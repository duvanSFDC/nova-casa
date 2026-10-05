@IsTest
private class TelemetryIngestionServiceTest {
    private static Long seconds(Datetime value) {
        return value == null ? null : value.getTime() / 1000;
    }

    private static Datetime iso(String value) {
        return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
    }

    private static Map<String, Signal_Log__c> logsByMessage() {
        Map<String, Signal_Log__c> result = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Message_Id__c, Delivery_Id__c, Message_Type__c, Status__c, Event_Uuid__c,
                Occurred_At__c, Source_Published_At__c, Published_At__c, Processed_At__c, Replay_Id__c
            FROM Signal_Log__c
            WITH SYSTEM_MODE
        ]) {
            result.put(log.Message_Id__c, log);
        }
        return result;
    }

    @IsTest
    static void firstRunOpensSessionPublishesAndStoresNextCursor() {
        NovaSimulatorMock mock = new NovaSimulatorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        TelemetryIngestionService.Result result = new TelemetryIngestionService().run(5);
        Test.stopTest();

        Assert.isTrue(result.sessionStarted, 'Sin cursor guardado debe abrir sesión');
        Assert.areEqual(1, mock.sessionCalls);
        Assert.areEqual(NovaSimulatorMock.SESSION_CURSOR, mock.lastCursor, 'El GET usa el cursor de la sesión');
        Assert.areEqual(2, result.received);
        Assert.areEqual(2, result.published);
        Assert.areEqual(0, result.publishFailed);
        Assert.isTrue(result.hasMore);
        Assert.areEqual(10000, result.pollAfterMs);

        Ingestion_State__c state = [SELECT Cursor__c, Has_More__c, Poll_After_Ms__c, Last_Batch_Count__c FROM Ingestion_State__c WITH SYSTEM_MODE];
        Assert.areEqual(NovaSimulatorMock.NEXT_CURSOR, state.Cursor__c, 'Debe guardar pagination.nextCursor');
        Assert.isTrue(state.Has_More__c);
        Assert.areEqual(10000, state.Poll_After_Ms__c);
        Assert.areEqual(2, state.Last_Batch_Count__c);
    }

    @IsTest
    static void runScenarioOpensASessionWithTheScenarioAndIngests() {
        NovaSimulatorMock mock = new NovaSimulatorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        TelemetryIngestionService.Result result = new TelemetryIngestionService().runScenario('critical_burst', 20260922L, 50);
        Test.stopTest();

        Assert.areEqual(1, mock.sessionCalls, 'El escenario siempre abre una sesión nueva');
        Assert.isTrue(result.sessionStarted);
        Assert.areEqual(2, result.received);
        // El cuerpo de /session lleva el escenario (normalizado), la semilla y los edificios.
        Assert.isTrue(mock.lastSessionBody.contains('CRITICAL_BURST'), mock.lastSessionBody);
        Assert.isTrue(mock.lastSessionBody.contains('20260922'), mock.lastSessionBody);
        Assert.isTrue(mock.lastSessionBody.contains('BLD-BOG-001'), mock.lastSessionBody);

        // Usa su propio cursor ('scenario'), separado de la ingesta normal ('default').
        Ingestion_State__c state = [SELECT Name, Cursor__c FROM Ingestion_State__c WITH SYSTEM_MODE];
        Assert.areEqual(TelemetryIngestionService.SCENARIO_STATE_NAME, state.Name);
        Assert.areEqual(NovaSimulatorMock.NEXT_CURSOR, state.Cursor__c);
    }

    @IsTest
    static void runScenarioRejectsAnUnknownScenario() {
        Test.setMock(HttpCalloutMock.class, new NovaSimulatorMock());

        Test.startTest();
        try {
            new TelemetryIngestionService().runScenario('NO_EXISTE', null, 10);
            Assert.fail('Un escenario desconocido debe rechazarse antes de llamar al simulador');
        } catch (NovaSimulatorClient.SimulatorException e) {
            Assert.isTrue(e.getMessage().contains('NO_EXISTE'), e.getMessage());
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Signal_Log__c WITH SYSTEM_MODE], 'No se publicó nada');
    }

    @IsTest
    static void publishedIsDistinctFromProcessed() {
        Test.setMock(HttpCalloutMock.class, new NovaSimulatorMock());

        Test.startTest();
        new TelemetryIngestionService().run(5);

        Map<String, Signal_Log__c> beforeDelivery = logsByMessage();
        Assert.areEqual(2, beforeDelivery.size());
        for (Signal_Log__c log : beforeDelivery.values()) {
            Assert.areEqual(TelemetryPublisher.STATUS_PUBLISHED, log.Status__c, 'Antes de que el suscriptor corra solo está publicada');
            Assert.isNotNull(log.Published_At__c);
            Assert.isNotNull(log.Event_Uuid__c, 'La publicación debe dejar el EventUuid para enlazar el procesamiento');
            Assert.isNull(log.Processed_At__c);
        }

        Test.getEventBus().deliver();
        Test.stopTest();

        Map<String, Signal_Log__c> afterDelivery = logsByMessage();
        Assert.areEqual(2, afterDelivery.size(), 'El suscriptor actualiza el mismo log, no crea otro');
        for (Signal_Log__c log : afterDelivery.values()) {
            Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c);
            Assert.isNotNull(log.Processed_At__c);
            Assert.isNotNull(log.Replay_Id__c);
            Assert.areEqual(beforeDelivery.get(log.Message_Id__c).Event_Uuid__c, log.Event_Uuid__c);
        }
    }

    @IsTest
    static void keepsSensorTimeSeparateFromReceptionAndProcessing() {
        Test.setMock(HttpCalloutMock.class, new NovaSimulatorMock());

        Test.startTest();
        new TelemetryIngestionService().run(5);
        Test.getEventBus().deliver();
        Test.stopTest();

        Signal_Log__c late = logsByMessage().get('msg_000002');
        Assert.areEqual('dlv_000002', late.Delivery_Id__c);
        Assert.areEqual('MEASUREMENT', late.Message_Type__c);
        Assert.areEqual(seconds(iso('2026-09-29T03:45:51.211Z')), seconds(late.Occurred_At__c), 'occurredAt del sensor intacto');
        Assert.areEqual(seconds(iso('2026-09-29T04:02:51.211Z')), seconds(late.Source_Published_At__c), 'publishedAt del simulador intacto');
        Assert.areNotEqual(seconds(late.Occurred_At__c), seconds(late.Published_At__c), 'La hora del sensor no se reemplaza por la de publicación');
        Assert.areNotEqual(seconds(late.Occurred_At__c), seconds(late.Processed_At__c), 'La hora del sensor no se reemplaza por la de procesamiento');
    }

    @IsTest
    static void simulatorErrorPublishesNothing() {
        NovaSimulatorMock mock = new NovaSimulatorMock();
        mock.telemetryStatus = 401;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            new TelemetryIngestionService().run(5);
            Assert.fail('Un 401 del simulador debe lanzar excepción');
        } catch (NovaSimulatorClient.SimulatorException e) {
            Assert.isTrue(e.getMessage().contains('401'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Token inválido'), e.getMessage());
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Signal_Log__c WITH SYSTEM_MODE]);
        Assert.areEqual(0, [SELECT COUNT() FROM Ingestion_State__c WITH SYSTEM_MODE]);
    }

    @IsTest
    static void subscriberLogsEventsPublishedOutsideTheService() {
        Test.startTest();
        EventBus.publish(new Telemetry_Signal__e(Message_Id__c = 'msg_manual', Delivery_Id__c = 'dlv_manual', Message_Type__c = 'MEASUREMENT'));
        Test.stopTest();

        Signal_Log__c log = logsByMessage().get('msg_manual');
        Assert.isNotNull(log);
        Assert.areEqual(TelemetryPublisher.STATUS_PROCESSED, log.Status__c);
        Assert.isNull(log.Published_At__c, 'No pasó por TelemetryPublisher');
    }

    @IsTest
    static void queueableRunsIngestion() {
        Test.setMock(HttpCalloutMock.class, new NovaSimulatorMock());

        Test.startTest();
        System.enqueueJob(new TelemetryIngestionJob(5, 3));
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Signal_Log__c WITH SYSTEM_MODE]);
    }

    @IsTest
    static void mapsConnectivityAndToleratesBadDates() {
        Telemetry_Signal__e evt = TelemetrySignalMapper.toEvent(
            new Map<String, Object>{
                'deliveryId' => 'dlv_x',
                'messageType' => 'CONNECTIVITY',
                'communication' => new Map<String, Object>{ 'status' => 'LOST', 'gapSeconds' => 900, 'episodeId' => 'EPI-1' },
                'occurredAt' => 'no-es-fecha'
            }
        );

        Assert.areEqual('LOST', evt.Communication_Status__c);
        Assert.areEqual(900, evt.Gap_Seconds__c);
        Assert.areEqual('EPI-1', evt.Episode_Id__c);
        Assert.isNull(evt.Measurement_Type__c, 'CONNECTIVITY no trae measurement');
        Assert.isNull(evt.Occurred_At__c, 'Una fecha ilegible no rompe el mapeo');
        Assert.isTrue(evt.Raw_Payload__c.contains('no-es-fecha'), 'El payload original se conserva');
    }
}
