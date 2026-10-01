@IsTest
private class TelemetrySignalValidatorTest {
    private static Telemetry_Signal__e measurement() {
        return new Telemetry_Signal__e(
            Message_Id__c = 'msg_1',
            Message_Type__c = TelemetrySignalValidator.TYPE_MEASUREMENT,
            Building_Id__c = 'BLD-BOG-001',
            Asset_Id__c = 'AST-BOG-PUMP-001',
            Measurement_Type__c = 'WATER_PRESSURE',
            Measurement_Value__c = 0.7,
            Measurement_Unit__c = 'BAR',
            Occurred_At__c = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0)
        );
    }

    private static Telemetry_Signal__e connectivity() {
        return new Telemetry_Signal__e(
            Message_Id__c = 'msg_2',
            Message_Type__c = TelemetrySignalValidator.TYPE_CONNECTIVITY,
            Building_Id__c = 'BLD-BAQ-001',
            Asset_Id__c = 'AST-BAQ-CAM-001',
            Communication_Status__c = 'LOST',
            Occurred_At__c = Datetime.newInstanceGmt(2026, 9, 29, 4, 0, 0)
        );
    }

    @IsTest
    static void completeSignalsPass() {
        Assert.isNull(TelemetrySignalValidator.validate(measurement()), 'Una medición completa pasa a Apex B');
        Assert.isNull(TelemetrySignalValidator.validate(connectivity()), 'La conectividad no exige bloque measurement');
    }

    @IsTest
    static void missingValueIsIncompleteAndNotRetrySafe() {
        Telemetry_Signal__e evt = measurement();
        evt.Measurement_Value__c = null;

        TelemetrySignalOutcome outcome = TelemetrySignalValidator.validate(evt);

        Assert.areEqual(TelemetrySignalOutcome.RESULT_REJECTED, outcome.result);
        Assert.areEqual(TelemetrySignalOutcome.REASON_INCOMPLETE, outcome.reason);
        Assert.areEqual('Falta o no se pudo leer: measurement.value.', outcome.detail);
        Assert.isFalse(outcome.retrySafe, 'El dato de origen está mal: reintentar daría lo mismo');
        Assert.isNull(outcome.assetId, 'Apex A no consulta, así que no enlaza el equipo');
    }

    @IsTest
    static void listsEveryMissingFieldInOneDetail() {
        Telemetry_Signal__e evt = measurement();
        evt.Message_Id__c = '';
        evt.Occurred_At__c = null;
        evt.Measurement_Unit__c = ' ';

        TelemetrySignalOutcome outcome = TelemetrySignalValidator.validate(evt);

        Assert.areEqual(TelemetrySignalOutcome.REASON_INCOMPLETE, outcome.reason);
        Assert.areEqual('Falta o no se pudo leer: messageId, occurredAt, measurement.unit.', outcome.detail);
    }

    @IsTest
    static void connectivityWithoutStatusIsIncomplete() {
        Telemetry_Signal__e evt = connectivity();
        evt.Communication_Status__c = null;

        TelemetrySignalOutcome outcome = TelemetrySignalValidator.validate(evt);

        Assert.areEqual(TelemetrySignalOutcome.REASON_INCOMPLETE, outcome.reason);
        Assert.areEqual('Falta o no se pudo leer: communication.status.', outcome.detail);
    }

    @IsTest
    static void missingMessageTypeIsIncomplete() {
        Telemetry_Signal__e evt = measurement();
        evt.Message_Type__c = null;

        TelemetrySignalOutcome outcome = TelemetrySignalValidator.validate(evt);

        Assert.areEqual(TelemetrySignalOutcome.REASON_INCOMPLETE, outcome.reason);
        Assert.areEqual('Falta o no se pudo leer: messageType.', outcome.detail);
    }

    @IsTest
    static void messageTypeIsCaseInsensitive() {
        Telemetry_Signal__e evt = measurement();
        evt.Message_Type__c = ' measurement ';

        Assert.isNull(TelemetrySignalValidator.validate(evt), 'El tipo se compara sin distinguir mayúsculas ni espacios');
    }

    @IsTest
    static void unknownMessageTypeIsRejected() {
        Telemetry_Signal__e evt = measurement();
        evt.Message_Type__c = 'FIRMWARE';

        TelemetrySignalOutcome outcome = TelemetrySignalValidator.validate(evt);

        Assert.areEqual(TelemetrySignalOutcome.REASON_UNKNOWN_MESSAGE_TYPE, outcome.reason);
        Assert.isTrue(outcome.detail.contains('FIRMWARE'), outcome.detail);
        Assert.isFalse(outcome.retrySafe);
    }
}
