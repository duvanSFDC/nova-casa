/**
 * Traduce un elemento de data[] del simulador a Telemetry_Signal__e.
 * No valida ni clasifica: solo conserva los hechos del contrato.
 */
public inherited sharing class TelemetrySignalMapper {
    private static final Integer RAW_PAYLOAD_MAX = 32768;

    public static Telemetry_Signal__e toEvent(Map<String, Object> item) {
        Map<String, Object> building = child(item, 'building');
        Map<String, Object> asset = child(item, 'asset');
        Map<String, Object> measurement = child(item, 'measurement');
        Map<String, Object> communication = child(item, 'communication');

        return new Telemetry_Signal__e(
            Delivery_Id__c = text(item.get('deliveryId')),
            Message_Id__c = text(item.get('messageId')),
            Message_Type__c = text(item.get('messageType')),
            Source__c = text(item.get('source')),
            Building_Id__c = text(building.get('id')),
            Building_Name__c = text(building.get('name')),
            Building_City__c = text(building.get('city')),
            Asset_Id__c = text(asset.get('id')),
            Asset_Name__c = text(asset.get('name')),
            Asset_Type__c = text(asset.get('type')),
            Sensor_Id__c = text(item.get('sensorId')),
            Measurement_Type__c = text(measurement.get('type')),
            Measurement_Value__c = decimalValue(measurement.get('value')),
            Measurement_Unit__c = text(measurement.get('unit')),
            Communication_Status__c = text(communication.get('status')),
            Gap_Seconds__c = decimalValue(communication.get('gapSeconds')),
            Last_Seen_At__c = parseDatetime(communication.get('lastSeenAt')),
            Episode_Id__c = text(communication.get('episodeId')),
            Occurred_At__c = parseDatetime(item.get('occurredAt')),
            Source_Published_At__c = parseDatetime(item.get('publishedAt')),
            Raw_Payload__c = JSON.serialize(item).left(RAW_PAYLOAD_MAX)
        );
    }

    /** ISO-8601 con zona (2026-09-29T04:01:47.914Z). Devuelve null si falta o no se puede leer. */
    public static Datetime parseDatetime(Object value) {
        if (!(value instanceof String) || String.isBlank((String) value)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize(JSON.serialize(value), Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> child(Map<String, Object> item, String key) {
        Object value = item.get(key);
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }

    private static String text(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}
