/**
 * Pantalla de umbrales de la coordinación. Lee y guarda con los permisos de quien la usa:
 * Javier ajusta solo los dos límites porque su permiso no le deja editar más, y las reglas de
 * validación de Alert_Threshold__c rechazan un umbral contradictorio o vacío. Al guardar solo
 * se copian el Id y los dos límites, aunque el cliente mande otros campos.
 */
public with sharing class AlertThresholdController {
    @AuraEnabled
    public static List<Row> getThresholds() {
        try {
            Map<String, String> assetTypeLabels = assetTypeLabels();
            Boolean canEdit = canEditLimits();

            List<Row> rows = new List<Row>();
            for (Alert_Threshold__c threshold : [
                SELECT Id, Asset_Type__c, Measurement_Type__c, Unit__c, Alert_Direction__c,
                    Warning_Limit__c, Critical_Limit__c, LastModifiedDate, LastModifiedBy.Name
                FROM Alert_Threshold__c
                WITH USER_MODE
                ORDER BY Asset_Type__c, Measurement_Type__c
            ]) {
                rows.add(new Row(threshold, assetTypeLabels, canEdit));
            }
            return rows;
        } catch (Exception e) {
            throw handled('No pudimos consultar los umbrales.');
        }
    }

    /** Devuelve un error por umbral que no se guardó; vacío si se guardaron todos. */
    @AuraEnabled
    public static List<SaveError> saveLimits(List<LimitChange> changes) {
        if (!canEditLimits()) {
            throw handled('No tienes permiso para cambiar los umbrales.');
        }
        List<Alert_Threshold__c> records = new List<Alert_Threshold__c>();
        for (LimitChange change : changes == null ? new List<LimitChange>() : changes) {
            records.add(
                new Alert_Threshold__c(
                    Id = change.id,
                    Warning_Limit__c = change.warningLimit,
                    Critical_Limit__c = change.criticalLimit
                )
            );
        }

        List<Database.SaveResult> results;
        try {
            results = Database.update(records, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw handled('No tienes permiso para cambiar los umbrales.');
        }

        List<SaveError> errors = new List<SaveError>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                List<String> messages = new List<String>();
                for (Database.Error error : results[i].getErrors()) {
                    messages.add(error.getMessage());
                }
                errors.add(new SaveError(records[i].Id, String.join(messages, ' ')));
            }
        }
        return errors;
    }

    private static Boolean canEditLimits() {
        return Schema.SObjectType.Alert_Threshold__c.isUpdateable() &&
            Schema.SObjectType.Alert_Threshold__c.fields.Warning_Limit__c.isUpdateable() &&
            Schema.SObjectType.Alert_Threshold__c.fields.Critical_Limit__c.isUpdateable();
    }

    private static Map<String, String> assetTypeLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : Asset.Asset_Type__c.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue().toUpperCase(), entry.getLabel());
        }
        return labels;
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String unitLabel;
        @AuraEnabled public String direction;
        @AuraEnabled public Decimal warningLimit;
        @AuraEnabled public Decimal criticalLimit;
        @AuraEnabled public Datetime lastModifiedAt;
        @AuraEnabled public String lastModifiedBy;
        @AuraEnabled public Boolean canEdit;

        Row(Alert_Threshold__c threshold, Map<String, String> assetTypeLabels, Boolean canEdit) {
            String assetType = threshold.Asset_Type__c == null ? '' : threshold.Asset_Type__c.toUpperCase();
            String assetLabel = assetTypeLabels.containsKey(assetType) ? assetTypeLabels.get(assetType) : threshold.Asset_Type__c;
            id = threshold.Id;
            name = assetLabel + ' · ' + MeasurementLabels.typeLabel(threshold.Measurement_Type__c);
            unitLabel = MeasurementLabels.unitLabel(threshold.Unit__c);
            direction = threshold.Alert_Direction__c;
            warningLimit = threshold.Warning_Limit__c;
            criticalLimit = threshold.Critical_Limit__c;
            lastModifiedAt = threshold.LastModifiedDate;
            lastModifiedBy = threshold.LastModifiedBy?.Name;
            this.canEdit = canEdit;
        }
    }

    public class LimitChange {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Decimal warningLimit { get; set; }
        @AuraEnabled public Decimal criticalLimit { get; set; }
    }

    public class SaveError {
        @AuraEnabled public Id id;
        @AuraEnabled public String message;

        SaveError(Id id, String message) {
            this.id = id;
            this.message = message;
        }
    }
}
