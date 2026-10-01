/**
 * BR-204: decide Normal, Warning o Critical comparando la lectura con los límites vigentes
 * de Measurement_Threshold__mdt. getAll() no gasta consultas SOQL, así que leer los límites
 * cuesta lo mismo para 1 señal que para 200. Los códigos se comparan sin distinguir mayúsculas.
 *
 * El valor exacto de un límite pertenece a la banda de ese límite:
 * Above: >= crítico es Critical; >= advertencia es Warning; lo demás es Normal.
 * Below: <= crítico es Critical; <= advertencia es Warning; lo demás es Normal.
 *
 * Sin registro, con un límite o la dirección vacíos, o con el crítico que no queda más allá
 * de la advertencia, la lectura no se clasifica: vuelve un motivo legible, nunca Normal.
 */
public inherited sharing class MeasurementSeverityClassifier {
    public static final String SEVERITY_NORMAL = 'Normal';
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_CRITICAL = 'Critical';

    public static final String DIRECTION_ABOVE = 'Above';
    public static final String DIRECTION_BELOW = 'Below';

    public static final String REASON_THRESHOLD_MISSING = 'THRESHOLD_MISSING';
    public static final String REASON_THRESHOLD_INCOMPLETE = 'THRESHOLD_INCOMPLETE';
    public static final String REASON_THRESHOLD_CONTRADICTORY = 'THRESHOLD_CONTRADICTORY';

    private static final Integer DETAIL_MAX = 255;

    @TestVisible
    private static List<Measurement_Threshold__mdt> testRecords;

    private final Map<String, Measurement_Threshold__mdt> thresholdByKey = new Map<String, Measurement_Threshold__mdt>();

    public static MeasurementSeverityClassifier load() {
        return new MeasurementSeverityClassifier(testRecords != null ? testRecords : Measurement_Threshold__mdt.getAll().values());
    }

    private MeasurementSeverityClassifier(List<Measurement_Threshold__mdt> records) {
        for (Measurement_Threshold__mdt record : records) {
            thresholdByKey.put(key(record.Asset_Type__c, record.Measurement_Type__c), record);
        }
    }

    /** La lectura tiene que venir ya validada: con valor, y con una unidad que el catálogo aceptó. */
    public Classification classify(String assetType, String measurementType, Decimal value) {
        Measurement_Threshold__mdt threshold = thresholdByKey.get(key(assetType, measurementType));
        String subject = '"' + measurementType + '" de "' + assetType + '"';

        if (threshold == null) {
            return unclassified(
                REASON_THRESHOLD_MISSING,
                'No hay límites configurados para ' + subject + '.'
            );
        }

        String direction = threshold.Alert_Direction__c;
        Decimal warning = threshold.Warning_Limit__c;
        Decimal critical = threshold.Critical_Limit__c;
        List<String> missing = new List<String>();
        if (String.isBlank(direction)) {
            missing.add('Alert Direction');
        }
        if (warning == null) {
            missing.add('Warning Limit');
        }
        if (critical == null) {
            missing.add('Critical Limit');
        }
        if (!missing.isEmpty()) {
            return unclassified(
                REASON_THRESHOLD_INCOMPLETE,
                'Faltan ' + String.join(missing, ', ') + ' en los límites de ' + subject + '.'
            );
        }

        Boolean above = direction == DIRECTION_ABOVE;
        if (above ? critical <= warning : critical >= warning) {
            return unclassified(
                REASON_THRESHOLD_CONTRADICTORY,
                'Los límites de ' + subject + ' son contradictorios: con dirección ' + direction +
                ', el crítico (' + critical + ') tiene que estar ' + (above ? 'por encima' : 'por debajo') +
                ' de la advertencia (' + warning + ').'
            );
        }

        if (above ? value >= critical : value <= critical) {
            return classified(SEVERITY_CRITICAL);
        }
        if (above ? value >= warning : value <= warning) {
            return classified(SEVERITY_WARNING);
        }
        return classified(SEVERITY_NORMAL);
    }

    private static String key(String assetType, String measurementType) {
        return normalize(assetType) + '|' + normalize(measurementType);
    }

    private static String normalize(String code) {
        return code == null ? '' : code.trim().toUpperCase();
    }

    /** severity es null cuando no se pudo clasificar; entonces reason y detail explican por qué. */
    public class Classification {
        public String severity { get; private set; }
        public String reason { get; private set; }
        public String detail { get; private set; }

        public Boolean isClassified() {
            return severity != null;
        }
    }

    private static Classification classified(String severity) {
        Classification result = new Classification();
        result.severity = severity;
        return result;
    }

    private static Classification unclassified(String reason, String detail) {
        Classification result = new Classification();
        result.reason = reason;
        result.detail = detail.left(DETAIL_MAX);
        return result;
    }
}
