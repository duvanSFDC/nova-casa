/**
 * Lista que consulta Laura. Una fila por lectura vigente y, si el equipo no ha
 * reportado, una fila sin lectura. La intervención abierta es el Work Order
 * más antiguo del mismo activo con IsClosed en falso.
 * Corre con los permisos de quien pregunta (BR-208).
 */
public with sharing class OperatorStatusService {
    public static final Set<String> SEVERITIES = new Set<String>{ 'Normal', 'Warning', 'Critical' };

    public class Row {
        @AuraEnabled public String rowKey;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public Id buildingId;
        @AuraEnabled public String buildingName;
        @AuraEnabled public Boolean hasReading;
        @AuraEnabled public Id conditionId;
        @AuraEnabled public String measurementType;
        @AuraEnabled public Decimal measurementValue;
        @AuraEnabled public String measurementUnit;
        @AuraEnabled public String severity;
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
    }

    public class Result {
        @AuraEnabled public Datetime consultedAt;
        @AuraEnabled public List<Row> rows;
    }

    public class Building {
        @AuraEnabled public Id buildingId;
        @AuraEnabled public String buildingName;
    }

    @AuraEnabled
    public static Result getAssets(Id buildingId, String severity) {
        Result result = new Result();
        result.consultedAt = Datetime.now();
        result.rows = loadRows(buildingId, normalizeSeverity(severity));
        return result;
    }

    @AuraEnabled
    public static List<Building> getBuildings() {
        List<Building> buildings = new List<Building>();
        try {
            for (Schema.Location building : [
                SELECT Id, Name
                FROM Location
                WHERE Id IN (SELECT LocationId FROM Asset)
                WITH USER_MODE
                ORDER BY Name
            ]) {
                Building option = new Building();
                option.buildingId = building.Id;
                option.buildingName = building.Name;
                buildings.add(option);
            }
        } catch (QueryException error) {
            throw handled('No pudimos consultar los edificios.');
        }
        return buildings;
    }

    private static List<Row> loadRows(Id buildingId, String severity) {
        List<Asset> assets;
        try {
            assets = queryAssets(buildingId);
        } catch (QueryException error) {
            throw handled('No pudimos consultar los equipos.');
        }
        if (assets.isEmpty()) {
            return new List<Row>();
        }

        Map<Id, Asset> assetsById = new Map<Id, Asset>(assets);
        Map<Id, List<Asset_Condition__c>> conditionsByAsset;
        Map<Id, WorkOrder> openWorkOrderByAsset;
        try {
            conditionsByAsset = queryConditions(assetsById.keySet(), severity);
            openWorkOrderByAsset = queryOpenWorkOrders(assetsById.keySet());
        } catch (QueryException error) {
            throw handled('No pudimos consultar los equipos.');
        }

        List<Row> rows = new List<Row>();
        for (Asset asset : assets) {
            List<Asset_Condition__c> conditions = conditionsByAsset.get(asset.Id);
            WorkOrder openOrder = openWorkOrderByAsset.get(asset.Id);
            if (conditions == null || conditions.isEmpty()) {
                if (severity == null) {
                    rows.add(withoutReading(asset, openOrder));
                }
                continue;
            }
            for (Asset_Condition__c condition : conditions) {
                rows.add(fromCondition(asset, condition, openOrder));
            }
        }
        return rows;
    }

    private static List<Asset> queryAssets(Id buildingId) {
        if (buildingId == null) {
            return [
                SELECT Id, Name, LocationId, Location.Name
                FROM Asset
                WITH USER_MODE
                ORDER BY Location.Name NULLS LAST, Name
            ];
        }
        return [
            SELECT Id, Name, LocationId, Location.Name
            FROM Asset
            WHERE LocationId = :buildingId
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    private static Map<Id, List<Asset_Condition__c>> queryConditions(Set<Id> assetIds, String severity) {
        List<Asset_Condition__c> conditions;
        if (severity == null) {
            conditions = [
                SELECT Id, Asset__c, Measurement_Type__c, Measurement_Value__c,
                    Measurement_Unit__c, Severity__c, Occurred_At__c
                FROM Asset_Condition__c
                WHERE Asset__c IN :assetIds
                WITH USER_MODE
                ORDER BY Measurement_Type__c
            ];
        } else {
            conditions = [
                SELECT Id, Asset__c, Measurement_Type__c, Measurement_Value__c,
                    Measurement_Unit__c, Severity__c, Occurred_At__c
                FROM Asset_Condition__c
                WHERE Asset__c IN :assetIds AND Severity__c = :severity
                WITH USER_MODE
                ORDER BY Measurement_Type__c
            ];
        }

        Map<Id, List<Asset_Condition__c>> byAsset = new Map<Id, List<Asset_Condition__c>>();
        for (Asset_Condition__c condition : conditions) {
            if (!byAsset.containsKey(condition.Asset__c)) {
                byAsset.put(condition.Asset__c, new List<Asset_Condition__c>());
            }
            byAsset.get(condition.Asset__c).add(condition);
        }
        return byAsset;
    }

    private static Map<Id, WorkOrder> queryOpenWorkOrders(Set<Id> assetIds) {
        Map<Id, WorkOrder> byAsset = new Map<Id, WorkOrder>();
        for (WorkOrder openOrder : [
            SELECT Id, WorkOrderNumber, AssetId
            FROM WorkOrder
            WHERE AssetId IN :assetIds AND IsClosed = false
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!byAsset.containsKey(openOrder.AssetId)) {
                byAsset.put(openOrder.AssetId, openOrder);
            }
        }
        return byAsset;
    }

    private static Row fromCondition(Asset asset, Asset_Condition__c condition, WorkOrder openOrder) {
        Row row = baseRow(asset, openOrder);
        row.rowKey = condition.Id;
        row.hasReading = true;
        row.conditionId = condition.Id;
        row.measurementType = condition.Measurement_Type__c;
        row.measurementValue = condition.Measurement_Value__c;
        row.measurementUnit = condition.Measurement_Unit__c;
        row.severity = condition.Severity__c;
        row.occurredAt = condition.Occurred_At__c;
        return row;
    }

    private static Row withoutReading(Asset asset, WorkOrder openOrder) {
        Row row = baseRow(asset, openOrder);
        row.rowKey = asset.Id + ':none';
        row.hasReading = false;
        return row;
    }

    private static Row baseRow(Asset asset, WorkOrder openOrder) {
        Row row = new Row();
        row.assetId = asset.Id;
        row.assetName = asset.Name;
        row.buildingId = asset.LocationId;
        row.buildingName = asset.Location == null ? null : asset.Location.Name;
        if (openOrder != null) {
            row.workOrderId = openOrder.Id;
            row.workOrderNumber = openOrder.WorkOrderNumber;
        }
        return row;
    }

    private static String normalizeSeverity(String severity) {
        if (String.isBlank(severity)) {
            return null;
        }
        if (!SEVERITIES.contains(severity)) {
            throw handled('Severidad no reconocida.');
        }
        return severity;
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}