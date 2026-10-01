@IsTest
private class TelemetrySignalSeverityTest {
    private static final String BOG = 'BLD-BOG-001';
    private static final String PUMP = 'AST-BOG-PUMP-001';
    private static final Datetime BASE_TIME = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0);

    @TestSetup
    static void createCatalog() {
        Account owner = new Account(Name = 'Nova Casa Test');
        Database.insert(owner, AccessLevel.SYSTEM_MODE);

        Schema.Location bogota = new Schema.Location(Name = 'Nova Alameda', LocationType = 'Site', IsMobile = false, External_Id__c = BOG);
        Database.insert(bogota, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new Asset(Name = 'Bomba principal de agua', External_Id__c = PUMP, Asset_Type__c = 'WATER_PUMP', LocationId = bogota.Id, AccountId = owner.Id),
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void usePumpLimits(String direction, Decimal warning, Decimal critical) {
        List<Measurement_Threshold__mdt> records = new List<Measurement_Threshold__mdt>{
            new Measurement_Threshold__mdt(
                Asset_Type__c = 'WATER_PUMP',
                Measurement_Type__c = 'WATER_PRESSURE',
                Unit__c = 'BAR',
                Alert_Direction__c = direction,
                Warning_Limit__c = warning,
                Critical_Limit__c = critical
            )
        };
        MeasurementCatalog.testRecords = records;
        MeasurementSeverityClassifier.testRecords = records;
    }

    private static Telemetry_Signal__e pressure(String key, Decimal value) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = BOG,
            Asset_Id__c = PUMP,
            Sensor_Id__c = 'SNS-' + key,
            Measurement_Type__c = 'WATER_PRESSURE',
            Measurement_Value__c = value,
            Measurement_Unit__c = 'BAR',
            Occurred_At__c = BASE_TIME
        );
    }

    private static Telemetry_Signal__e connectivity(String key) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_CONNECTIVITY,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = BOG,
            Asset_Id__c = PUMP,
            Communication_Status__c = 'HEALTHY',
            Occurred_At__c = BASE_TIME
        );
    }

    private static Map<String, Signal_Log__c> logs() {
        Map<String, Signal_Log__c> byDelivery = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Delivery_Id__c, Result__c, Reason__c, Error__c, Retry_Safe__c, Severity__c, Asset__r.External_Id__c
            FROM Signal_Log__c
            WITH SYSTEM_MODE
        ]) {
            byDelivery.put(log.Delivery_Id__c, log);
        }
        return byDelivery;
    }

    @IsTest
    static void eachAcceptedMeasurementLeavesItsSeverity() {
        usePumpLimits('Below', 1.5, 1.0);

        Test.startTest();
        TelemetryPublisher.publish(
            new List<Telemetry_Signal__e>{
                pressure('normal', 2.0),
                pressure('warning-limit', 1.5),
                pressure('warning', 1.2),
                pressure('critical-limit', 1.0),
                pressure('critical', 0.7),
                connectivity('healthy')
            }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Map<String, Signal_Log__c> logs = logs();
        Assert.areEqual('Normal', logs.get('dlv_normal').Severity__c);
        Assert.areEqual('Warning', logs.get('dlv_warning-limit').Severity__c, 'El límite exacto de advertencia ya es Warning.');
        Assert.areEqual('Warning', logs.get('dlv_warning').Severity__c);
        Assert.areEqual('Critical', logs.get('dlv_critical-limit').Severity__c, 'El límite exacto crítico ya es Critical.');
        Assert.areEqual('Critical', logs.get('dlv_critical').Severity__c);
        // Con US-203, varias lecturas del mismo activo+tipo en el mismo instante dejan solo la
        // primera como estado actual; las demás quedan Late, pero todas registran su severidad.
        for (String key : new List<String>{ 'dlv_normal', 'dlv_warning-limit', 'dlv_warning', 'dlv_critical-limit', 'dlv_critical' }) {
            Assert.isTrue(
                logs.get(key).Result__c == TelemetrySignalOutcome.RESULT_ACCEPTED ||
                    logs.get(key).Result__c == TelemetrySignalOutcome.RESULT_LATE,
                key + ': ' + logs.get(key).Error__c
            );
            Assert.areEqual(PUMP, logs.get(key).Asset__r.External_Id__c, key);
        }
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_healthy').Result__c);
        Assert.isNull(logs.get('dlv_healthy').Severity__c, 'La conectividad no es una medición: no tiene severidad.');
    }

    @IsTest
    static void aChangedLimitAppliesToTheNextSignalOnly() {
        usePumpLimits('Below', 1.5, 1.0);
        TelemetrySignalSubscriber.handle(new List<Telemetry_Signal__e>{ pressure('before-change', 1.2) });

        usePumpLimits('Below', 1.1, 1.0);
        TelemetrySignalSubscriber.handle(new List<Telemetry_Signal__e>{ pressure('after-change', 1.2) });

        Map<String, Signal_Log__c> logs = logs();
        Assert.areEqual('Normal', logs.get('dlv_after-change').Severity__c, 'Con la advertencia en 1.1, 1.2 bar ya es Normal.');
        Assert.areEqual('Warning', logs.get('dlv_before-change').Severity__c, 'Cambiar el límite no reclasifica lo ya procesado.');
    }

    @IsTest
    static void invalidLimitsRejectWithAReasonInsteadOfNormal() {
        usePumpLimits('Below', 1.0, 1.5);
        TelemetrySignalSubscriber.handle(new List<Telemetry_Signal__e>{ pressure('contradictory', 2.0) });

        usePumpLimits(null, 1.5, null);
        TelemetrySignalSubscriber.handle(new List<Telemetry_Signal__e>{ pressure('incomplete', 2.0) });

        Map<String, Signal_Log__c> logs = logs();
        Signal_Log__c contradictory = logs.get('dlv_contradictory');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, contradictory.Result__c);
        Assert.areEqual(TelemetrySignalOutcome.REASON_THRESHOLD_CONTRADICTORY, contradictory.Reason__c);
        Assert.isTrue(contradictory.Retry_Safe__c, 'Se corrige en la CMDT: reprocesar después sí sirve.');
        Assert.isNull(contradictory.Severity__c, 'Sin límites válidos no se guarda Normal.');
        Assert.isTrue(contradictory.Error__c.contains('contradictorios'), contradictory.Error__c);
        Assert.areEqual(PUMP, contradictory.Asset__r.External_Id__c, 'Se enlaza lo que sí se reconoció.');

        Signal_Log__c incomplete = logs.get('dlv_incomplete');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, incomplete.Result__c);
        Assert.areEqual(TelemetrySignalOutcome.REASON_THRESHOLD_INCOMPLETE, incomplete.Reason__c);
        Assert.isNull(incomplete.Severity__c);
        Assert.isTrue(incomplete.Error__c.contains('Alert Direction, Critical Limit'), incomplete.Error__c);
    }
}
