/**
 * Qué unidad acepta cada tipo de equipo y medición, según Measurement_Threshold__mdt.
 * getAll() no gasta consultas SOQL. Los códigos se comparan sin distinguir mayúsculas.
 */
public inherited sharing class MeasurementCatalog {
    @TestVisible
    private static List<Measurement_Threshold__mdt> testRecords;

    private final Map<String, String> unitByKey = new Map<String, String>();

    public static MeasurementCatalog load() {
        return new MeasurementCatalog(testRecords != null ? testRecords : Measurement_Threshold__mdt.getAll().values());
    }

    private MeasurementCatalog(List<Measurement_Threshold__mdt> records) {
        for (Measurement_Threshold__mdt record : records) {
            unitByKey.put(key(record.Asset_Type__c, record.Measurement_Type__c), record.Unit__c);
        }
    }

    /** Unidad esperada, o null si esa medición no está configurada para ese tipo de equipo. */
    public String unitFor(String assetType, String measurementType) {
        return unitByKey.get(key(assetType, measurementType));
    }

    private static String key(String assetType, String measurementType) {
        return normalize(assetType) + '|' + normalize(measurementType);
    }

    private static String normalize(String code) {
        return code == null ? '' : code.trim().toUpperCase();
    }
}
