/**
 * Lo que el suscriptor decidió sobre una señal: el resultado, el motivo del rechazo,
 * un detalle legible para Camila, si es seguro reintentar, cuando se reconocieron,
 * el equipo y el edificio, y la severidad de una medición aceptada. Los valores son los del picklist de Signal_Log__c.
 */
public inherited sharing class TelemetrySignalOutcome {
    public static final String RESULT_ACCEPTED = 'Accepted';
    public static final String RESULT_REJECTED = 'Rejected';
    public static final String RESULT_LATE = 'Late';
    public static final String RESULT_DUPLICATE = 'Duplicate';

    public static final String REASON_INCOMPLETE = 'INCOMPLETE';
    public static final String REASON_UNKNOWN_MESSAGE_TYPE = 'UNKNOWN_MESSAGE_TYPE';
    public static final String REASON_UNKNOWN_BUILDING = 'UNKNOWN_BUILDING';
    public static final String REASON_UNKNOWN_ASSET = 'UNKNOWN_ASSET';
    public static final String REASON_ASSET_NOT_IN_BUILDING = 'ASSET_NOT_IN_BUILDING';
    public static final String REASON_UNSUPPORTED_MEASUREMENT = 'UNSUPPORTED_MEASUREMENT';
    public static final String REASON_INCOMPATIBLE_UNIT = 'INCOMPATIBLE_UNIT';
    public static final String REASON_THRESHOLD_MISSING = MeasurementSeverityClassifier.REASON_THRESHOLD_MISSING;
    public static final String REASON_THRESHOLD_INCOMPLETE = MeasurementSeverityClassifier.REASON_THRESHOLD_INCOMPLETE;
    public static final String REASON_THRESHOLD_CONTRADICTORY = MeasurementSeverityClassifier.REASON_THRESHOLD_CONTRADICTORY;
    public static final String REASON_IDENTITY_CONFLICT = 'IDENTITY_CONFLICT';
    public static final String REASON_INTERVENTION_FAILED = 'INTERVENTION_FAILED';

    private static final Integer DETAIL_MAX = 255;

    public String result { get; private set; }
    public String reason { get; private set; }
    public String detail { get; private set; }
    public Boolean retrySafe { get; private set; }
    public Id assetId { get; private set; }
    public Id locationId { get; private set; }
    /** Solo en mediciones aceptadas: Normal, Warning o Critical según los límites vigentes. */
    public String severity { get; private set; }
    /** Intervención (Work Order) relacionada: la que creó una crítica o la que reutiliza un reenvío. */
    public Id workOrderId { get; private set; }

    private TelemetrySignalOutcome(String result, String reason, String detail, Boolean retrySafe) {
        this.result = result;
        this.reason = reason;
        this.detail = detail == null ? null : detail.left(DETAIL_MAX);
        this.retrySafe = retrySafe;
    }

    public static TelemetrySignalOutcome accepted(Id assetId, Id locationId) {
        return new TelemetrySignalOutcome(RESULT_ACCEPTED, null, null, false).withReferences(assetId, locationId);
    }

    /**
     * retrySafe es verdadero cuando el rechazo se corrige en Salesforce (el catálogo o la CMDT)
     * y falso cuando el dato de origen está mal y reprocesarlo daría lo mismo.
     */
    public static TelemetrySignalOutcome rejected(String reason, String detail, Boolean retrySafe) {
        return new TelemetrySignalOutcome(RESULT_REJECTED, reason, detail, retrySafe);
    }

    /**
     * La señal es válida pero no es más nueva que la lectura actual del activo (BR-203),
     * así que no reemplaza el estado. Queda en el log como Atrasada, con el equipo y el
     * edificio que ya se habían reconocido. No es un rechazo: no lleva motivo.
     */
    public static TelemetrySignalOutcome late(Id assetId, Id locationId, String detail) {
        return new TelemetrySignalOutcome(RESULT_LATE, null, detail, false).withReferences(assetId, locationId);
    }

    /**
     * Un reenvío (mismo messageId, mismo contenido) de una señal ya procesada (BR-205): no crea
     * otra intervención ni vuelve a tocar el estado; reutiliza y enlaza el resultado existente.
     */
    public static TelemetrySignalOutcome duplicate(Id assetId, Id locationId, Id workOrderId, String detail) {
        return new TelemetrySignalOutcome(RESULT_DUPLICATE, null, detail, false)
            .withReferences(assetId, locationId)
            .withWorkOrder(workOrderId);
    }

    public TelemetrySignalOutcome withReferences(Id assetId, Id locationId) {
        this.assetId = assetId;
        this.locationId = locationId;
        return this;
    }

    public TelemetrySignalOutcome withSeverity(String severity) {
        this.severity = severity;
        return this;
    }

    public TelemetrySignalOutcome withWorkOrder(Id workOrderId) {
        this.workOrderId = workOrderId;
        return this;
    }

    /** Escribe la decisión en el log. Limpia lo que hubiera de un procesamiento anterior. */
    public void applyTo(Signal_Log__c log) {
        log.Result__c = result;
        log.Reason__c = reason;
        log.Error__c = detail;
        log.Retry_Safe__c = retrySafe;
        log.Asset__c = assetId;
        log.Location__c = locationId;
        log.Severity__c = severity;
        log.Work_Order__c = workOrderId;
    }
}
