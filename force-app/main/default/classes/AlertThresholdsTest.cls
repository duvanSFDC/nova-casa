@IsTest
private class AlertThresholdsTest {
    @IsTest
    static void catalogAndClassifierShareOneQuery() {
        AlertThresholdTestData.save(
            new List<Alert_Threshold__c>{
                new Alert_Threshold__c(
                    Asset_Type__c = 'WATER_PUMP',
                    Measurement_Type__c = 'WATER_PRESSURE',
                    Unit__c = 'BAR',
                    Alert_Direction__c = 'Below',
                    Warning_Limit__c = 1.5,
                    Critical_Limit__c = 1.0
                )
            }
        );

        Integer queriesBefore = Limits.getQueries();
        MeasurementCatalog catalog = MeasurementCatalog.load();
        MeasurementSeverityClassifier classifier = MeasurementSeverityClassifier.load();
        Assert.areEqual(1, Limits.getQueries() - queriesBefore, 'Los dos leen la misma consulta');

        Assert.areEqual('BAR', catalog.unitFor('WATER_PUMP', 'WATER_PRESSURE'));
        Assert.areEqual('Critical', classifier.classify('WATER_PUMP', 'WATER_PRESSURE', 1.0).severity);
    }

    @IsTest
    static void withoutThresholdsNothingIsAccepted() {
        Assert.isNull(MeasurementCatalog.load().unitFor('WATER_PUMP', 'WATER_PRESSURE'));
        Assert.areEqual(
            MeasurementSeverityClassifier.REASON_THRESHOLD_MISSING,
            MeasurementSeverityClassifier.load().classify('WATER_PUMP', 'WATER_PRESSURE', 1.0).reason
        );
    }
}
