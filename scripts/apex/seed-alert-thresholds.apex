// Carga los umbrales de alerta iniciales en Alert_Threshold__c.
// Solo crea los que faltan: un umbral que ya existe no se toca, para no pisar un límite
// que la coordinación ya ajustó. Se puede correr las veces que haga falta.
// Corre con los permisos de quien lo ejecuta: hace falta Nova_Admin.
//   sf apex run --file scripts/apex/seed-alert-thresholds.apex --target-org novacasa
// Los valores son de ejemplo hasta que Emiliano defina los reales.
List<Alert_Threshold__c> seed = new List<Alert_Threshold__c>{
    new Alert_Threshold__c(Asset_Type__c = 'WATER_PUMP', Measurement_Type__c = 'WATER_PRESSURE', Unit__c = 'BAR',
        Alert_Direction__c = 'Below', Warning_Limit__c = 1.5, Critical_Limit__c = 1.0),
    new Alert_Threshold__c(Asset_Type__c = 'TECHNICAL_ROOM', Measurement_Type__c = 'TEMPERATURE', Unit__c = 'CELSIUS',
        Alert_Direction__c = 'Above', Warning_Limit__c = 30, Critical_Limit__c = 35),
    new Alert_Threshold__c(Asset_Type__c = 'WATER_METER', Measurement_Type__c = 'WATER_CONSUMPTION', Unit__c = 'LITER_PER_15_MIN',
        Alert_Direction__c = 'Above', Warning_Limit__c = 600, Critical_Limit__c = 1000),
    new Alert_Threshold__c(Asset_Type__c = 'ENERGY_METER', Measurement_Type__c = 'ENERGY_CONSUMPTION', Unit__c = 'KWH_PER_15_MIN',
        Alert_Direction__c = 'Above', Warning_Limit__c = 40, Critical_Limit__c = 60)
};

Set<String> existing = new Set<String>();
for (Alert_Threshold__c threshold : [SELECT Threshold_Key__c FROM Alert_Threshold__c WITH USER_MODE]) {
    existing.add(threshold.Threshold_Key__c.toUpperCase());
}

List<Alert_Threshold__c> missing = new List<Alert_Threshold__c>();
for (Alert_Threshold__c threshold : seed) {
    threshold.Threshold_Key__c = threshold.Asset_Type__c + '|' + threshold.Measurement_Type__c;
    if (!existing.contains(threshold.Threshold_Key__c)) {
        missing.add(threshold);
    }
}
Database.insert(missing, AccessLevel.USER_MODE);
System.debug(LoggingLevel.ERROR, '>>> UMBRALES creados=' + missing.size() + ' ya existían=' + (seed.size() - missing.size()));
