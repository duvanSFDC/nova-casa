/**
 * Los umbrales son un objeto y no Custom Metadata para que la coordinación ajuste los límites
 * con un permiso de objeto, sin Customize Application ni permisos de metadata. Javier edita
 * solo los dos límites; el resto del umbral, crear y borrar quedan fuera de su permiso, y las
 * reglas de validación impiden guardar un umbral incompleto, contradictorio o repetido.
 */
@IsTest
private class AlertThresholdAccessTest {
    @IsTest
    static void theCoordinatorAdjustsTheLimits() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            Alert_Threshold__c threshold = [
                SELECT Id, Warning_Limit__c, Critical_Limit__c
                FROM Alert_Threshold__c
                WHERE Id = :data.pump.Id
                WITH USER_MODE
            ];
            threshold.Warning_Limit__c = 1.8;
            threshold.Critical_Limit__c = 1.2;
            Database.update(threshold, AccessLevel.USER_MODE);
        }

        Alert_Threshold__c saved = [
            SELECT Warning_Limit__c, Critical_Limit__c
            FROM Alert_Threshold__c
            WHERE Id = :data.pump.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1.8, saved.Warning_Limit__c);
        System.assertEquals(1.2, saved.Critical_Limit__c);
    }

    @IsTest
    static void theCoordinatorChangesNothingElse() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            assertDenied(new Alert_Threshold__c(Id = data.pump.Id, Unit__c = 'PSI'), 'change the unit');
            assertDenied(
                new Alert_Threshold__c(Id = data.pump.Id, Alert_Direction__c = 'Above'),
                'change the direction'
            );
            assertDenied(
                new Alert_Threshold__c(Id = data.pump.Id, Asset_Type__c = 'FAN'),
                'change the asset type'
            );

            try {
                Database.insert(threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'CELSIUS', 'Above', 30, 35), AccessLevel.USER_MODE);
                System.assert(false, 'The coordinator should not create thresholds.');
            } catch (Exception expected) {
                System.assert(!(expected instanceof System.AssertException), expected.getMessage());
            }

            try {
                Database.delete(new Alert_Threshold__c(Id = data.pump.Id), AccessLevel.USER_MODE);
                System.assert(false, 'The coordinator should not delete thresholds.');
            } catch (Exception expected) {
                System.assert(!(expected instanceof System.AssertException), expected.getMessage());
            }
        }

        Alert_Threshold__c saved = [
            SELECT Unit__c, Alert_Direction__c, Asset_Type__c
            FROM Alert_Threshold__c
            WHERE Id = :data.pump.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals('BAR', saved.Unit__c);
        System.assertEquals('Below', saved.Alert_Direction__c);
        System.assertEquals('WATER_PUMP', saved.Asset_Type__c);
        System.assertEquals(1, [SELECT COUNT() FROM Alert_Threshold__c WITH SYSTEM_MODE]);
    }

    @IsTest
    static void theAdministratorManagesThresholds() {
        Fixture data = new Fixture();

        System.runAs(data.administrator) {
            Alert_Threshold__c room = threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'CELSIUS', 'Above', 30, 35);
            Database.insert(room, AccessLevel.USER_MODE);
            room.Unit__c = 'FAHRENHEIT';
            Database.update(room, AccessLevel.USER_MODE);
            Database.delete(room, AccessLevel.USER_MODE);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Alert_Threshold__c WITH SYSTEM_MODE]);
    }

    @IsTest
    static void operatorsAndUsersWithoutAccessCannotReadThresholds() {
        Fixture data = new Fixture();

        for (User person : new List<User>{ data.operator, data.withoutAccess }) {
            System.runAs(person) {
                try {
                    List<Alert_Threshold__c> visible = [
                        SELECT Id, Warning_Limit__c
                        FROM Alert_Threshold__c
                        WITH USER_MODE
                    ];
                    System.assert(false, person.Alias + ' should not read thresholds.');
                } catch (QueryException expected) {
                    System.assert(expected.getMessage() != null);
                }
            }
        }
    }

    @IsTest
    static void theCoordinatorHasNoSetupOrMetadataPermissions() {
        Fixture data = new Fixture();

        List<PermissionSet> granted = [
            SELECT PermissionsCustomizeApplication, PermissionsModifyMetadata, PermissionsApiEnabled
            FROM PermissionSet
            WHERE Id IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :data.coordinator.Id)
        ];
        System.assertEquals(2, granted.size(), 'The profile and Nova_Coordinator.');
        for (PermissionSet permissions : granted) {
            System.assertEquals(false, permissions.PermissionsCustomizeApplication);
            System.assertEquals(false, permissions.PermissionsModifyMetadata);
            System.assertEquals(false, permissions.PermissionsApiEnabled);
        }
    }

    @IsTest
    static void contradictoryLimitsAreRejected() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            Alert_Threshold__c inverted = new Alert_Threshold__c(
                Id = data.pump.Id,
                Warning_Limit__c = 1.0,
                Critical_Limit__c = 1.5
            );
            assertRejectedWith(inverted, 'El límite crítico tiene que ser más grave');

            Alert_Threshold__c equal = new Alert_Threshold__c(
                Id = data.pump.Id,
                Warning_Limit__c = 1.5,
                Critical_Limit__c = 1.5
            );
            assertRejectedWith(equal, 'El límite crítico tiene que ser más grave');
        }

        Alert_Threshold__c hot = threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'CELSIUS', 'Above', 35, 30);
        assertRejectedWith(hot, 'El límite crítico tiene que ser más grave', AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void emptyLimitsAreRejected() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            Alert_Threshold__c blank = new Alert_Threshold__c(Id = data.pump.Id, Warning_Limit__c = null);
            assertRejectedWith(blank, 'Faltan datos');
        }

        Alert_Threshold__c withoutUnit = threshold('TECHNICAL_ROOM', 'TEMPERATURE', null, 'Above', 30, 35);
        assertRejectedWith(withoutUnit, 'Faltan datos', AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void oneThresholdPerAssetTypeAndMeasurement() {
        Fixture data = new Fixture();

        Alert_Threshold__c repeated = threshold('water_pump', 'water_pressure', 'BAR', 'Below', 2, 1);
        assertRejectedWith(repeated, 'DUPLICATE_VALUE', AccessLevel.SYSTEM_MODE);

        Alert_Threshold__c wrongKey = threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'CELSIUS', 'Above', 30, 35);
        wrongKey.Threshold_Key__c = 'WATER_PUMP|WATER_PRESSURE_2';
        assertRejectedWith(wrongKey, 'La clave tiene que ser', AccessLevel.SYSTEM_MODE);
    }

    private static Alert_Threshold__c threshold(
        String assetType,
        String measurementType,
        String unit,
        String direction,
        Decimal warning,
        Decimal critical
    ) {
        return new Alert_Threshold__c(
            Asset_Type__c = assetType,
            Measurement_Type__c = measurementType,
            Threshold_Key__c = assetType.toUpperCase() + '|' + measurementType.toUpperCase(),
            Unit__c = unit,
            Alert_Direction__c = direction,
            Warning_Limit__c = warning,
            Critical_Limit__c = critical
        );
    }

    private static void assertDenied(Alert_Threshold__c change, String action) {
        try {
            Database.update(change, AccessLevel.USER_MODE);
            System.assert(false, 'The coordinator should not ' + action + '.');
        } catch (Exception expected) {
            System.assert(!(expected instanceof System.AssertException), 'The coordinator should not ' + action + '.');
        }
    }

    private static void assertRejectedWith(Alert_Threshold__c record, String message) {
        assertRejectedWith(record, message, AccessLevel.USER_MODE);
    }

    private static void assertRejectedWith(Alert_Threshold__c record, String message, AccessLevel access) {
        Database.SaveResult result = record.Id == null
            ? Database.insert(record, false, access)
            : Database.update(record, false, access);
        System.assert(!result.isSuccess(), 'Expected a rejection containing: ' + message);
        String errors = '';
        for (Database.Error error : result.getErrors()) {
            errors += error.getStatusCode() + ' ' + error.getMessage() + ' ';
        }
        System.assert(errors.containsIgnoreCase(message), errors);
    }

    private class Fixture {
        User coordinator;
        User operator;
        User administrator;
        User withoutAccess;
        Alert_Threshold__c pump;

        Fixture() {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                coordinator = person('coord', 'Nova_Coordinator');
                operator = person('opbog', 'Nova_Operator');
                administrator = person('admin', 'Nova_Admin');
                withoutAccess = person('noacc', null);
            }
            pump = threshold('WATER_PUMP', 'WATER_PRESSURE', 'BAR', 'Below', 1.5, 1.0);
            Database.insert(pump, AccessLevel.SYSTEM_MODE);
        }

        User person(String alias, String permissionSet) {
            User u = new User(
                Alias = alias,
                FirstName = 'Test',
                LastName = alias,
                Username = alias + '.' + Datetime.now().getTime() + '@umbrales.test',
                Email = alias + '@umbrales.test',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
                TimeZoneSidKey = 'America/Bogota',
                LocaleSidKey = 'es_CO',
                LanguageLocaleKey = 'es',
                EmailEncodingKey = 'UTF-8'
            );
            insert u;
            if (permissionSet != null) {
                insert new PermissionSetAssignment(
                    AssigneeId = u.Id,
                    PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSet].Id
                );
            }
            return u;
        }
    }
}
