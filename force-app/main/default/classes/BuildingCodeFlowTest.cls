@IsTest
private class BuildingCodeFlowTest {
    @IsTest
    static void copiesTheBuildingCodeToAssetConditionAndWorkOrder() {
        Fixture data = new Fixture();

        System.assertEquals('BLD-TST-001', [SELECT Building_Code__c FROM Asset WHERE Id = :data.pump.Id].Building_Code__c);
        System.assertEquals(
            'BLD-TST-001',
            [SELECT Building_Code__c FROM Asset_Condition__c WHERE Id = :data.condition.Id].Building_Code__c
        );
        System.assertEquals(
            'BLD-TST-001',
            [SELECT Building_Code__c FROM WorkOrder WHERE Id = :data.order.Id].Building_Code__c
        );
    }

    @IsTest
    static void followsTheAssetWhenItMovesToAnotherBuilding() {
        Fixture data = new Fixture();

        data.pump.LocationId = data.sur.Id;
        update data.pump;
        update data.condition;

        System.assertEquals('BLD-TST-002', [SELECT Building_Code__c FROM Asset WHERE Id = :data.pump.Id].Building_Code__c);
        System.assertEquals(
            'BLD-TST-002',
            [SELECT Building_Code__c FROM Asset_Condition__c WHERE Id = :data.condition.Id].Building_Code__c
        );
    }

    @IsTest
    static void ignoresAManualValue() {
        Fixture data = new Fixture();

        data.condition.Building_Code__c = 'BLD-OTRO';
        update data.condition;

        System.assertEquals(
            'BLD-TST-001',
            [SELECT Building_Code__c FROM Asset_Condition__c WHERE Id = :data.condition.Id].Building_Code__c
        );
    }

    private class Fixture {
        Schema.Location norte;
        Schema.Location sur;
        Asset pump;
        Asset_Condition__c condition;
        WorkOrder order;

        Fixture() {
            Account account = new Account(Name = 'Nova Casa Test');
            Database.insert(account, AccessLevel.SYSTEM_MODE);
            norte = location('Norte', 'BLD-TST-001');
            sur = location('Sur', 'BLD-TST-002');
            Database.insert(new List<Schema.Location>{ norte, sur }, AccessLevel.SYSTEM_MODE);
            pump = new Asset(
                Name = 'Bomba',
                AccountId = account.Id,
                LocationId = norte.Id,
                IsCompetitorProduct = false,
                IsInternal = false
            );
            Database.insert(pump, AccessLevel.SYSTEM_MODE);
            condition = new Asset_Condition__c(
                Name = pump.Id + ':WATER_PRESSURE',
                Asset__c = pump.Id,
                Measurement_Type__c = 'WATER_PRESSURE',
                Severity__c = 'Normal',
                Occurred_At__c = Datetime.now(),
                Asset_Measurement_Key__c = pump.Id + ':WATER_PRESSURE'
            );
            Database.insert(condition, AccessLevel.SYSTEM_MODE);
            order = new WorkOrder(
                Subject = 'Bomba',
                Status = 'New',
                AccountId = account.Id,
                AssetId = pump.Id,
                LocationId = norte.Id,
                IsStopped = false
            );
            Database.insert(order, AccessLevel.SYSTEM_MODE);
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
    }
}
