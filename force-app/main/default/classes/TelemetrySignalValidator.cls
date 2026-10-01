/**
 * Apex A (BR-202): revisa que cada señal traiga lo que exige su tipo de mensaje.
 * No consulta nada. Una señal incompleta se rechaza aquí y no llega a Apex B.
 */
public inherited sharing class TelemetrySignalValidator {
    public static final String TYPE_MEASUREMENT = 'MEASUREMENT';
    public static final String TYPE_CONNECTIVITY = 'CONNECTIVITY';

    /** Devuelve el rechazo, o null si la señal está completa. */
    public static TelemetrySignalOutcome validate(Telemetry_Signal__e evt) {
        // Se compara sin distinguir mayúsculas, igual que los demás códigos (building, asset, unidad).
        String messageType = String.isBlank(evt.Message_Type__c) ? evt.Message_Type__c : evt.Message_Type__c.trim().toUpperCase();
        Boolean isMeasurement = messageType == TYPE_MEASUREMENT;
        Boolean isConnectivity = messageType == TYPE_CONNECTIVITY;
        if (String.isNotBlank(messageType) && !isMeasurement && !isConnectivity) {
            return TelemetrySignalOutcome.rejected(
                TelemetrySignalOutcome.REASON_UNKNOWN_MESSAGE_TYPE,
                'messageType "' + messageType.abbreviate(40) + '" no es ' + TYPE_MEASUREMENT + ' ni ' + TYPE_CONNECTIVITY + '.',
                false
            );
        }

        List<String> missing = new List<String>();
        requireText(missing, evt.Message_Id__c, 'messageId');
        requireText(missing, messageType, 'messageType');
        requireText(missing, evt.Building_Id__c, 'building.id');
        requireText(missing, evt.Asset_Id__c, 'asset.id');
        requireValue(missing, evt.Occurred_At__c, 'occurredAt');
        if (isMeasurement) {
            requireText(missing, evt.Measurement_Type__c, 'measurement.type');
            requireValue(missing, evt.Measurement_Value__c, 'measurement.value');
            requireText(missing, evt.Measurement_Unit__c, 'measurement.unit');
        } else if (isConnectivity) {
            requireText(missing, evt.Communication_Status__c, 'communication.status');
        }

        if (missing.isEmpty()) {
            return null;
        }
        return TelemetrySignalOutcome.rejected(
            TelemetrySignalOutcome.REASON_INCOMPLETE,
            'Falta o no se pudo leer: ' + String.join(missing, ', ') + '.',
            false
        );
    }

    private static void requireText(List<String> missing, String value, String field) {
        if (String.isBlank(value)) {
            missing.add(field);
        }
    }

    private static void requireValue(List<String> missing, Object value, String field) {
        if (value == null) {
            missing.add(field);
        }
    }
}
