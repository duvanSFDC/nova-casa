@IsTest
private class OperatorStatusServiceTest {
    @IsTest
    static void returnsOneRowPerReadingAndOneForAnAssetWithoutReading() {
        Fixture data = new Fixture();
        Datetime occurredAt = Datetime.newInstance(2026, 9, 29, 10, 5, 0);
        data.condition(data.pump, 'pressure', 0.7, 'bar', 'Critical', occurredAt);
        data.condition(data.pump, 'temperature', 40, '°C', 'Warning', occurredAt);
        data.workOrder(data.pump, 'New');

        OperatorStatusService.Result result = OperatorStatusService.getAssets(null, null);

        System.assertNotEquals(null, result.consultedAt);
        System.assertEquals(4, result.rows.size(), 'Two pump readings, plus the light and the fan without a reading.');

        OperatorStatusService.Row pressure = row(result, data.pump.Id, 'pressure');
        System.assertEquals(true, pressure.hasReading);
        System.assertEquals(0.7, pressure.measurementValue);
        System.assertEquals('bar', pressure.measurementUnit);
        System.assertEquals('Critical', pressure.severity);
        System.assertEquals(occurredAt, pressure.occurredAt);
        System.assertEquals('Norte', pressure.buildingName);
        System.assertNotEquals(null, pressure.workOrderId);

        OperatorStatusService.Row temperature = row(result, data.pump.Id, 'temperature');
        System.assertEquals('Warning', temperature.severity);
        System.assertEquals(pressure.workOrderId, temperature.workOrderId);

        OperatorStatusService.Row light = row(result, data.light.Id, null);
        System.assertEquals(false, light.hasReading);
        System.assertEquals(null, light.severity);
        System.assertEquals(null, light.occurredAt);
        System.assertEquals(null, light.workOrderId);
        System.assertEquals(data.light.Id + ':none', light.rowKey);

        OperatorStatusService.Row fan = row(result, data.fan.Id, null);
        System.assertEquals(false, fan.hasReading);
        System.assertEquals('Sur', fan.buildingName);
    }

    @IsTest
    static void filtersByBuildingAndSeverity() {
        Fixture data = new Fixture();
        Datetime occurredAt = Datetime.newInstance(2026, 9, 29, 10, 5, 0);
        data.condition(data.pump, 'pressure', 0.7, 'bar', 'Critical', occurredAt);
        data.condition(data.fan, 'temperature', 22.5, '°C', 'Normal', occurredAt);

        OperatorStatusService.Result norte = OperatorStatusService.getAssets(data.norte.Id, null);
        System.assertEquals(2, norte.rows.size());
        System.assertEquals(data.pump.Id, norte.rows[0].assetId);
        System.assertEquals(data.light.Id, norte.rows[1].assetId);

        OperatorStatusService.Result critical = OperatorStatusService.getAssets(null, 'Critical');
        System.assertEquals(1, critical.rows.size());
        System.assertEquals('pressure', critical.rows[0].measurementType);

        OperatorStatusService.Result none = OperatorStatusService.getAssets(data.sur.Id, 'Critical');
        System.assertEquals(0, none.rows.size());
        System.assertNotEquals(null, none.consultedAt);
    }

    @IsTest
    static void keepsTheOldestOpenWorkOrder() {
        Fixture data = new Fixture();
        data.condition(data.pump, 'pressure', 0.7, 'bar', 'Critical', Datetime.now());
        WorkOrder first = data.workOrder(data.pump, 'New');
        data.workOrder(data.pump, 'In Progress');
        data.workOrder(data.fan, 'Closed');
        data.condition(data.fan, 'temperature', 22.5, '°C', 'Normal', Datetime.now());

        Id expected = [
            SELECT Id
            FROM WorkOrder
            WHERE AssetId = :data.pump.Id AND IsClosed = false
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 1
        ].Id;

        OperatorStatusService.Result result = OperatorStatusService.getAssets(null, null);
        System.assertEquals(expected, row(result, data.pump.Id, 'pressure').workOrderId);
        System.assertEquals(first.Id, expected);
        System.assertEquals(null, row(result, data.fan.Id, 'temperature').workOrderId);
    }

    @IsTest
    static void rejectsAnUnknownSeverity() {
        try {
            OperatorStatusService.getAssets(null, 'Urgent');
            System.assert(false, 'An unknown severity should fail.');
        } catch (AuraHandledException error) {
            System.assertEquals('Severidad no reconocida.', error.getMessage());
        }
    }

    @IsTest
    static void listsBuildingsThatHaveAssets() {
        Fixture data = new Fixture();

        List<OperatorStatusService.Building> buildings = OperatorStatusService.getBuildings();

        System.assertEquals(2, buildings.size());
        System.assertEquals('Norte', buildings[0].buildingName);
        System.assertEquals(data.norte.Id, buildings[0].buildingId);
        System.assertEquals('Sur', buildings[1].buildingName);
    }

    private static OperatorStatusService.Row row(OperatorStatusService.Result result, Id assetId, String measurementType) {
        for (OperatorStatusService.Row candidate : result.rows) {
            if (candidate.assetId == assetId && candidate.measurementType == measurementType) {
                return candidate;
            }
        }
        System.assert(false, 'Missing row for ' + assetId + ' ' + measurementType);
        return null;
    }

    private class Fixture {
        Account account;
        Schema.Location norte;
        Schema.Location sur;
        Asset pump;
        Asset light;
        Asset fan;

        Fixture() {
            account = new Account(Name = 'Nova Casa Test');
            insert account;
            norte = location('Norte');
            sur = location('Sur');
            insert new List<Schema.Location>{ norte, sur };
            pump = asset('Bomba', norte);
            light = asset('Luz', norte);
            fan = asset('Ventilación', sur);
            insert new List<Asset>{ pump, light, fan };
        }

        Schema.Location location(String name) {
            return new Schema.Location(
                Name = name,
                LocationType = 'Site',
                IsMobile = false,
                IsInventoryLocation = false,
                ShouldSyncWithOci = false,
                IsEligibleForPickup = false
            );
        }

        Asset asset(String name, Schema.Location building) {
            return new Asset(
                Name = name,
                AccountId = account.Id,
                LocationId = building.Id,
                IsCompetitorProduct = false,
                IsInternal = false
            );
        }

        void condition(Asset equipment, String type, Decimal value, String unit, String severity, Datetime occurredAt) {
            insert new Asset_Condition__c(
                Name = equipment.Name + ' · ' + type,
                Asset__c = equipment.Id,
                Measurement_Type__c = type,
                Measurement_Value__c = value,
                Measurement_Unit__c = unit,
                Severity__c = severity,
                Occurred_At__c = occurredAt,
                Asset_Measurement_Key__c = equipment.Id + ':' + type
            );
        }

        WorkOrder workOrder(Asset equipment, String status) {
            WorkOrder order = new WorkOrder(
                Subject = equipment.Name,
                Status = status,
                AccountId = account.Id,
                AssetId = equipment.Id,
                LocationId = equipment.LocationId,
                IsStopped = false
            );
            insert order;
            return order;
        }
    }
}