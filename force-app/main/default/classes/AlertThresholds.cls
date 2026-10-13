/**
 * Lee los umbrales de Alert_Threshold__c una sola vez por transacción y los comparte entre
 * MeasurementCatalog y MeasurementSeverityClassifier: el lote gasta una consulta, tenga 1
 * o 200 señales. Lee en modo sistema porque el suscriptor corre como Automated Process.
 */
public inherited sharing class AlertThresholds {
    private static List<Alert_Threshold__c> cached;

    public static List<Alert_Threshold__c> all() {
        if (cached == null) {
            cached = [
                SELECT Asset_Type__c, Measurement_Type__c, Unit__c, Alert_Direction__c, Warning_Limit__c, Critical_Limit__c
                FROM Alert_Threshold__c
                WITH SYSTEM_MODE
            ];
        }
        return cached;
    }

    /** En la org cada lote es su propia transacción; un test que mide varios lotes seguidos lo simula así. */
    @TestVisible
    private static void forget() {
        cached = null;
    }
}
