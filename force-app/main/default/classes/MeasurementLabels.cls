/**
 * Nombres amigables en español para tipos de medición y unidades. Es la fuente única
 * en Apex, en paralelo con lwc/operatorStatus/labels.js (mismos textos). Se usa para
 * que la causa de la intervención (WorkOrder.Subject) se lea para una persona y no con
 * códigos del simulador. Un código desconocido se devuelve tal cual llegó.
 */
public inherited sharing class MeasurementLabels {
    private static final Map<String, String> TYPE_LABELS = new Map<String, String>{
        'WATER_PRESSURE' => 'presión de agua',
        'TEMPERATURE' => 'temperatura',
        'WATER_CONSUMPTION' => 'consumo de agua',
        'ENERGY_CONSUMPTION' => 'consumo de energía',
        'CONNECTIVITY' => 'conectividad'
    };

    private static final Map<String, String> UNIT_LABELS = new Map<String, String>{
        'BAR' => 'bar',
        'CELSIUS' => '°C',
        'LITER_PER_15_MIN' => 'L/15 min',
        'KWH_PER_15_MIN' => 'kWh/15 min'
    };

    /** Nombre amigable del tipo de medición, o el mismo código si no está mapeado. */
    public static String typeLabel(String code) {
        return label(TYPE_LABELS, code);
    }

    /** Nombre amigable de la unidad, o el mismo código si no está mapeado. */
    public static String unitLabel(String code) {
        return label(UNIT_LABELS, code);
    }

    private static String label(Map<String, String> table, String code) {
        if (String.isBlank(code)) {
            return code;
        }
        String friendly = table.get(code.trim().toUpperCase());
        return friendly == null ? code : friendly;
    }
}
