/**
 * Apex B, primera parte (BR-202): reconoce el edificio y el equipo de cada señal por su
 * código y revisa que la medición sea compatible con el tipo de equipo guardado en Salesforce.
 * Hace una consulta de Location y una de Asset para todo el lote, sin importar cuántas señales traiga.
 * La señal nunca crea edificios ni equipos: un código que no existe se rechaza.
 * Corre como Automated Process, así que lee en modo sistema (ver README).
 */
public inherited sharing class TelemetrySignalProcessor {
    /** Recibe solo señales que pasaron Apex A. Devuelve una decisión por señal, en el mismo orden. */
    public static List<TelemetrySignalOutcome> process(List<Telemetry_Signal__e> events) {
        List<TelemetrySignalOutcome> outcomes = new List<TelemetrySignalOutcome>();
        if (events.isEmpty()) {
            return outcomes;
        }

        Set<String> buildingCodes = new Set<String>();
        Set<String> assetCodes = new Set<String>();
        for (Telemetry_Signal__e evt : events) {
            buildingCodes.add(normalize(evt.Building_Id__c));
            assetCodes.add(normalize(evt.Asset_Id__c));
        }

        Map<String, Id> locationIdByCode = new Map<String, Id>();
        for (Schema.Location building : [
            SELECT Id, External_Id__c
            FROM Location
            WHERE External_Id__c IN :buildingCodes
            WITH SYSTEM_MODE
        ]) {
            locationIdByCode.put(normalize(building.External_Id__c), building.Id);
        }

        Map<String, Asset> assetByCode = new Map<String, Asset>();
        for (Asset equipment : [
            SELECT Id, External_Id__c, LocationId, Asset_Type__c
            FROM Asset
            WHERE External_Id__c IN :assetCodes
            WITH SYSTEM_MODE
        ]) {
            assetByCode.put(normalize(equipment.External_Id__c), equipment);
        }

        MeasurementCatalog catalog = MeasurementCatalog.load();
        for (Telemetry_Signal__e evt : events) {
            outcomes.add(resolve(evt, locationIdByCode, assetByCode, catalog));
        }
        return outcomes;
    }

    private static TelemetrySignalOutcome resolve(
        Telemetry_Signal__e evt,
        Map<String, Id> locationIdByCode,
        Map<String, Asset> assetByCode,
        MeasurementCatalog catalog
    ) {
        Id locationId = locationIdByCode.get(normalize(evt.Building_Id__c));
        Asset equipment = assetByCode.get(normalize(evt.Asset_Id__c));
        Id assetId = equipment == null ? null : equipment.Id;

        if (locationId == null) {
            return TelemetrySignalOutcome.rejected(
                    TelemetrySignalOutcome.REASON_UNKNOWN_BUILDING,
                    'El edificio "' + evt.Building_Id__c + '" no existe en Salesforce.',
                    true
                )
                .withReferences(assetId, null);
        }
        if (equipment == null) {
            return TelemetrySignalOutcome.rejected(
                    TelemetrySignalOutcome.REASON_UNKNOWN_ASSET,
                    'El equipo "' + evt.Asset_Id__c + '" no existe en Salesforce.',
                    true
                )
                .withReferences(null, locationId);
        }
        if (equipment.LocationId == null) {
            return TelemetrySignalOutcome.rejected(
                    TelemetrySignalOutcome.REASON_ASSET_NOT_IN_BUILDING,
                    'El equipo "' + evt.Asset_Id__c + '" no tiene edificio asignado en Salesforce.',
                    true
                )
                .withReferences(assetId, locationId);
        }
        if (equipment.LocationId != locationId) {
            return TelemetrySignalOutcome.rejected(
                    TelemetrySignalOutcome.REASON_ASSET_NOT_IN_BUILDING,
                    'El equipo "' + evt.Asset_Id__c + '" no pertenece al edificio "' + evt.Building_Id__c + '".',
                    true
                )
                .withReferences(assetId, locationId);
        }
        if (TelemetrySignalValidator.TYPE_MEASUREMENT.equalsIgnoreCase(evt.Message_Type__c)) {
            TelemetrySignalOutcome incompatible = checkMeasurement(evt, equipment, catalog);
            if (incompatible != null) {
                return incompatible.withReferences(assetId, locationId);
            }
        }
        return TelemetrySignalOutcome.accepted(assetId, locationId);
    }

    private static TelemetrySignalOutcome checkMeasurement(Telemetry_Signal__e evt, Asset equipment, MeasurementCatalog catalog) {
        if (String.isBlank(equipment.Asset_Type__c)) {
            return TelemetrySignalOutcome.rejected(
                TelemetrySignalOutcome.REASON_UNSUPPORTED_MEASUREMENT,
                'El equipo "' + evt.Asset_Id__c + '" no tiene Asset Type en Salesforce.',
                true
            );
        }
        String expectedUnit = catalog.unitFor(equipment.Asset_Type__c, evt.Measurement_Type__c);
        if (expectedUnit == null) {
            return TelemetrySignalOutcome.rejected(
                TelemetrySignalOutcome.REASON_UNSUPPORTED_MEASUREMENT,
                'La medición ' + evt.Measurement_Type__c + ' no está configurada para equipos ' + equipment.Asset_Type__c + '.',
                true
            );
        }
        String actualUnit = evt.Measurement_Unit__c == null ? null : evt.Measurement_Unit__c.trim();
        if (!expectedUnit.equalsIgnoreCase(actualUnit)) {
            return TelemetrySignalOutcome.rejected(
                TelemetrySignalOutcome.REASON_INCOMPATIBLE_UNIT,
                'Llegó en ' + evt.Measurement_Unit__c + ' y ' + evt.Measurement_Type__c + ' se mide en ' + expectedUnit + '.',
                false
            );
        }
        return null;
    }

    private static String normalize(String code) {
        return code == null ? null : code.trim().toUpperCase();
    }
}
