/**
 * Clasifica una lectura como Normal, Warning o Critical.
 * Hoy es un placeholder: siempre devuelve Normal. La clasificación real contra los
 * umbrales de Measurement_Threshold__mdt llega con BR-204 (administrar límites) y
 * BR-206 (diferenciar la respuesta). Se aísla aquí para que US-203 solo tenga que
 * cambiar esta clase cuando Emiliano entregue los valores.
 */
public inherited sharing class SeverityClassifier {
    public static final String SEVERITY_NORMAL = 'Normal';
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_CRITICAL = 'Critical';

    // Deja a las pruebas forzar una severidad para validar la política de críticas atrasadas.
    @TestVisible
    private static String forced;

    /** Severidad de una medición numérica. Placeholder: Normal (ver BR-206). */
    public static String classifyMeasurement(String assetType, String measurementType, Decimal value) {
        return forced != null ? forced : SEVERITY_NORMAL;
    }

    /** Severidad de una señal de conectividad. Placeholder: Normal (ver BR-206). */
    public static String classifyConnectivity(String communicationStatus) {
        return forced != null ? forced : SEVERITY_NORMAL;
    }
}
