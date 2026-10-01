@IsTest
private class MeasurementSeverityClassifierTest {
    private static Measurement_Threshold__mdt threshold(String assetType, String measurementType, String direction, Decimal warning, Decimal critical) {
        return new Measurement_Threshold__mdt(
            Asset_Type__c = assetType,
            Measurement_Type__c = measurementType,
            Alert_Direction__c = direction,
            Warning_Limit__c = warning,
            Critical_Limit__c = critical
        );
    }

    /** Mismos límites de ejemplo que la CMDT desplegada, para no depender de que alguien la edite. */
    private static MeasurementSeverityClassifier useThresholds() {
        MeasurementSeverityClassifier.testRecords = new List<Measurement_Threshold__mdt>{
            threshold('WATER_PUMP', 'WATER_PRESSURE', 'Below', 1.5, 1.0),
            threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'Above', 30, 35)
        };
        return MeasurementSeverityClassifier.load();
    }

    private static String severityOf(MeasurementSeverityClassifier classifier, String assetType, String measurementType, Decimal value) {
        MeasurementSeverityClassifier.Classification result = classifier.classify(assetType, measurementType, value);
        Assert.isTrue(result.isClassified(), 'Se esperaba una severidad para ' + value + ': ' + result.detail);
        return result.severity;
    }

    @IsTest
    static void lowIsBadOwnsTheExactLimit() {
        MeasurementSeverityClassifier classifier = useThresholds();

        Assert.areEqual('Normal', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 2.0));
        Assert.areEqual('Normal', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 1.5001));
        Assert.areEqual('Warning', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 1.5), 'El límite exacto de advertencia ya es Warning.');
        Assert.areEqual('Warning', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 1.2));
        Assert.areEqual('Warning', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 1.0001));
        Assert.areEqual('Critical', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 1.0), 'El límite exacto crítico ya es Critical.');
        Assert.areEqual('Critical', severityOf(classifier, 'WATER_PUMP', 'WATER_PRESSURE', 0.7));
    }

    @IsTest
    static void highIsBadOwnsTheExactLimit() {
        MeasurementSeverityClassifier classifier = useThresholds();

        Assert.areEqual('Normal', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 22.5));
        Assert.areEqual('Normal', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 29.9999));
        Assert.areEqual('Warning', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 30), 'El límite exacto de advertencia ya es Warning.');
        Assert.areEqual('Warning', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 34.9999));
        Assert.areEqual('Critical', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 35), 'El límite exacto crítico ya es Critical.');
        Assert.areEqual('Critical', severityOf(classifier, 'TECHNICAL_ROOM', 'TEMPERATURE', 40));
    }

    @IsTest
    static void theSameValueFollowsTheCurrentLimit() {
        MeasurementSeverityClassifier.testRecords = new List<Measurement_Threshold__mdt>{
            threshold('WATER_PUMP', 'WATER_PRESSURE', 'Below', 1.5, 1.0)
        };
        Assert.areEqual('Warning', severityOf(MeasurementSeverityClassifier.load(), 'WATER_PUMP', 'WATER_PRESSURE', 1.2));

        MeasurementSeverityClassifier.testRecords = new List<Measurement_Threshold__mdt>{
            threshold('WATER_PUMP', 'WATER_PRESSURE', 'Below', 1.1, 1.0)
        };
        Assert.areEqual('Normal', severityOf(MeasurementSeverityClassifier.load(), 'WATER_PUMP', 'WATER_PRESSURE', 1.2), 'Con la advertencia en 1.1, 1.2 bar ya no es Warning.');
    }

    @IsTest
    static void comparesCodesWithoutCase() {
        MeasurementSeverityClassifier classifier = useThresholds();

        Assert.areEqual('Critical', severityOf(classifier, ' water_pump ', 'Water_Pressure', 0.7));
    }

    @IsTest
    static void aMeasurementWithoutThresholdsIsNotNormal() {
        MeasurementSeverityClassifier.Classification result = useThresholds().classify('ENERGY_METER', 'ENERGY_CONSUMPTION', 10);

        Assert.isFalse(result.isClassified());
        Assert.isNull(result.severity);
        Assert.areEqual(MeasurementSeverityClassifier.REASON_THRESHOLD_MISSING, result.reason);
        Assert.areEqual('No hay límites configurados para "ENERGY_CONSUMPTION" de "ENERGY_METER".', result.detail);
    }

    @IsTest
    static void anIncompleteThresholdIsNotNormal() {
        MeasurementSeverityClassifier.testRecords = new List<Measurement_Threshold__mdt>{
            threshold('WATER_PUMP', 'WATER_PRESSURE', null, 1.5, null)
        };
        MeasurementSeverityClassifier.Classification result = MeasurementSeverityClassifier.load().classify('WATER_PUMP', 'WATER_PRESSURE', 2.0);

        Assert.isFalse(result.isClassified());
        Assert.areEqual(MeasurementSeverityClassifier.REASON_THRESHOLD_INCOMPLETE, result.reason);
        Assert.areEqual('Faltan Alert Direction, Critical Limit en los límites de "WATER_PRESSURE" de "WATER_PUMP".', result.detail);
    }

    @IsTest
    static void aContradictoryRangeIsNotNormal() {
        MeasurementSeverityClassifier.testRecords = new List<Measurement_Threshold__mdt>{
            threshold('WATER_PUMP', 'WATER_PRESSURE', 'Below', 1.0, 1.5),
            threshold('TECHNICAL_ROOM', 'TEMPERATURE', 'Above', 30, 30)
        };
        MeasurementSeverityClassifier classifier = MeasurementSeverityClassifier.load();

        MeasurementSeverityClassifier.Classification pump = classifier.classify('WATER_PUMP', 'WATER_PRESSURE', 2.0);
        Assert.isFalse(pump.isClassified(), 'Con Below, un crítico por encima de la advertencia es contradictorio.');
        Assert.areEqual(MeasurementSeverityClassifier.REASON_THRESHOLD_CONTRADICTORY, pump.reason);
        Assert.areEqual(
            'Los límites de "WATER_PRESSURE" de "WATER_PUMP" son contradictorios: con dirección Below, el crítico (1.5) tiene que estar por debajo de la advertencia (1.0).',
            pump.detail
        );

        MeasurementSeverityClassifier.Classification room = classifier.classify('TECHNICAL_ROOM', 'TEMPERATURE', 22.5);
        Assert.isFalse(room.isClassified(), 'Límites iguales dejan sin banda de advertencia.');
        Assert.areEqual(MeasurementSeverityClassifier.REASON_THRESHOLD_CONTRADICTORY, room.reason);
    }

    @IsTest
    static void readsTheDeployedThresholds() {
        Measurement_Threshold__mdt deployed = Measurement_Threshold__mdt.getInstance('WATER_PUMP_WATER_PRESSURE');
        MeasurementSeverityClassifier.Classification result = MeasurementSeverityClassifier.load()
            .classify(deployed.Asset_Type__c, deployed.Measurement_Type__c, deployed.Critical_Limit__c);

        Assert.areEqual('Critical', result.severity, 'El límite crítico guardado en Setup tiene que dar Critical.');
    }
}
