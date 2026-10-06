@IsTest
private class SignalLogSensitiveDataTest {
    private static final String FAKE_SECRET = 'Bearer SECRETO-de-prueba-123';
    private static final List<String> SENSITIVE_NAMES = new List<String>{ 'PAYLOAD', 'TOKEN', 'PASSWORD', 'SECRET', 'AUTH' };

    @IsTest
    static void theLogHasNoRoomForPayloadsOrSecrets() {
        for (Schema.SObjectField token : Schema.SObjectType.Signal_Log__c.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (!field.isCustom()) {
                continue;
            }
            String name = field.getName().toUpperCase();
            System.assertNotEquals(Schema.DisplayType.TEXTAREA, field.getType(), name + ' could hold a payload.');
            System.assert(field.isCalculated() || field.getLength() <= 255, name + ' is longer than 255 characters.');
            for (String sensitive : SENSITIVE_NAMES) {
                System.assert(!name.contains(sensitive), name + ' looks like it stores ' + sensitive + '.');
            }
        }
    }

    @IsTest
    static void rejectedSignalsDoNotCopyTheirPayloadIntoTheLog() {
        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>{
            signal('unknown_building', 'BLD-NO-EXISTE', 12.5),
            signal('incomplete', 'BLD-NO-EXISTE', null)
        };

        Test.startTest();
        TelemetryPublisher.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Signal_Log__c> logs = Database.query(
            'SELECT ' + String.join(customFieldNames(), ', ') + ' FROM Signal_Log__c WITH SYSTEM_MODE'
        );
        System.assertEquals(2, logs.size());
        for (Signal_Log__c log : logs) {
            System.assertEquals('Rejected', log.Result__c, log.Message_Id__c);
            String everything = JSON.serialize(log);
            System.assert(!everything.contains('SECRETO'), 'The log copied the payload: ' + everything);
        }
    }

    private static Telemetry_Signal__e signal(String key, String buildingCode, Decimal value) {
        String payload = JSON.serialize(
            new Map<String, Object>{ 'messageId' => 'msg_' + key, 'authorization' => FAKE_SECRET }
        );
        return new Telemetry_Signal__e(
            Delivery_Id__c = 'dlv_' + key,
            Message_Id__c = 'msg_' + key,
            Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
            Source__c = 'nova-casa-simulator',
            Building_Id__c = buildingCode,
            Asset_Id__c = 'AST-NO-EXISTE',
            Sensor_Id__c = FAKE_SECRET,
            Measurement_Type__c = 'WATER_PRESSURE',
            Measurement_Value__c = value,
            Measurement_Unit__c = 'BAR',
            Occurred_At__c = Datetime.newInstanceGmt(2026, 10, 5, 12, 0, 0),
            Raw_Payload__c = payload
        );
    }

    private static List<String> customFieldNames() {
        List<String> names = new List<String>{ 'Id', 'Name' };
        for (Schema.SObjectField token : Schema.SObjectType.Signal_Log__c.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isCustom()) {
                names.add(field.getName());
            }
        }
        return names;
    }
}
