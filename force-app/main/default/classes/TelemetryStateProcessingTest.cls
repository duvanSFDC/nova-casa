@IsTest
private class TelemetryStateProcessingTest {
    private static final String BOG = 'BLD-BOG-001';
    private static final String PUMP = 'AST-BOG-PUMP-001';
    private static final String ENERGY = 'AST-BOG-ENERGY-001';
    private static final String CAMERA = 'AST-BOG-CAM-001';
    private static final Datetime T1 = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0);
    private static final Datetime T2 = Datetime.newInstanceGmt(2026, 9, 29, 4, 15, 0);
    private static final Datetime T3 = Datetime.newInstanceGmt(2026, 9, 29, 4, 30, 0);

    @TestSetup
    static void seed() {
        Account owner = new Account(Name = 'Nova Casa Test');
        Database.insert(owner, AccessLevel.SYSTEM_MODE);

        Schema.Location bogota = new Schema.Location(Name = 'Nova Alameda', LocationType = 'Site', IsMobile = false, External_Id__c = BOG);
        Database.insert(bogota, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new List<Asset>{
                asset('Bomba principal', PUMP, 'WATER_PUMP', bogota.Id, owner.Id),
                asset('Medidor de energía', ENERGY, 'ENERGY_METER', bogota.Id, owner.Id),
                asset('Cámara azotea', CAMERA, 'SECURITY_CAMERA', bogota.Id, owner.Id)
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Asset asset(String name, String code, String type, Id locationId, Id accountId) {
        return new Asset(Name = name, External_Id__c = code, Asset_Type__c = type, LocationId = locationId, AccountId = accountId);
    }

    private static void useCatalog() {
        MeasurementCatalog.testRecords = new List<Measurement_Threshold__mdt>{
            new Measurement_Threshold__mdt(Asset_Type__c = 'WATER_PUMP', Measurement_Type__c = 'WATER_PRESSURE', Unit__c = 'BAR'),
            new Measurement_Threshold__mdt(Asset_Type__c = 'ENERGY_METER', Measurement_Type__c = 'ENERGY_CONSUMPTION', Unit__c = 'KWH_PER_15_MIN')
        };
    }

    private static Telemetry_Signal__e pressure(String key, Decimal value, Datetime occurredAt) {
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
            Occurred_At__c = occurredAt
        );
    }

    private static Telemetry_Signal__e connectivity(String key, String status, Datetime occurredAt) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_CONNECTIVITY,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = BOG,
            Asset_Id__c = CAMERA,
            Communication_Status__c = status,
            Occurred_At__c = occurredAt
        );
    }

    /** Publica y entrega el lote al suscriptor. Se puede llamar varias veces (varias publicaciones). */
    private static void deliver(List<Telemetry_Signal__e> events) {
        TelemetryPublisher.publish(events);
        Test.getEventBus().deliver();
    }

    private static Map<String, Signal_Log__c> logsByDelivery() {
        Map<String, Signal_Log__c> logs = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Delivery_Id__c, Result__c, Reason__c, Error__c, Asset__r.External_Id__c
            FROM Signal_Log__c
            WITH SYSTEM_MODE
        ]) {
            logs.put(log.Delivery_Id__c, log);
        }
        return logs;
    }

    private static Asset_Condition__c conditionFor(String measurementType) {
        List<Asset_Condition__c> rows = [
            SELECT Measurement_Value__c, Measurement_Unit__c, Measurement_Type__c, Severity__c,
                Occurred_At__c, Communication_Status__c, Asset__r.External_Id__c
            FROM Asset_Condition__c
            WHERE Measurement_Type__c = :measurementType
            WITH SYSTEM_MODE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @IsTest
    static void inOrderAcrossPublicationsAdvancesTheState() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('p1', 0.7, T1) });
        deliver(new List<Telemetry_Signal__e>{ pressure('p2', 1.2, T2) });
        Test.stopTest();

        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(1.2, current.Measurement_Value__c, 'Quedó la lectura más reciente');
        Assert.areEqual(T2, current.Occurred_At__c);
        Assert.areEqual(PUMP, current.Asset__r.External_Id__c);
        Assert.areEqual(SeverityClassifier.SEVERITY_NORMAL, current.Severity__c, 'Severidad del clasificador (placeholder)');

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_p1').Result__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_p2').Result__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Asset_Condition__c WITH SYSTEM_MODE], 'Una sola fila por activo+tipo');
    }

    @IsTest
    static void olderPublicationDoesNotOverwriteAndIsLate() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('newer', 1.2, T2) });
        deliver(new List<Telemetry_Signal__e>{ pressure('older', 0.7, T1) });
        Test.stopTest();

        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(1.2, current.Measurement_Value__c, 'La vieja no pisa la actual');
        Assert.areEqual(T2, current.Occurred_At__c);

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_newer').Result__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_older').Result__c);
        Assert.isNull(logs.get('dlv_older').Reason__c, 'Atrasada no es un rechazo');
        Assert.areEqual(PUMP, logs.get('dlv_older').Asset__r.External_Id__c, 'La atrasada conserva su equipo');
    }

    @IsTest
    static void outOfOrderWithinOneCollectionKeepsNewest() {
        useCatalog();
        // En un mismo lote, mezcladas: la del medio es la más reciente.
        Test.startTest();
        deliver(
            new List<Telemetry_Signal__e>{
                pressure('a', 0.7, T1),
                pressure('b', 1.5, T3),
                pressure('c', 1.0, T2)
            }
        );
        Test.stopTest();

        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(1.5, current.Measurement_Value__c);
        Assert.areEqual(T3, current.Occurred_At__c);

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_b').Result__c, 'La más reciente del lote');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_a').Result__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_c').Result__c);
    }

    @IsTest
    static void tieOnOccurredAtKeepsCurrentAndMarksIncomingLate() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('first', 0.7, T2) });
        deliver(new List<Telemetry_Signal__e>{ pressure('tie', 9.9, T2) });
        Test.stopTest();

        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(0.7, current.Measurement_Value__c, 'En empate exacto se conserva la actual');
        Assert.areEqual(T2, current.Occurred_At__c);

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_tie').Result__c, 'El empate no reemplaza');
    }

    @IsTest
    static void lateCriticalDoesNotOverwriteNorOpenWork() {
        useCatalog();
        SeverityClassifier.forced = SeverityClassifier.SEVERITY_CRITICAL;

        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('crit-new', 3.0, T2) });
        deliver(new List<Telemetry_Signal__e>{ pressure('crit-old', 9.9, T1) });
        Test.stopTest();

        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(SeverityClassifier.SEVERITY_CRITICAL, current.Severity__c);
        Assert.areEqual(3.0, current.Measurement_Value__c, 'La crítica atrasada no pisa la actual');
        Assert.areEqual(T2, current.Occurred_At__c);

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_crit-old').Result__c);
        Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder WITH SYSTEM_MODE], 'Apex nunca abre Work Orders');
    }

    @IsTest
    static void connectivityKeepsTheLatestStatusWithoutValueOrUnit() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ connectivity('lost', 'LOST', T1) });
        deliver(new List<Telemetry_Signal__e>{ connectivity('restored', 'RESTORED', T2) });
        deliver(new List<Telemetry_Signal__e>{ connectivity('stale', 'LOST', T1) });
        Test.stopTest();

        Asset_Condition__c current = conditionFor(AssetConditionService.CONNECTIVITY_TYPE);
        Assert.areEqual('RESTORED', current.Communication_Status__c, 'Queda el estado de comunicación más reciente');
        Assert.areEqual(T2, current.Occurred_At__c);
        Assert.isNull(current.Measurement_Value__c, 'La fila de conectividad no tiene valor');
        Assert.isNull(current.Measurement_Unit__c, 'La fila de conectividad no tiene unidad');
        Assert.areEqual(CAMERA, current.Asset__r.External_Id__c);

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_restored').Result__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logs.get('dlv_stale').Result__c);
    }

    @IsTest
    static void differentMeasurementTypesDoNotOverwriteEachOther() {
        useCatalog();
        Test.startTest();
        deliver(
            new List<Telemetry_Signal__e>{
                pressure('pr', 0.8, T2),
                new Telemetry_Signal__e(
                    Delivery_Id__c = 'dlv_en',
                    Message_Id__c = 'msg_en',
                    Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
                    Source__c = 'nova-casa-simulator',
                    Building_Id__c = BOG,
                    Asset_Id__c = ENERGY,
                    Sensor_Id__c = 'SNS-en',
                    Measurement_Type__c = 'ENERGY_CONSUMPTION',
                    Measurement_Value__c = 42,
                    Measurement_Unit__c = 'KWH_PER_15_MIN',
                    Occurred_At__c = T2
                )
            }
        );
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Asset_Condition__c WITH SYSTEM_MODE], 'Presión y consumo son filas distintas');
        Assert.areEqual(0.8, conditionFor('WATER_PRESSURE').Measurement_Value__c);
        Assert.areEqual(42, conditionFor('ENERGY_CONSUMPTION').Measurement_Value__c);
    }

    @IsTest
    static void stateUpdateStaysBulkSafeForLargeBatches() {
        useCatalog();
        // 200 señales de presión del mismo activo+tipo, occurredAt creciente.
        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(pressure('bulk-' + i, 0.5 + i / 100.0, T1.addSeconds(i)));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        TelemetrySignalSubscriber.handle(events);
        Integer queries = Limits.getQueries() - queriesBefore;
        Integer dml = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(4, queries, 'Logs, edificios, equipos y condiciones: una consulta cada uno');
        Assert.areEqual(2, dml, 'Un upsert de condiciones y uno de logs');
        Asset_Condition__c current = conditionFor('WATER_PRESSURE');
        Assert.areEqual(T1.addSeconds(199), current.Occurred_At__c, 'Queda la más reciente de las 200');
        Assert.areEqual(1, [SELECT COUNT() FROM Asset_Condition__c WITH SYSTEM_MODE]);
    }
}
