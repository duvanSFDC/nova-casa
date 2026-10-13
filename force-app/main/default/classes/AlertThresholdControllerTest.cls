@IsTest
private class AlertThresholdControllerTest {
    @IsTest
    static void theCoordinatorSeesReadableThresholds() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            List<AlertThresholdController.Row> rows = AlertThresholdController.getThresholds();
            Assert.areEqual(2, rows.size());

            AlertThresholdController.Row pump = rowFor(rows, data.pump.Id);
            Assert.areEqual('Bomba de agua · presión de agua', pump.name);
            Assert.areEqual('bar', pump.unitLabel);
            Assert.areEqual('Below', pump.direction);
            Assert.areEqual(1.5, pump.warningLimit);
            Assert.areEqual(1.0, pump.criticalLimit);
            Assert.isTrue(pump.canEdit);
            Assert.isNotNull(pump.lastModifiedAt);
        }
    }

    @IsTest
    static void theCoordinatorSavesBothLimits() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            List<AlertThresholdController.SaveError> errors = AlertThresholdController.saveLimits(
                new List<AlertThresholdController.LimitChange>{ change(data.pump.Id, 1.8, 1.2) }
            );
            Assert.areEqual(0, errors.size(), String.valueOf(errors));
        }

        Alert_Threshold__c saved = [
            SELECT Warning_Limit__c, Critical_Limit__c, Unit__c
            FROM Alert_Threshold__c
            WHERE Id = :data.pump.Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1.8, saved.Warning_Limit__c);
        Assert.areEqual(1.2, saved.Critical_Limit__c);
        Assert.areEqual('BAR', saved.Unit__c);
    }

    @IsTest
    static void aBadChangeComesBackWithItsReasonAndTheGoodOneIsSaved() {
        Fixture data = new Fixture();

        List<AlertThresholdController.SaveError> errors;
        System.runAs(data.coordinator) {
            errors = AlertThresholdController.saveLimits(
                new List<AlertThresholdController.LimitChange>{
                    change(data.pump.Id, 1.0, 1.5),
                    change(data.room.Id, 32, 38)
                }
            );
        }

        Assert.areEqual(1, errors.size());
        Assert.areEqual(data.pump.Id, errors[0].id);
        Assert.isTrue(errors[0].message.contains('El límite crítico tiene que ser más grave'), errors[0].message);

        Map<Id, Alert_Threshold__c> saved = new Map<Id, Alert_Threshold__c>(
            [SELECT Warning_Limit__c, Critical_Limit__c FROM Alert_Threshold__c WITH SYSTEM_MODE]
        );
        Assert.areEqual(1.5, saved.get(data.pump.Id).Warning_Limit__c, 'La bomba se queda como estaba');
        Assert.areEqual(38, saved.get(data.room.Id).Critical_Limit__c, 'El cuarto técnico sí se guarda');
    }

    @IsTest
    static void anEmptyLimitIsRejected() {
        Fixture data = new Fixture();

        System.runAs(data.coordinator) {
            List<AlertThresholdController.SaveError> errors = AlertThresholdController.saveLimits(
                new List<AlertThresholdController.LimitChange>{ change(data.pump.Id, null, 1.0) }
            );
            Assert.areEqual(1, errors.size());
            Assert.isTrue(errors[0].message.contains('Faltan datos'), errors[0].message);
        }
    }

    @IsTest
    static void anOperatorCannotSeeOrChangeThresholds() {
        Fixture data = new Fixture();

        System.runAs(data.operator) {
            try {
                AlertThresholdController.getThresholds();
                Assert.fail('An operator should not read thresholds.');
            } catch (AuraHandledException expected) {
                Assert.areEqual('No pudimos consultar los umbrales.', expected.getMessage());
            }

            try {
                AlertThresholdController.saveLimits(
                    new List<AlertThresholdController.LimitChange>{ change(data.pump.Id, 1.8, 1.2) }
                );
                Assert.fail('An operator should not change thresholds.');
            } catch (AuraHandledException expected) {
                Assert.areEqual('No tienes permiso para cambiar los umbrales.', expected.getMessage());
            }
        }
        Assert.areEqual(1.5, [SELECT Warning_Limit__c FROM Alert_Threshold__c WHERE Id = :data.pump.Id WITH SYSTEM_MODE].Warning_Limit__c);
    }

    private static AlertThresholdController.LimitChange change(Id thresholdId, Decimal warning, Decimal critical) {
        AlertThresholdController.LimitChange change = new AlertThresholdController.LimitChange();
        change.id = thresholdId;
        change.warningLimit = warning;
        change.criticalLimit = critical;
        return change;
    }

    private static AlertThresholdController.Row rowFor(List<AlertThresholdController.Row> rows, Id thresholdId) {
        for (AlertThresholdController.Row row : rows) {
            if (row.id == thresholdId) {
                return row;
            }
        }
        Assert.fail('Missing threshold ' + thresholdId);
        return null;
    }

    private class Fixture {
        User coordinator;
        User operator;
        Alert_Threshold__c pump;
        Alert_Threshold__c room;

        Fixture() {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                coordinator = person('coord', 'Nova_Coordinator');
                operator = person('opbog', 'Nova_Operator');
            }
            pump = new Alert_Threshold__c(Asset_Type__c = 'WATER_PUMP', Measurement_Type__c = 'WATER_PRESSURE', Unit__c = 'BAR',
                Alert_Direction__c = 'Below', Warning_Limit__c = 1.5, Critical_Limit__c = 1.0);
            room = new Alert_Threshold__c(Asset_Type__c = 'TECHNICAL_ROOM', Measurement_Type__c = 'TEMPERATURE', Unit__c = 'CELSIUS',
                Alert_Direction__c = 'Above', Warning_Limit__c = 30, Critical_Limit__c = 35);
            AlertThresholdTestData.save(new List<Alert_Threshold__c>{ pump, room });
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
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSet].Id
            );
            return u;
        }
    }
}
