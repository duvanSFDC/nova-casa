@IsTest
private class InterventionProcessingTest {
    private static final String BOG = 'BLD-BOG-001';
    private static final String PUMP = 'AST-BOG-PUMP-001';
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
            new Asset(Name = 'Bomba principal', External_Id__c = PUMP, Asset_Type__c = 'WATER_PUMP', LocationId = bogota.Id, AccountId = owner.Id),
            AccessLevel.SYSTEM_MODE
        );
    }

    /** Límites donde una presión baja es crítica (Below): <= 1.0 bar es Critical; <= 2.0 es Warning. */
    private static void useCatalog() {
        List<Measurement_Threshold__mdt> records = new List<Measurement_Threshold__mdt>{
            new Measurement_Threshold__mdt(
                Asset_Type__c = 'WATER_PUMP',
                Measurement_Type__c = 'WATER_PRESSURE',
                Unit__c = 'BAR',
                Alert_Direction__c = 'Below',
                Warning_Limit__c = 2.0,
                Critical_Limit__c = 1.0
            )
        };
        MeasurementCatalog.testRecords = records;
        MeasurementSeverityClassifier.testRecords = records;
    }

    /** deliveryKey distingue la entrega; messageId es la identidad (los reenvíos la repiten). */
    private static Telemetry_Signal__e pressure(String deliveryKey, String messageId, Decimal value, Datetime occurredAt) {
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + deliveryKey,
            Message_Id__c = messageId,
            Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = BOG,
            Asset_Id__c = PUMP,
            Sensor_Id__c = 'SNS-' + deliveryKey,
            Measurement_Type__c = 'WATER_PRESSURE',
            Measurement_Value__c = value,
            Measurement_Unit__c = 'BAR',
            Occurred_At__c = occurredAt
        );
    }

    private static void deliver(List<Telemetry_Signal__e> events) {
        TelemetryPublisher.publish(events);
        Test.getEventBus().deliver();
    }

    private static List<WorkOrder> workOrders() {
        return [
            SELECT Id, Message_Key__c, AssetId, LocationId, Status, Priority, Subject
            FROM WorkOrder
            WITH SYSTEM_MODE
        ];
    }

    private static Map<String, Signal_Log__c> logsByDelivery() {
        Map<String, Signal_Log__c> byDelivery = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Delivery_Id__c, Result__c, Reason__c, Error__c, Retry_Safe__c, Severity__c, Work_Order__c
            FROM Signal_Log__c
            WITH SYSTEM_MODE
        ]) {
            byDelivery.put(log.Delivery_Id__c, log);
        }
        return byDelivery;
    }

    @IsTest
    static void criticalCreatesOneInterventionWithItsFields() {
        useCatalog();
        Id pumpId = [SELECT Id FROM Asset WHERE External_Id__c = :PUMP WITH SYSTEM_MODE].Id;
        Id bogId = [SELECT Id FROM Location WHERE External_Id__c = :BOG WITH SYSTEM_MODE].Id;

        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('c1', 'msg_crit', 0.5, T2) });
        Test.stopTest();

        List<WorkOrder> orders = workOrders();
        Assert.areEqual(1, orders.size(), 'Una crítica crea exactamente una intervención');
        WorkOrder order = orders[0];
        Assert.areEqual('msg_crit', order.Message_Key__c, 'La identidad del mensaje es la llave de la intervención');
        Assert.areEqual(pumpId, order.AssetId, 'Lleva el activo');
        Assert.areEqual(bogId, order.LocationId, 'Lleva el edificio');
        Assert.areEqual('Critical', order.Priority, 'Severidad crítica');
        Assert.areEqual('New', order.Status, 'Estado de seguimiento inicial');
        Assert.isTrue(order.Subject != null && order.Subject.contains('Bomba principal'), 'La causa menciona el equipo por su nombre: ' + order.Subject);

        Signal_Log__c log = logsByDelivery().get('dlv_c1');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, log.Result__c);
        Assert.areEqual('Critical', log.Severity__c);
        Assert.areEqual(order.Id, log.Work_Order__c, 'El log enlaza su intervención');
    }

    @IsTest
    static void resendAcrossDeliveriesReusesTheIntervention() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('orig', 'msg_crit', 0.5, T2) });
        // Reenvío: misma identidad y mismo contenido, otra entrega.
        deliver(new List<Telemetry_Signal__e>{ pressure('resend', 'msg_crit', 0.5, T2) });
        Test.stopTest();

        List<WorkOrder> orders = workOrders();
        Assert.areEqual(1, orders.size(), 'El reenvío no crea una segunda intervención');

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, logs.get('dlv_orig').Result__c);
        Assert.areEqual(TelemetrySignalOutcome.RESULT_DUPLICATE, logs.get('dlv_resend').Result__c, 'El reenvío es un duplicado');
        Assert.areEqual(orders[0].Id, logs.get('dlv_resend').Work_Order__c, 'El reenvío reutiliza y enlaza la intervención existente');
    }

    @IsTest
    static void duplicateWithinOneCollectionReusesTheIntervention() {
        useCatalog();
        Test.startTest();
        deliver(
            new List<Telemetry_Signal__e>{
                pressure('a', 'msg_dup', 0.5, T2),
                pressure('b', 'msg_dup', 0.5, T2)
            }
        );
        Test.stopTest();

        List<WorkOrder> orders = workOrders();
        Assert.areEqual(1, orders.size(), 'Dos entregas de la misma identidad en el lote dejan una sola intervención');

        Map<String, Signal_Log__c> logs = logsByDelivery();
        Integer accepted = 0;
        Integer duplicate = 0;
        for (String key : new List<String>{ 'dlv_a', 'dlv_b' }) {
            if (logs.get(key).Result__c == TelemetrySignalOutcome.RESULT_ACCEPTED) {
                accepted++;
            } else if (logs.get(key).Result__c == TelemetrySignalOutcome.RESULT_DUPLICATE) {
                duplicate++;
                Assert.areEqual(orders[0].Id, logs.get(key).Work_Order__c, 'El duplicado del lote enlaza la intervención');
            }
        }
        Assert.areEqual(1, accepted, 'Solo una queda aceptada');
        Assert.areEqual(1, duplicate, 'La otra queda como duplicado');
    }

    @IsTest
    static void sameIdentityDifferentContentIsAConflict() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('first', 'msg_x', 0.5, T2) });
        // Misma identidad, contenido distinto (otra hora de origen).
        deliver(new List<Telemetry_Signal__e>{ pressure('conflict', 'msg_x', 0.5, T3) });
        Test.stopTest();

        Assert.areEqual(1, workOrders().size(), 'Un conflicto no crea otra intervención');

        Signal_Log__c log = logsByDelivery().get('dlv_conflict');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, log.Result__c);
        Assert.areEqual(TelemetrySignalOutcome.REASON_IDENTITY_CONFLICT, log.Reason__c, 'Se identifica como conflicto, no como aviso nuevo');
        Assert.isNull(log.Work_Order__c, 'El conflicto no enlaza una intervención');
    }

    @IsTest
    static void lateCriticalDoesNotCreateIntervention() {
        useCatalog();
        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('current', 'msg_new', 0.5, T2) });
        // Crítica más vieja (otra identidad): queda atrasada y no abre intervención.
        deliver(new List<Telemetry_Signal__e>{ pressure('old', 'msg_old', 0.5, T1) });
        Test.stopTest();

        Assert.areEqual(1, workOrders().size(), 'La crítica atrasada no crea intervención');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_LATE, logsByDelivery().get('dlv_old').Result__c);
    }

    @IsTest
    static void normalAndWarningDoNotCreateIntervention() {
        useCatalog();
        Test.startTest();
        deliver(
            new List<Telemetry_Signal__e>{
                pressure('normal', 'msg_normal', 3.0, T2),
                pressure('warning', 'msg_warning', 1.5, T2)
            }
        );
        Test.stopTest();

        Assert.areEqual(0, workOrders().size(), 'Normal y advertencia no abren intervención');
        Map<String, Signal_Log__c> logs = logsByDelivery();
        Assert.areEqual('Normal', logs.get('dlv_normal').Severity__c);
        Assert.areEqual('Warning', logs.get('dlv_warning').Severity__c);
    }

    @IsTest
    static void creationFailureLeavesTheSignalWithoutClaimingSuccess() {
        useCatalog();
        InterventionService.failInsertsForTest = true;

        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('fail', 'msg_fail', 0.5, T2) });
        Test.stopTest();

        Assert.areEqual(0, workOrders().size(), 'No quedó intervención');
        Signal_Log__c log = logsByDelivery().get('dlv_fail');
        Assert.areNotEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, log.Result__c, 'No queda procesada satisfactoriamente sin su intervención');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, log.Result__c);
        Assert.areEqual(TelemetrySignalOutcome.REASON_INTERVENTION_FAILED, log.Reason__c);
        Assert.isTrue(log.Retry_Safe__c, 'Se puede reintentar de forma segura');
        Assert.isNull(log.Work_Order__c);
    }

    @IsTest
    static void reusesAnInterventionThatAlreadyExistsForTheIdentity() {
        useCatalog();
        // Ya existe una intervención con esa identidad (p. ej. creada por una transacción concurrente),
        // pero no hay señal previa procesada, así que la dedup no la atrapa: el candado es Message_Key__c.
        WorkOrder existing = new WorkOrder(Message_Key__c = 'msg_pre', Status = 'New', Priority = 'Critical', Subject = 'Previa');
        Database.insert(existing, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        deliver(new List<Telemetry_Signal__e>{ pressure('pre', 'msg_pre', 0.5, T2) });
        Test.stopTest();

        Assert.areEqual(1, workOrders().size(), 'No se crea una segunda intervención: se reutiliza la existente');
        Signal_Log__c log = logsByDelivery().get('dlv_pre');
        Assert.areEqual(TelemetrySignalOutcome.RESULT_ACCEPTED, log.Result__c);
        Assert.areEqual(existing.Id, log.Work_Order__c, 'Enlaza la intervención que ya existía para esa identidad');
    }

    @IsTest
    static void staysBulkSafeForLargeBatches() {
        useCatalog();
        // 200 críticas de la misma bomba, occurredAt creciente, identidades distintas.
        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(pressure('bulk-' + i, 'msg_bulk_' + i, 0.5, T1.addSeconds(i)));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        TelemetrySignalSubscriber.handle(events);
        Integer queries = Limits.getQueries() - queriesBefore;
        Integer dml = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(7, queries, 'Logs, edificios, equipos, identidad, condiciones, intervenciones y nombres de equipo: una consulta cada uno');
        Assert.areEqual(3, dml, 'Un upsert de condiciones, un insert de intervención y un upsert de logs');
        // Solo la más reciente queda vigente y abre intervención; las demás, atrasadas.
        Assert.areEqual(1, workOrders().size(), 'La recencia deja una sola crítica vigente por activo+tipo');
    }
}
