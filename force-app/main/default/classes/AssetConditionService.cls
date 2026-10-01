/**
 * Apex B, parte 2 (BR-203): mantiene la lectura válida más reciente de cada activo y
 * tipo de medición en Asset_Condition__c. Recibe las señales que ya aceptó
 * TelemetrySignalProcessor y, por cada activo+tipo, conserva la de mayor occurredAt.
 *
 * Una señal que no es estrictamente más nueva que la lectura actual no reemplaza el
 * estado: se marca como Atrasada (Late), sin importar su severidad, y no dispara ninguna
 * acción (Apex nunca abre Work Orders). Así una señal vieja no hace que Laura actúe sobre
 * información desactualizada.
 *
 * Corre como Automated Process, así que lee y escribe en modo sistema (ver README).
 * Todo es por lote: una consulta a Asset_Condition__c y un upsert, sin SOQL ni DML por señal.
 */
public inherited sharing class AssetConditionService {
    public static final String CONNECTIVITY_TYPE = 'CONNECTIVITY';
    private static final Integer NAME_MAX = 80;

    /**
     * Actualiza el estado actual con las señales aceptadas del lote y convierte en Late
     * las que no son más nuevas. Reemplaza en la lista outcomes las posiciones que cambian.
     */
    public static void updateCurrentState(List<Telemetry_Signal__e> events, List<TelemetrySignalOutcome> outcomes) {
        // 1. Agrupar las aceptadas por llave (activo + tipo) y hallar la ganadora del lote.
        Map<String, Integer> winnerIndexByKey = new Map<String, Integer>();
        Map<Integer, String> keyByIndex = new Map<Integer, String>();
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].result != TelemetrySignalOutcome.RESULT_ACCEPTED) {
                continue;
            }
            String key = conditionKey(outcomes[i].assetId, events[i]);
            keyByIndex.put(i, key);
            Integer best = winnerIndexByKey.get(key);
            // Estrictamente mayor: en empate de occurredAt gana la primera vista y la otra queda Late.
            if (best == null || events[i].Occurred_At__c > events[best].Occurred_At__c) {
                winnerIndexByKey.put(key, i);
            }
        }
        if (keyByIndex.isEmpty()) {
            return;
        }

        // 2. Lectura actual guardada para esas llaves (una sola consulta).
        Map<String, Datetime> currentByKey = new Map<String, Datetime>();
        for (Asset_Condition__c condition : [
            SELECT Asset_Measurement_Key__c, Occurred_At__c
            FROM Asset_Condition__c
            WHERE Asset_Measurement_Key__c IN :winnerIndexByKey.keySet()
            WITH SYSTEM_MODE
        ]) {
            currentByKey.put(condition.Asset_Measurement_Key__c, condition.Occurred_At__c);
        }

        // 3. La ganadora que además es estrictamente más nueva que lo guardado actualiza el estado;
        //    las demás (perdedoras del lote o no más nuevas que la actual) quedan Late.
        Map<String, Asset_Condition__c> toUpsertByKey = new Map<String, Asset_Condition__c>();
        for (Integer i : keyByIndex.keySet()) {
            String key = keyByIndex.get(i);
            Datetime current = currentByKey.get(key);
            Boolean isWinner = winnerIndexByKey.get(key) == i;
            Boolean isNewer = current == null || events[i].Occurred_At__c > current;
            if (isWinner && isNewer) {
                toUpsertByKey.put(key, buildCondition(key, outcomes[i].assetId, events[i]));
            } else {
                outcomes.set(
                    i,
                    TelemetrySignalOutcome.late(outcomes[i].assetId, outcomes[i].locationId, lateDetail(current))
                );
            }
        }

        // 4. Un solo upsert parcial por la llave única.
        saveConditions(toUpsertByKey.values());
    }

    private static String conditionKey(Id assetId, Telemetry_Signal__e evt) {
        return assetId + ':' + measurementType(evt);
    }

    /** Para una medición, el tipo que trae la señal (normalizado); para conectividad, una constante. */
    private static String measurementType(Telemetry_Signal__e evt) {
        if (TelemetrySignalValidator.TYPE_CONNECTIVITY.equalsIgnoreCase(evt.Message_Type__c)) {
            return CONNECTIVITY_TYPE;
        }
        return evt.Measurement_Type__c == null ? null : evt.Measurement_Type__c.trim().toUpperCase();
    }

    private static Asset_Condition__c buildCondition(String key, Id assetId, Telemetry_Signal__e evt) {
        String type = measurementType(evt);
        Asset_Condition__c condition = new Asset_Condition__c(
            Asset_Measurement_Key__c = key,
            Name = key.abbreviate(NAME_MAX),
            Asset__c = assetId,
            Measurement_Type__c = type,
            Occurred_At__c = evt.Occurred_At__c,
            Sensor_Id__c = evt.Sensor_Id__c
        );
        if (CONNECTIVITY_TYPE == type) {
            // La fila de conectividad guarda el estado del dispositivo, sin valor ni unidad.
            condition.Communication_Status__c = evt.Communication_Status__c;
            condition.Severity__c = SeverityClassifier.classifyConnectivity(evt.Communication_Status__c);
        } else {
            condition.Measurement_Value__c = evt.Measurement_Value__c;
            condition.Measurement_Unit__c = evt.Measurement_Unit__c;
            // El tipo de equipo lo cableará BR-206 cuando la clasificación lea los umbrales.
            condition.Severity__c = SeverityClassifier.classifyMeasurement(null, type, evt.Measurement_Value__c);
        }
        return condition;
    }

    private static String lateDetail(Datetime current) {
        if (current == null) {
            return 'Otra señal más reciente del mismo activo llegó en este lote; esta no reemplaza el estado.';
        }
        return 'La lectura actual (' + current.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + ') es igual o más nueva; esta no reemplaza el estado.';
    }

    /**
     * Guardado parcial: si una condición falla, las demás se guardan igual. No se relanza el
     * lote, igual que en el suscriptor. El upsert usa la llave única activo+tipo (nunca
     * consultar y luego insertar), así que varias señales del mismo activo son seguras.
     */
    private static void saveConditions(List<Asset_Condition__c> conditions) {
        if (conditions.isEmpty()) {
            return;
        }
        List<Database.UpsertResult> results = Database.upsert(
            conditions,
            Asset_Condition__c.Asset_Measurement_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'No se pudo guardar la condición ' + conditions[i].Asset_Measurement_Key__c + ': ' +
                    TelemetryPublisher.describe(results[i].getErrors())
                );
            }
        }
    }
}
