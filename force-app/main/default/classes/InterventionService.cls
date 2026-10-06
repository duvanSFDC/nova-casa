/**
 * BR-205: crea una sola intervención (Work Order) por mensaje crítico vigente.
 * Recibe las señales que ya quedaron Accepted con severidad Critical (las atrasadas y los
 * reenvíos ya se apartaron antes) y abre una intervención por cada messageId, usando
 * WorkOrder.Message_Key__c como llave única.
 *
 * Garantía frente a duplicados y concurrencia: la unicidad de Message_Key__c es el candado.
 * Si un messageId ya tiene intervención (reenvío que llegó hasta aquí, o una transacción
 * concurrente que la creó primero), se reutiliza y se enlaza, nunca se crea una segunda.
 * Límite: la consolidación de varias claves distintas del mismo activo en un solo incidente
 * no es parte del alcance base (es un extra, según los acuerdos de Discovery).
 *
 * Recuperación segura: si la creación falla, la señal no queda Accepted sin su intervención;
 * su log pasa a Rechazada con motivo INTERVENTION_FAILED y Retry_Safe = true.
 *
 * Corre como Automated Process (modo sistema). Apex nunca cierra ni avanza el Work Order:
 * eso lo hace Javier.
 */
public inherited sharing class InterventionService {
    private static final String STATUS_NEW = 'New';
    private static final String PRIORITY_CRITICAL = 'Critical';
    private static final Integer SUBJECT_MAX = 255;

    // Deja a las pruebas forzar una falla de creación (no duplicada) para validar la recuperación segura.
    @TestVisible
    private static Boolean failInsertsForTest = false;

    /**
     * Abre o reutiliza la intervención de cada crítica aceptada del lote y enlaza su log.
     * Modifica la lista outcomes: pone el Work Order en las que lo logran y marca las que fallan.
     */
    public static void ensureInterventions(List<Telemetry_Signal__e> events, List<TelemetrySignalOutcome> outcomes) {
        // 1. Críticas aceptadas, una por messageId.
        Map<String, Integer> indexByMessageId = new Map<String, Integer>();
        for (Integer i = 0; i < outcomes.size(); i++) {
            TelemetrySignalOutcome outcome = outcomes[i];
            if (outcome.result == TelemetrySignalOutcome.RESULT_ACCEPTED &&
                MeasurementSeverityClassifier.SEVERITY_CRITICAL.equals(outcome.severity) &&
                String.isNotBlank(events[i].Message_Id__c)) {
                indexByMessageId.put(events[i].Message_Id__c, i);
            }
        }
        if (indexByMessageId.isEmpty()) {
            return;
        }

        // 2. Intervenciones que ya existen para esas identidades (reenvío o carrera previa).
        Map<String, Id> workOrderIdByKey = existingWorkOrders(indexByMessageId.keySet());

        // 3. Reutilizar las que existen; preparar la creación de las nuevas.
        List<Integer> insertPositions = new List<Integer>();
        List<String> insertMessageIds = new List<String>();
        Set<Id> newAssetIds = new Set<Id>();
        for (String messageId : indexByMessageId.keySet()) {
            Integer i = indexByMessageId.get(messageId);
            if (workOrderIdByKey.containsKey(messageId)) {
                outcomes[i].withWorkOrder(workOrderIdByKey.get(messageId));
            } else {
                insertPositions.add(i);
                insertMessageIds.add(messageId);
                if (outcomes[i].assetId != null) {
                    newAssetIds.add(outcomes[i].assetId);
                }
            }
        }

        // El nombre del equipo hace legible la causa (no el código del simulador).
        Map<Id, String> assetNameById = assetNames(newAssetIds);
        List<WorkOrder> toInsert = new List<WorkOrder>();
        for (Integer k = 0; k < insertPositions.size(); k++) {
            Integer i = insertPositions[k];
            toInsert.add(buildWorkOrder(insertMessageIds[k], outcomes[i], events[i], assetNameById));
        }

        createInterventions(toInsert, insertPositions, events, outcomes);
        linkBatchDuplicates(indexByMessageId, events, outcomes);
    }

    /** Enlaza los reenvíos del mismo lote (Duplicate sin Work Order) a la intervención recién creada. */
    private static void linkBatchDuplicates(
        Map<String, Integer> indexByMessageId,
        List<Telemetry_Signal__e> events,
        List<TelemetrySignalOutcome> outcomes
    ) {
        Map<String, Id> workOrderByMessageId = new Map<String, Id>();
        for (String messageId : indexByMessageId.keySet()) {
            Id workOrderId = outcomes[indexByMessageId.get(messageId)].workOrderId;
            if (workOrderId != null) {
                workOrderByMessageId.put(messageId, workOrderId);
            }
        }
        if (workOrderByMessageId.isEmpty()) {
            return;
        }
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].result == TelemetrySignalOutcome.RESULT_DUPLICATE &&
                outcomes[i].workOrderId == null &&
                workOrderByMessageId.containsKey(events[i].Message_Id__c)) {
                outcomes[i].withWorkOrder(workOrderByMessageId.get(events[i].Message_Id__c));
            }
        }
    }

    private static Map<String, Id> existingWorkOrders(Set<String> messageIds) {
        Map<String, Id> byKey = new Map<String, Id>();
        for (WorkOrder order : [
            SELECT Id, Message_Key__c
            FROM WorkOrder
            WHERE Message_Key__c IN :messageIds
            WITH SYSTEM_MODE
        ]) {
            byKey.put(order.Message_Key__c, order.Id);
        }
        return byKey;
    }

    private static WorkOrder buildWorkOrder(
        String messageId,
        TelemetrySignalOutcome outcome,
        Telemetry_Signal__e evt,
        Map<Id, String> assetNameById
    ) {
        return new WorkOrder(
            Message_Key__c = messageId,
            AssetId = outcome.assetId,
            LocationId = outcome.locationId,
            Status = STATUS_NEW,
            Priority = PRIORITY_CRITICAL,
            Subject = cause(evt, assetNameById.get(outcome.assetId))
        );
    }

    /** Nombres de los equipos que abrirán intervención, en una sola consulta. */
    private static Map<Id, String> assetNames(Set<Id> assetIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (assetIds.isEmpty()) {
            return names;
        }
        for (Asset equipment : [SELECT Id, Name FROM Asset WHERE Id IN :assetIds WITH SYSTEM_MODE]) {
            names.put(equipment.Id, equipment.Name);
        }
        return names;
    }

    /**
     * Causa legible para la persona: "Crítico · Temperatura 35 °C · Ventilación".
     * Usa los nombres amigables de MeasurementLabels y el nombre del equipo; si no hay
     * nombre a mano, cae al código del simulador.
     */
    private static String cause(Telemetry_Signal__e evt, String assetName) {
        String measurement = capitalize(MeasurementLabels.typeLabel(evt.Measurement_Type__c));
        String unit = MeasurementLabels.unitLabel(evt.Measurement_Unit__c);
        String reading = measurement + ' ' + formatValue(evt.Measurement_Value__c);
        if (String.isNotBlank(unit)) {
            reading += ' ' + unit;
        }
        String equipment = String.isNotBlank(assetName) ? assetName : evt.Asset_Id__c;
        return ('Crítico · ' + reading + ' · ' + equipment).abbreviate(SUBJECT_MAX);
    }

    /** El valor sin ceros de relleno: 35.0000 -> 35, 0.8000 -> 0.8. */
    private static String formatValue(Object raw) {
        if (raw == null) {
            return '';
        }
        return Decimal.valueOf(String.valueOf(raw)).stripTrailingZeros().toPlainString();
    }

    private static String capitalize(String text) {
        return String.isBlank(text) ? text : text.substring(0, 1).toUpperCase() + text.substring(1);
    }

    /**
     * Inserta las intervenciones nuevas con guardado parcial. Un DUPLICATE_VALUE significa que
     * otra transacción concurrente ya la creó: se vuelve a consultar y se enlaza (reutilizar, no
     * fallar). Cualquier otro error deja la señal en INTERVENTION_FAILED para reintentar seguro.
     */
    private static void createInterventions(
        List<WorkOrder> toInsert,
        List<Integer> insertPositions,
        List<Telemetry_Signal__e> events,
        List<TelemetrySignalOutcome> outcomes
    ) {
        if (toInsert.isEmpty()) {
            return;
        }
        if (failInsertsForTest) {
            // Fuerza STRING_TOO_LONG (Message_Key__c es de 80): una falla real, no duplicada.
            for (WorkOrder order : toInsert) {
                order.Message_Key__c = order.Message_Key__c.rightPad(300, 'X');
            }
        }
        List<Database.SaveResult> results = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);

        Map<String, Integer> raceByMessageId = new Map<String, Integer>();
        for (Integer r = 0; r < results.size(); r++) {
            Integer i = insertPositions[r];
            if (results[r].isSuccess()) {
                outcomes[i].withWorkOrder(results[r].getId());
            } else if (isDuplicate(results[r])) {
                raceByMessageId.put(events[i].Message_Id__c, i);
            } else {
                outcomes.set(
                    i,
                    TelemetrySignalOutcome.rejected(
                            TelemetrySignalOutcome.REASON_INTERVENTION_FAILED,
                            'No se pudo crear la intervención: ' + TelemetryPublisher.describe(results[r].getErrors()),
                            true
                        )
                        .withReferences(outcomes[i].assetId, outcomes[i].locationId)
                        .withSeverity(outcomes[i].severity)
                );
            }
        }

        // Carrera concurrente: la intervención ya existe, se reutiliza.
        if (!raceByMessageId.isEmpty()) {
            Map<String, Id> created = existingWorkOrders(raceByMessageId.keySet());
            for (String messageId : raceByMessageId.keySet()) {
                Integer i = raceByMessageId.get(messageId);
                if (created.containsKey(messageId)) {
                    outcomes[i].withWorkOrder(created.get(messageId));
                } else {
                    outcomes.set(
                        i,
                        TelemetrySignalOutcome.rejected(
                                TelemetrySignalOutcome.REASON_INTERVENTION_FAILED,
                                'No se pudo crear ni reutilizar la intervención del mensaje ' + messageId + '.',
                                true
                            )
                            .withReferences(outcomes[i].assetId, outcomes[i].locationId)
                            .withSeverity(outcomes[i].severity)
                    );
                }
            }
        }
    }

    private static Boolean isDuplicate(Database.SaveResult result) {
        for (Database.Error error : result.getErrors()) {
            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}
