@IsTest
private class TelemetryIngestionCursorTest {
    private static final String STORED_CURSOR = 'cursor-stored';

    @TestSetup
    static void storeActiveCursor() {
        Database.insert(
            new Ingestion_State__c(
                Name = TelemetryIngestionService.STATE_NAME,
                Cursor__c = STORED_CURSOR,
                Session_Expires_At__c = Datetime.now().addDays(10)
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void reusesStoredCursorWithoutOpeningNewSession() {
        NovaSimulatorMock mock = new NovaSimulatorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        TelemetryIngestionService.Result result = new TelemetryIngestionService().run(5);
        Test.stopTest();

        Assert.isFalse(result.sessionStarted);
        Assert.areEqual(0, mock.sessionCalls, 'Una sesión nueva sería otro escenario del simulador');
        Assert.areEqual(STORED_CURSOR, mock.lastCursor);
        Assert.areEqual(NovaSimulatorMock.NEXT_CURSOR, [SELECT Cursor__c FROM Ingestion_State__c WITH SYSTEM_MODE].Cursor__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Ingestion_State__c WITH SYSTEM_MODE], 'Actualiza el estado, no crea otro');
    }

    @IsTest
    static void expiredSessionOpensANewOne() {
        Ingestion_State__c state = [SELECT Id FROM Ingestion_State__c WITH SYSTEM_MODE];
        state.Session_Expires_At__c = Datetime.now().addMinutes(-1);
        Database.update(state, AccessLevel.SYSTEM_MODE);

        NovaSimulatorMock mock = new NovaSimulatorMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        TelemetryIngestionService.Result result = new TelemetryIngestionService().run(5);
        Test.stopTest();

        Assert.isTrue(result.sessionStarted);
        Assert.areEqual(1, mock.sessionCalls);
        Assert.areEqual(NovaSimulatorMock.SESSION_CURSOR, mock.lastCursor);
    }
}
