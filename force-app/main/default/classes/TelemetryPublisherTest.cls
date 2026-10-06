@IsTest
private class TelemetryPublisherTest {
    @IsTest
    static void publicaYDejaCadaSenalComoPublicada() {
        Telemetry_Signal__e evt = new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv-1',
            Message_Id__c = 'msg-1',
            Message_Type__c = 'measurement',
            Building_Id__c = 'BLD-BOG-001',
            Asset_Id__c = 'AST-BOG-TEMP-001',
            Occurred_At__c = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0)
        );

        Test.startTest();
        TelemetryPublisher.Outcome outcome = TelemetryPublisher.publish(new List<Telemetry_Signal__e>{ evt });
        Test.stopTest();

        Assert.areEqual(1, outcome.published, 'La señal se publica');
        Assert.areEqual(0, outcome.failed, 'No hay fallos');
        Assert.areEqual(TelemetryPublisher.STATUS_PUBLISHED, outcome.logs[0].Status__c);
    }

    @IsTest
    static void unaPublicacionFallidaQuedaReintentableYSinDatosCrudos() {
        Telemetry_Signal__e evt = new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv-err',
            Message_Id__c = 'msg-err',
            Message_Type__c = 'measurement',
            Building_Id__c = 'BLD-BOG-001',
            Asset_Id__c = 'AST-BOG-TEMP-001'
        );

        Signal_Log__c log = TelemetryPublisher.failedLog(evt, 'STORAGE_LIMIT_EXCEEDED: sin espacio');

        Assert.areEqual(TelemetryPublisher.STATUS_PUBLISH_FAILED, log.Status__c, 'Queda como Publish_Failed');
        Assert.areEqual(true, log.Retry_Safe__c, 'Volver a publicar es seguro: se marca reintentable');
        Assert.areEqual('msg-err', log.Message_Id__c, 'Conserva la identidad por messageId');
        Assert.isTrue(log.Error__c != null && log.Error__c.contains('STORAGE_LIMIT_EXCEEDED'), 'Guarda el motivo del fallo');
    }
}
