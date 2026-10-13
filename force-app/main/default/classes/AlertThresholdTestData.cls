/**
 * Guarda umbrales en la base de prueba para que las clases los lean por la misma consulta
 * que en la org, y así los tests de costo cuenten esa consulta.
 */
@IsTest
public class AlertThresholdTestData {
    public static List<Alert_Threshold__c> save(List<Alert_Threshold__c> records) {
        for (Alert_Threshold__c record : records) {
            record.Threshold_Key__c = record.Asset_Type__c.toUpperCase() + '|' + record.Measurement_Type__c.toUpperCase();
        }
        Database.insert(records, AccessLevel.SYSTEM_MODE);
        return records;
    }
}
