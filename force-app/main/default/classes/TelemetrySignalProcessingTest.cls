@IsTest
private class TelemetrySignalProcessingTest {
    private static final String BOG = 'BLD-BOG-001';
    private static final String BAQ = 'BLD-BAQ-001';
    private static final String PUMP = 'AST-BOG-PUMP-001';
    private static final String ENERGY = 'AST-BOG-ENERGY-001';
    private static final String CAMERA = 'AST-BAQ-CAM-001';
    private static final String UNTYPED = 'AST-BOG-LOBBY-001';
    private static final Datetime BASE_TIME = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0);

    @TestSetup
    static void createCatalog() {
        Account owner = new Account(Name = 'Nova Casa Test');
        Database.insert(owner, AccessLevel.SYSTEM_MODE);

        Schema.Location bogota = building('Nova Alameda', BOG);
        Schema.Location barranquilla = building('Nova Caribe', BAQ);
        Database.insert(new List<Schema.Location>{ bogota, barranquilla }, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new List<Asset>{
                equipment('Bomba principal de agua', PUMP, 'WATER_PUMP', bogota.Id, owner.Id),
                equipment('Medidor de energía', ENERGY, 'ENERGY_METER', bogota.Id, owner.Id),
                equipment('Cámara azotea', CAMERA, 'SECURITY_CAMERA', barranquilla.Id, owner.Id),
                equipment('Iluminación del lobby', UNTYPED, null, bogota.Id, owner.Id)
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Schema.Location building(String name, String code) {
        return new Schema.Location(Name = name, LocationType = 'Site', IsMobile = false, External_Id__c = code);
    }

    private static Asset equipment(String name, String code, String type, Id locationId, Id accountId) {
        return new Asset(Name = name, External_Id__c = code, Asset_Type__c = type, LocationId = locationId, AccountId = accountId);
    }

    /** Mismas unidades que la CMDT desplegada, para no depender de que alguien la edite. */
    private static void useCatalog() {
        MeasurementCatalog.testRecords = new List<Measurement_Threshold__mdt>{
            new Measurement_Threshold__mdt(Asset_Type__c = 'WATER_PUMP', Measurement_Type__c = 'WATER_PRESSURE', Unit__c = 'BAR'),
            new Measurement_Threshold__mdt(Asset_Type__c = 'ENERGY_METER', Measurement_Type__c = 'ENERGY_CONSUMPTION', Unit__c = 'KWH_PER_15_MIN')
        };
    }

    private static Telemetry_Signal__e measurement(String key, String buildingCode, String assetCode, String type, Decimal value, String unit) {
        return measurement(key, buildingCode, assetCode, type, value, unit, BASE_TIME);
    }

    private static Telemetry_Signal__e measurement(
        String key,
        String buildingCode,
        String assetCode,
        String type,
        Decimal value,
        String unit,
        Datetime occurredAt
    ) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = buildingCode,
            Asset_Id__c = assetCode,
            Sensor_Id__c = 'SNS-' + key,
            Measurement_Type__c = type,
            Measurement_Value__c = value,
            Measurement_Unit__c = unit,
            Occurred_At__c = occurredAt
        );
    }

    private static Telemetry_Signal__e connectivity(String key, String status) {
        return connectivity(key, status, BASE_TIME);
    }

    private static Telemetry_Signal__e connectivity(String key, String status, Datetime occurredAt) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_CONNECTIVITY,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = BAQ,
            Asset_Id__c = CAMERA,
            Communication_Status__c = status,
            Occurred_At__c = occurredAt
        );
    }

    /** Publica como lo hace la ingesta y deja que el suscriptor procese. Devuelve los logs por deliveryId. */
    private static Map<String, Signal_Log__c> publishAndProcess(List<Telemetry_Signal__e> events) {
        Test.startTest();
        TelemetryPublisher.Outcome published = TelemetryPublisher.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.areEqual(events.size(), published.published, 'Todas las señales deben salir al bus');

        Map<String, Signal_Log__c> logs = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Delivery_Id__c, Status__c, Result__c, Reason__c, Error__c, Retry_Safe__c,
                Asset__r.External_Id__c, Location__r.External_Id__c, Processed_At__c
            FROM Signal_Log__c
            WITH SYSTEM_MODE
        ]) {
            logs.put(log.Delivery_Id__c, log);
        }
        return logs;
    }

    private static void assertAccepted(Signal_Log__c log, String assetCode, String buildingCode) {
        Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c, log.Delivery_Id__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, log.Result__c, log.Delivery_Id__c + ': ' + log.Error__c);
        Assert.isNull(log.Reason__c, log.Delivery_Id__c);
        Assert.isNull(log.Error__c, log.Delivery_Id__c);
        Assert.areEqual(assetCode, log.Asset__r?.External_Id__c, log.Delivery_Id__c + ': enlaza el equipo');
        Assert.areEqual(buildingCode, log.Location__r?.External_Id__c, log.Delivery_Id__c + ': enlaza el edificio');
    }

    private static void assertLate(Signal_Log__c log, String assetCode, String buildingCode) {
        Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c, log.Delivery_Id__c + ': atrasada también es procesada');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, log.Result__c, log.Delivery_Id__c);
        Assert.isNull(log.Reason__c, log.Delivery_Id__c + ': Late no lleva motivo de rechazo');
        Assert.areEqual(assetCode, log.Asset__r?.External_Id__c, log.Delivery_Id__c + ': conserva el equipo reconocido');
        Assert.areEqual(buildingCode, log.Location__r?.External_Id__c, log.Delivery_Id__c + ': conserva el edificio reconocido');
    }

    private static void assertRejected(Signal_Log__c log, String reason, Boolean retrySafe, String detailFragment) {
        Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c, log.Delivery_Id__c + ': rechazada también es procesada');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, log.Result__c, log.Delivery_Id__c);
        Assert.areEqual(reason, log.Reason__c, log.Delivery_Id__c);
        Assert.areEqual(retrySafe, log.Retry_Safe__c, log.Delivery_Id__c);
        Assert.isTrue(log.Error__c != null && log.Error__c.contains(detailFragment), log.Delivery_Id__c + ': ' + log.Error__c);
    }

    @IsTest
    static void mixedBatchKeepsValidSignalsAndExplainsEachRejection() {
        useCatalog();
        Telemetry_Signal__e withoutMessageId = measurement('no-message-id', BOG, PUMP, 'WATER_PRESSURE', 0.9, 'BAR');
        withoutMessageId.Message_Id__c = null;
        Telemetry_Signal__e unknownType = measurement('unknown-type', BOG, PUMP, 'WATER_PRESSURE', 0.9, 'BAR');
        unknownType.Message_Type__c = 'FIRMWARE';

        Map<String, Signal_Log__c> logs = publishAndProcess(
            new List<Telemetry_Signal__e>{
                measurement('pressure-1', BOG, PUMP, 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('pressure-2', BOG, PUMP, 'WATER_PRESSURE', 1.1, 'BAR'),
                measurement('lowercase-codes', 'bld-bog-001', 'ast-bog-pump-001', 'water_pressure', 1.0, 'bar'),
                measurement('energy', BOG, ENERGY, 'ENERGY_CONSUMPTION', 12.5, 'KWH_PER_15_MIN'),
                connectivity('camera-lost', 'LOST'),
                measurement('no-value', BOG, PUMP, 'WATER_PRESSURE', null, 'BAR'),
                withoutMessageId,
                connectivity('no-status', null),
                unknownType,
                measurement('unknown-asset', BAQ, 'AST-UNKNOWN-0001', 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('unknown-building', 'BLD-XXX-999', PUMP, 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('wrong-building', BAQ, PUMP, 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('unsupported', BOG, PUMP, 'TEMPERATURE', 25, 'CELSIUS'),
                measurement('untyped-asset', BOG, UNTYPED, 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('wrong-unit', BOG, ENERGY, 'ENERGY_CONSUMPTION', 1200, 'WATT')
            }
        );

        Assert.areEqual(15, logs.size(), 'Cada señal deja exactamente un log');

        // Tres señales comparten activo+tipo (PUMP WATER_PRESSURE) con el mismo occurredAt:
        // la primera queda como estado actual y las otras dos, al no ser más nuevas, quedan Late.
        assertAccepted(logs.get('dlv_pressure-1'), PUMP, BOG);
        assertLate(logs.get('dlv_pressure-2'), PUMP, BOG);
        assertLate(logs.get('dlv_lowercase-codes'), PUMP, BOG);
        assertAccepted(logs.get('dlv_energy'), ENERGY, BOG);
        assertAccepted(logs.get('dlv_camera-lost'), CAMERA, BAQ);

        assertRejected(logs.get('dlv_no-value'), TelemetrySignalOutcome.REASON_INCOMPLETE, false, 'measurement.value');
        assertRejected(logs.get('dlv_no-message-id'), TelemetrySignalOutcome.REASON_INCOMPLETE, false, 'messageId');
        assertRejected(logs.get('dlv_no-status'), TelemetrySignalOutcome.REASON_INCOMPLETE, false, 'communication.status');
        assertRejected(logs.get('dlv_unknown-type'), TelemetrySignalOutcome.REASON_UNKNOWN_MESSAGE_TYPE, false, 'FIRMWARE');
        assertRejected(logs.get('dlv_unknown-asset'), TelemetrySignalOutcome.REASON_UNKNOWN_ASSET, true, 'AST-UNKNOWN-0001');
        assertRejected(logs.get('dlv_unknown-building'), TelemetrySignalOutcome.REASON_UNKNOWN_BUILDING, true, 'BLD-XXX-999');
        assertRejected(logs.get('dlv_wrong-building'), TelemetrySignalOutcome.REASON_ASSET_NOT_IN_BUILDING, true, PUMP);
        assertRejected(logs.get('dlv_unsupported'), TelemetrySignalOutcome.REASON_UNSUPPORTED_MEASUREMENT, true, 'TEMPERATURE');
        assertRejected(logs.get('dlv_untyped-asset'), TelemetrySignalOutcome.REASON_UNSUPPORTED_MEASUREMENT, true, 'Asset Type');
        assertRejected(logs.get('dlv_wrong-unit'), TelemetrySignalOutcome.REASON_INCOMPATIBLE_UNIT, false, 'WATT');

        Assert.isNull(logs.get('dlv_no-value').Asset__r, 'Apex A rechaza sin consultar: no hay lookup');
        Assert.isNull(logs.get('dlv_unknown-asset').Asset__r, 'Un código que no existe no inventa un equipo');
        Assert.areEqual(BAQ, logs.get('dlv_unknown-asset').Location__r.External_Id__c, 'Se enlaza lo que sí se reconoció');
        Assert.isNull(logs.get('dlv_unknown-building').Location__r);
        Assert.areEqual(PUMP, logs.get('dlv_unknown-building').Asset__r.External_Id__c);

        Assert.areEqual(4, [SELECT COUNT() FROM Asset WITH SYSTEM_MODE], 'Las señales no crean equipos');
        Assert.areEqual(2, [SELECT COUNT() FROM Location WITH SYSTEM_MODE], 'Las señales no crean edificios');

        // El estado actual queda con una fila por activo+tipo aceptado (presión, energía, conectividad).
        Assert.areEqual(3, [SELECT COUNT() FROM Asset_Condition__c WITH SYSTEM_MODE], 'Una condición por activo+tipo aceptado');
        Asset_Condition__c pressure = [
            SELECT Measurement_Value__c, Measurement_Unit__c
            FROM Asset_Condition__c
            WHERE Measurement_Type__c = 'WATER_PRESSURE'
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(0.7, pressure.Measurement_Value__c, 'La condición conserva la primera lectura, no las empatadas');
    }

    @IsTest
    static void volumeOf200KeepsTheMostRecentPerAssetAndIsolatesInvalid() {
        useCatalog();
        // occurredAt crece con i: dentro de cada activo+tipo, la de mayor i es la más reciente.
        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>();
        for (Integer i = 0; i < 200; i++) {
            String key = 'vol-' + i;
            Datetime occurredAt = BASE_TIME.addSeconds(i);
            switch on Math.mod(i, 5) {
                when 0 {
                    events.add(measurement(key, BOG, PUMP, 'WATER_PRESSURE', 0.5 + i / 100.0, 'BAR', occurredAt));
                }
                when 1 {
                    events.add(measurement(key, BOG, ENERGY, 'ENERGY_CONSUMPTION', 10 + i, 'KWH_PER_15_MIN', occurredAt));
                }
                when 2 {
                    events.add(connectivity(key, Math.mod(i, 2) == 0 ? 'HEALTHY' : 'LOST', occurredAt));
                }
                when 3 {
                    events.add(measurement(key, BAQ, 'AST-UNKNOWN-' + i, 'WATER_PRESSURE', 0.7, 'BAR', occurredAt));
                }
                when else {
                    events.add(
                        Math.mod(i, 10) == 4
                            ? measurement(key, BOG, PUMP, 'WATER_PRESSURE', null, 'BAR', occurredAt)
                            : measurement(key, BOG, ENERGY, 'ENERGY_CONSUMPTION', 900, 'WATT', occurredAt)
                    );
                }
            }
        }

        Map<String, Signal_Log__c> logs = publishAndProcess(events);

        Assert.areEqual(200, logs.size(), 'Una señal, un log');
        Map<String, Integer> countByOutcome = new Map<String, Integer>();
        Map<String, Integer> validByAsset = new Map<String, Integer>();
        for (Signal_Log__c log : logs.values()) {
            Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c, log.Delivery_Id__c);
            Assert.isNotNull(log.Processed_At__c, log.Delivery_Id__c);
            String outcome = log.Result__c + (log.Reason__c == null ? '' : ':' + log.Reason__c);
            countByOutcome.put(outcome, (countByOutcome.containsKey(outcome) ? countByOutcome.get(outcome) : 0) + 1);
            if (log.Result__c == TelemetrySignalOutcome.RESULT_ACCEPTED || log.Result__c == TelemetrySignalOutcome.RESULT_LATE) {
                String assetCode = log.Asset__r.External_Id__c;
                validByAsset.put(assetCode, (validByAsset.containsKey(assetCode) ? validByAsset.get(assetCode) : 0) + 1);
            }
        }

        // 40 válidas por cada uno de los 3 activos: 1 queda como estado actual (la más reciente) y 39 Late.
        Assert.areEqual(
            new Map<String, Integer>{
                'Accepted' => 3,
                'Late' => 117,
                'Rejected:UNKNOWN_ASSET' => 40,
                'Rejected:INCOMPLETE' => 20,
                'Rejected:INCOMPATIBLE_UNIT' => 20
            },
            countByOutcome,
            'Las válidas sobreviven a las 80 inválidas; por activo queda solo la más reciente'
        );
        Assert.areEqual(
            new Map<String, Integer>{ PUMP => 40, ENERGY => 40, CAMERA => 40 },
            validByAsset,
            'Las 40 señales de cada equipo quedan enlazadas a su equipo (aceptada o atrasada)'
        );

        // El estado actual guarda, por activo+tipo, la lectura de mayor occurredAt del lote.
        Map<String, Asset_Condition__c> conditionByType = new Map<String, Asset_Condition__c>();
        for (Asset_Condition__c condition : [
            SELECT Measurement_Type__c, Occurred_At__c
            FROM Asset_Condition__c
            WITH SYSTEM_MODE
        ]) {
            conditionByType.put(condition.Measurement_Type__c, condition);
        }
        Assert.areEqual(3, conditionByType.size(), 'Una condición por activo+tipo');
        Assert.areEqual(BASE_TIME.addSeconds(195), conditionByType.get('WATER_PRESSURE').Occurred_At__c, 'Presión: la más reciente (i=195)');
        Assert.areEqual(BASE_TIME.addSeconds(196), conditionByType.get('ENERGY_CONSUMPTION').Occurred_At__c, 'Energía: la más reciente (i=196)');
        Assert.areEqual(BASE_TIME.addSeconds(197), conditionByType.get(AssetConditionService.CONNECTIVITY_TYPE).Occurred_At__c, 'Conectividad: la más reciente (i=197)');
    }

    @IsTest
    static void queriesAndWritesDoNotGrowWithTheBatch() {
        useCatalog();
        // Un lote de 1 (presión) y uno de 200 (energía, occurredAt creciente). Usan activos distintos
        // para no interferir entre sí; cada lote actualiza una condición.
        List<Telemetry_Signal__e> single = new List<Telemetry_Signal__e>{ measurement('single', BOG, PUMP, 'WATER_PRESSURE', 0.7, 'BAR') };
        List<Telemetry_Signal__e> full = new List<Telemetry_Signal__e>();
        for (Integer i = 0; i < 200; i++) {
            full.add(measurement('full-' + i, BOG, ENERGY, 'ENERGY_CONSUMPTION', 10 + i, 'KWH_PER_15_MIN', BASE_TIME.addSeconds(i)));
        }

        Test.startTest();
        List<Integer> costOfOne = cost(single);
        List<Integer> costOf200 = cost(full);
        Test.stopTest();

        // 4 consultas (logs, edificios, equipos, condiciones) y 2 escrituras (condiciones y logs).
        Assert.areEqual(new List<Integer>{ 4, 2 }, costOfOne, 'Costo fijo por lote');
        Assert.areEqual(costOfOne, costOf200, 'El costo no crece con el tamaño del lote');
        Assert.areEqual(201, [SELECT COUNT() FROM Signal_Log__c WITH SYSTEM_MODE]);
        // De las 200 de energía, solo la más reciente queda como estado actual; el resto, Late.
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Signal_Log__c WHERE Result__c = :TelemetrySignalOutcome.RESULT_ACCEPTED AND Delivery_Id__c LIKE 'dlv_full-%' WITH SYSTEM_MODE]
        );
        Assert.areEqual(
            BASE_TIME.addSeconds(199),
            [SELECT Occurred_At__c FROM Asset_Condition__c WHERE Measurement_Type__c = 'ENERGY_CONSUMPTION' WITH SYSTEM_MODE].Occurred_At__c,
            'La condición de energía guarda la lectura más reciente del lote'
        );
    }

    /** Consultas y escrituras que gasta el suscriptor con ese lote. */
    private static List<Integer> cost(List<Telemetry_Signal__e> events) {
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        TelemetrySignalSubscriber.handle(events);
        return new List<Integer>{ Limits.getQueries() - queriesBefore, Limits.getDmlStatements() - dmlBefore };
    }

    @IsTest
    static void catalogReadsDeployedThresholds() {
        // Sin inyectar testRecords: se lee la Measurement_Threshold__mdt real desplegada.
        MeasurementCatalog catalog = MeasurementCatalog.load();

        Assert.areEqual('BAR', catalog.unitFor('WATER_PUMP', 'WATER_PRESSURE'));
        Assert.areEqual('KWH_PER_15_MIN', catalog.unitFor('ENERGY_METER', 'ENERGY_CONSUMPTION'));
        Assert.areEqual('CELSIUS', catalog.unitFor('TECHNICAL_ROOM', 'TEMPERATURE'));
        Assert.areEqual('LITER_PER_15_MIN', catalog.unitFor('WATER_METER', 'WATER_CONSUMPTION'));
        Assert.areEqual('BAR', catalog.unitFor('water_pump', 'water_pressure'), 'La búsqueda no distingue mayúsculas');
        Assert.isNull(catalog.unitFor('WATER_PUMP', 'TEMPERATURE'), 'Combinación no configurada');
    }

    @IsTest
    static void assetWithoutBuildingConnectivityUnknownAndTrailingUnit() {
        useCatalog();
        Account owner = [SELECT Id FROM Account WITH SYSTEM_MODE LIMIT 1];
        Asset orphan = new Asset(
            Name = 'Bomba sin edificio',
            External_Id__c = 'AST-BOG-ORPHAN-001',
            Asset_Type__c = 'WATER_PUMP',
            AccountId = owner.Id
        );
        Database.insert(orphan, AccessLevel.SYSTEM_MODE);

        Telemetry_Signal__e connectivityUnknown = connectivity('conn-unknown', 'LOST');
        connectivityUnknown.Asset_Id__c = 'AST-UNKNOWN-CAM';

        Map<String, Signal_Log__c> logs = publishAndProcess(
            new List<Telemetry_Signal__e>{
                measurement('orphan', BOG, 'AST-BOG-ORPHAN-001', 'WATER_PRESSURE', 0.7, 'BAR'),
                measurement('trailing-unit', BOG, PUMP, 'WATER_PRESSURE', 0.7, 'BAR '),
                connectivityUnknown
            }
        );

        assertRejected(logs.get('dlv_orphan'), TelemetrySignalOutcome.REASON_ASSET_NOT_IN_BUILDING, true, 'no tiene edificio asignado');
        assertAccepted(logs.get('dlv_trailing-unit'), PUMP, BOG);
        assertRejected(logs.get('dlv_conn-unknown'), TelemetrySignalOutcome.REASON_UNKNOWN_ASSET, true, 'AST-UNKNOWN-CAM');
    }

    @IsTest
    static void compatibilityComesFromTheCatalogNotFromTheCode() {
        MeasurementCatalog.testRecords = new List<Measurement_Threshold__mdt>();
        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>{ measurement('no-catalog', BOG, PUMP, 'WATER_PRESSURE', 0.7, 'BAR') };

        TelemetrySignalOutcome withoutRow = TelemetrySignalProcessor.process(events)[0];
        Assert.areEqual(TelemetrySignalOutcome.REASON_UNSUPPORTED_MEASUREMENT, withoutRow.reason, 'Sin registro en la CMDT no se acepta');

        MeasurementCatalog.testRecords = new List<Measurement_Threshold__mdt>{
            new Measurement_Threshold__mdt(Asset_Type__c = 'water_pump', Measurement_Type__c = 'Water_Pressure', Unit__c = 'BAR')
        };
        TelemetrySignalOutcome withRow = TelemetrySignalProcessor.process(events)[0];
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, withRow.result, 'Al agregar el registro se acepta, sin cambiar código');
    }
}
