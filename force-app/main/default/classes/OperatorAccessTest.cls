/**
 * BR-208: cada usuario recibe solo lo que su rol y sus edificios permiten, también cuando
 * le pide los datos directamente a Apex. Los usuarios usan el perfil mínimo, así que todo
 * lo que pueden hacer sale de los permission sets y de las reglas de compartición.
 */
@IsTest
private class OperatorAccessTest {
    @IsTest
    static void anOperatorSeesOnlyHerBuilding() {
        Fixture data = new Fixture();

        System.runAs(data.alamedaOperator) {
            OperatorStatusService.Result result = OperatorStatusService.getAssets(null, null);
            System.assertEquals(2, result.rows.size(), 'The pump reading and the light without reading.');
            for (OperatorStatusService.Row row : result.rows) {
                System.assertEquals(data.alameda.Id, row.buildingId);
            }
            System.assertNotEquals(null, row(result, data.alamedaPump.Id).workOrderId);

            List<OperatorStatusService.Building> buildings = OperatorStatusService.getBuildings();
            System.assertEquals(1, buildings.size());
            System.assertEquals(data.alameda.Id, buildings[0].buildingId);
        }

        System.runAs(data.miradorOperator) {
            OperatorStatusService.Result result = OperatorStatusService.getAssets(null, null);
            System.assertEquals(1, result.rows.size());
            System.assertEquals(data.miradorPump.Id, result.rows[0].assetId);
            System.assertEquals(null, result.rows[0].workOrderId, 'The Alameda work order is not hers.');
        }
    }

    @IsTest
    static void askingApexForAnotherBuildingReturnsNothing() {
        Fixture data = new Fixture();

        System.runAs(data.alamedaOperator) {
            OperatorStatusService.Result result = OperatorStatusService.getAssets(data.mirador.Id, null);
            System.assertEquals(0, result.rows.size());

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Asset_Condition__c WHERE Asset__c = :data.miradorPump.Id WITH USER_MODE]
            );
            System.assertEquals(0, [SELECT COUNT() FROM Asset WHERE Id = :data.miradorPump.Id WITH USER_MODE]);
            System.assertEquals(0, [SELECT COUNT() FROM Location WHERE Id = :data.mirador.Id WITH USER_MODE]);
        }
    }

    @IsTest
    static void anOperatorCannotChangeReadingsOrWorkOrders() {
        Fixture data = new Fixture();

        System.runAs(data.alamedaOperator) {
            Asset_Condition__c reading = [SELECT Id FROM Asset_Condition__c WHERE Asset__c = :data.alamedaPump.Id];
            reading.Severity__c = 'Normal';
            assertDenied(reading, 'edit a reading');

            WorkOrder order = [SELECT Id FROM WorkOrder WHERE Id = :data.alamedaOrder.Id];
            order.Status = 'Closed';
            assertDenied(order, 'close a work order');

            try {
                Database.insert(new WorkOrder(Subject = 'Manual', AssetId = data.alamedaPump.Id), AccessLevel.USER_MODE);
                System.assert(false, 'An operator should not create work orders.');
            } catch (Exception expected) {
                System.assertEquals(0, [SELECT COUNT() FROM WorkOrder WHERE Subject = 'Manual' WITH SYSTEM_MODE]);
            }
        }
    }

    @IsTest
    static void respectsFieldPermissionsBesidesRecordAccess() {
        Fixture data = new Fixture();

        System.runAs(data.alamedaOperator) {
            try {
                List<Asset_Condition__c> readings = [
                    SELECT Id, Sensor_Id__c
                    FROM Asset_Condition__c
                    WHERE Asset__c = :data.alamedaPump.Id
                    WITH USER_MODE
                ];
                System.assert(false, 'Sensor Id is not part of the operator view.');
            } catch (QueryException expected) {
                System.assert(expected.getMessage().contains('Sensor_Id__c'), expected.getMessage());
            }
        }
    }

    @IsTest
    static void onlyTheAdministratorReadsTechnicalErrors() {
        Fixture data = new Fixture();

        for (User person : new List<User>{ data.alamedaOperator, data.coordinator }) {
            System.runAs(person) {
                try {
                    List<Signal_Log__c> logs = [SELECT Id FROM Signal_Log__c WITH USER_MODE];
                    System.assert(false, person.LastName + ' should not read technical errors.');
                } catch (QueryException expected) {
                    System.assert(expected.getMessage().contains('Signal_Log__c'), expected.getMessage());
                }
            }
        }

        System.runAs(data.administrator) {
            System.assertEquals(1, [SELECT COUNT() FROM Signal_Log__c WITH USER_MODE]);
        }
    }

    @IsTest
    static void theCoordinatorSeesEveryBuildingAndMovesWorkOrders() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            OperatorStatusService.Result result = OperatorStatusService.getAssets(null, null);
            Set<Id> buildings = new Set<Id>();
            for (OperatorStatusService.Row row : result.rows) {
                buildings.add(row.buildingId);
            }
            System.assertEquals(new Set<Id>{ data.alameda.Id, data.mirador.Id }, buildings);

            WorkOrder order = [SELECT Id FROM WorkOrder WHERE Id = :data.alamedaOrder.Id];
            order.Status = 'In Progress';
            Database.update(order, AccessLevel.USER_MODE);

            try {
                Database.insert(new WorkOrder(Subject = 'Manual', AssetId = data.alamedaPump.Id), AccessLevel.USER_MODE);
                System.assert(false, 'Work orders are opened by the ingestion, not by hand.');
            } catch (Exception expected) {
                System.assertEquals(0, [SELECT COUNT() FROM WorkOrder WHERE Subject = 'Manual' WITH SYSTEM_MODE]);
            }
        }
        System.assertEquals('In Progress', [SELECT Status FROM WorkOrder WHERE Id = :data.alamedaOrder.Id].Status);
    }

    @IsTest
    static void aUserWithoutTheOperatorPermissionGetsAnError() {
        Fixture data = new Fixture();

        System.runAs(data.withoutAccess) {
            try {
                OperatorStatusService.getAssets(null, null);
                System.assert(false, 'A user without access should not get the list.');
            } catch (AuraHandledException expected) {
                System.assertEquals('No pudimos consultar los equipos.', expected.getMessage());
            }
        }
    }

    private static void assertDenied(SObject record, String action) {
        try {
            Database.update(record, AccessLevel.USER_MODE);
            System.assert(false, 'An operator should not ' + action + '.');
        } catch (Exception expected) {
            System.assert(
                !(expected instanceof System.AssertException),
                'An operator should not ' + action + '.'
            );
        }
    }

    private static OperatorStatusService.Row row(OperatorStatusService.Result result, Id assetId) {
        for (OperatorStatusService.Row candidate : result.rows) {
            if (candidate.assetId == assetId && candidate.hasReading) {
                return candidate;
            }
        }
        System.assert(false, 'Missing reading for ' + assetId);
        return null;
    }

    private class Fixture {
        User alamedaOperator;
        User miradorOperator;
        User coordinator;
        User administrator;
        User withoutAccess;
        Schema.Location alameda;
        Schema.Location mirador;
        Asset alamedaPump;
        Asset miradorPump;
        WorkOrder alamedaOrder;

        Fixture() {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                alamedaOperator = person('opbog', 'Nova_Operator', 'Nova_Building_BOG');
                miradorOperator = person('opmde', 'Nova_Operator', 'Nova_Building_MDE');
                coordinator = person('coord', 'Nova_Coordinator', 'Nova_Coordination');
                administrator = person('admin', 'Nova_Admin', null);
                withoutAccess = person('noacc', null, null);
            }

            Account account = new Account(Name = 'Nova Casa Test');
            Database.insert(account, AccessLevel.SYSTEM_MODE);
            alameda = location('Alameda', 'BLD-BOG-001');
            mirador = location('Mirador', 'BLD-MDE-001');
            Database.insert(new List<Schema.Location>{ alameda, mirador }, AccessLevel.SYSTEM_MODE);
            alamedaPump = asset('Bomba Alameda', account, alameda);
            Asset alamedaLight = asset('Luz Alameda', account, alameda);
            miradorPump = asset('Bomba Mirador', account, mirador);
            Database.insert(new List<Asset>{ alamedaPump, alamedaLight, miradorPump }, AccessLevel.SYSTEM_MODE);
            Database.insert(
                new List<Asset_Condition__c>{ reading(alamedaPump, 'Critical'), reading(miradorPump, 'Warning') },
                AccessLevel.SYSTEM_MODE
            );
            alamedaOrder = new WorkOrder(
                Subject = 'Presión crítica',
                Status = 'New',
                AccountId = account.Id,
                AssetId = alamedaPump.Id,
                LocationId = alameda.Id,
                IsStopped = false
            );
            Database.insert(alamedaOrder, AccessLevel.SYSTEM_MODE);
            Database.insert(new Signal_Log__c(Event_Uuid__c = 'evt-us208-test'), AccessLevel.SYSTEM_MODE);
            grantWhatTheSharingRulesGrant();
        }

        /**
         * Las reglas de compartición por criterio no se evalúan dentro de las pruebas Apex,
         * así que aquí se da el mismo acceso que dan en la org: cada edificio en lectura a su
         * grupo, y a coordinación lectura más edición de las intervenciones.
         */
        void grantWhatTheSharingRulesGrant() {
            Map<String, Id> groupByCode = new Map<String, Id>();
            Id coordination;
            for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName LIKE 'Nova_%']) {
                if (g.DeveloperName == 'Nova_Coordination') {
                    coordination = g.Id;
                } else {
                    groupByCode.put('BLD-' + g.DeveloperName.substringAfterLast('_') + '-001', g.Id);
                }
            }
            List<SObject> shares = new List<SObject>();
            for (Schema.Location building : [SELECT Id, External_Id__c FROM Location WITH SYSTEM_MODE]) {
                for (Id grantee : new List<Id>{ groupByCode.get(building.External_Id__c), coordination }) {
                    shares.add(new LocationShare(ParentId = building.Id, UserOrGroupId = grantee, AccessLevel = 'Read'));
                }
            }
            for (Asset equipment : [SELECT Id, Building_Code__c FROM Asset WITH SYSTEM_MODE]) {
                for (Id grantee : new List<Id>{ groupByCode.get(equipment.Building_Code__c), coordination }) {
                    shares.add(new AssetShare(AssetId = equipment.Id, UserOrGroupId = grantee, AssetAccessLevel = 'Read'));
                }
            }
            for (Asset_Condition__c reading : [SELECT Id, Building_Code__c FROM Asset_Condition__c WITH SYSTEM_MODE]) {
                for (Id grantee : new List<Id>{ groupByCode.get(reading.Building_Code__c), coordination }) {
                    shares.add(
                        new Asset_Condition__Share(ParentId = reading.Id, UserOrGroupId = grantee, AccessLevel = 'Read')
                    );
                }
            }
            for (WorkOrder order : [SELECT Id, Building_Code__c FROM WorkOrder WITH SYSTEM_MODE]) {
                shares.add(
                    new WorkOrderShare(
                        ParentId = order.Id,
                        UserOrGroupId = groupByCode.get(order.Building_Code__c),
                        AccessLevel = 'Read'
                    )
                );
                shares.add(new WorkOrderShare(ParentId = order.Id, UserOrGroupId = coordination, AccessLevel = 'Edit'));
            }
            Database.insert(shares, AccessLevel.SYSTEM_MODE);
        }

        User person(String alias, String permissionSet, String groupName) {
            User u = new User(
                Alias = alias,
                FirstName = 'Test',
                LastName = alias,
                Username = alias + '.' + Datetime.now().getTime() + '@us208.test',
                Email = alias + '@us208.test',
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
            if (groupName != null) {
                insert new GroupMember(
                    UserOrGroupId = u.Id,
                    GroupId = [SELECT Id FROM Group WHERE DeveloperName = :groupName].Id
                );
            }
            return u;
        }

        Schema.Location location(String name, String code) {
            return new Schema.Location(
                Name = name,
                External_Id__c = code,
                LocationType = 'Site',
                IsMobile = false,
                IsInventoryLocation = false,
                ShouldSyncWithOci = false,
                IsEligibleForPickup = false
            );
        }

        Asset asset(String name, Account account, Schema.Location building) {
            return new Asset(
                Name = name,
                AccountId = account.Id,
                LocationId = building.Id,
                IsCompetitorProduct = false,
                IsInternal = false
            );
        }

        Asset_Condition__c reading(Asset equipment, String severity) {
            return new Asset_Condition__c(
                Name = equipment.Id + ':WATER_PRESSURE',
                Asset__c = equipment.Id,
                Measurement_Type__c = 'WATER_PRESSURE',
                Measurement_Value__c = 1.2,
                Measurement_Unit__c = 'BAR',
                Severity__c = severity,
                Occurred_At__c = Datetime.now(),
                Asset_Measurement_Key__c = equipment.Id + ':WATER_PRESSURE'
            );
        }
    }
}
