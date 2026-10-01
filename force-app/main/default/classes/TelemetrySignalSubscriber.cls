/**
 * Suscriptor de Telemetry_Signal__e. Procesa el lote en una sola transacción:
 * Apex A (TelemetrySignalValidator) aparta las señales incompletas y Apex B
 * (TelemetrySignalProcessor) reconoce el edificio y el equipo de las demás.
 * Cada señal deja su log en "Procesada" con su resultado y motivo, así que una
 * señal inválida no detiene a las otras. Clasificar y actualizar Condition viene
 * después (BR-203 a BR-206).
 */
public inherited sharing class TelemetrySignalSubscriber {
    public static void handle(List<Telemetry_Signal__e> events) {
        List<TelemetrySignalOutcome> outcomes = evaluate(events);
        Map<String, Signal_Log__c> logsByUuid = existingLogs(events);

        Datetime processedAt = Datetime.now();
        List<Signal_Log__c> toSave = new List<Signal_Log__c>();
        for (Integer i = 0; i < events.size(); i++) {
            Telemetry_Signal__e evt = events[i];
            Signal_Log__c log = logsByUuid.get(evt.EventUuid);
            if (log == null) {
                // Publicado fuera de TelemetryPublisher (p. ej. a mano): igual queda rastro.
                log = TelemetryPublisher.baseLog(evt);
                log.Event_Uuid__c = evt.EventUuid;
            }
            log.Status__c = TelemetryPublisher.STATUS_PROCESSED;
            log.Processed_At__c = processedAt;
            log.Replay_Id__c = evt.ReplayId;
            outcomes[i].applyTo(log);
            toSave.add(log);
        }
        save(toSave);
    }

    /** Apex A sobre cada señal y Apex B, de una vez, sobre las que pasaron. Mismo orden que events. */
    private static List<TelemetrySignalOutcome> evaluate(List<Telemetry_Signal__e> events) {
        List<TelemetrySignalOutcome> outcomes = new List<TelemetrySignalOutcome>();
        List<Telemetry_Signal__e> complete = new List<Telemetry_Signal__e>();
        List<Integer> completePositions = new List<Integer>();
        for (Integer i = 0; i < events.size(); i++) {
            TelemetrySignalOutcome rejection = TelemetrySignalValidator.validate(events[i]);
            outcomes.add(rejection);
            if (rejection == null) {
                complete.add(events[i]);
                completePositions.add(i);
            }
        }

        List<TelemetrySignalOutcome> resolved = TelemetrySignalProcessor.process(complete);
        for (Integer j = 0; j < resolved.size(); j++) {
            outcomes[completePositions[j]] = resolved[j];
        }
        return outcomes;
    }

    private static Map<String, Signal_Log__c> existingLogs(List<Telemetry_Signal__e> events) {
        Set<String> uuids = new Set<String>();
        for (Telemetry_Signal__e evt : events) {
            if (evt.EventUuid != null) {
                uuids.add(evt.EventUuid);
            }
        }

        Map<String, Signal_Log__c> logsByUuid = new Map<String, Signal_Log__c>();
        // Message_Id__c y Delivery_Id__c se traen para el mensaje de error de save().
        for (Signal_Log__c log : [
            SELECT Id, Event_Uuid__c, Message_Id__c, Delivery_Id__c
            FROM Signal_Log__c
            WHERE Event_Uuid__c IN :uuids
            WITH SYSTEM_MODE
        ]) {
            logsByUuid.put(log.Event_Uuid__c, log);
        }
        return logsByUuid;
    }

    /**
     * Guardado parcial: si un log falla, los demás se guardan igual. No se relanza el lote
     * (EventBus.RetryableException) porque un error de datos se repetiría en cada reintento.
     */
    private static void save(List<Signal_Log__c> logs) {
        // Corre como Automated Process: modo sistema explícito.
        List<Database.UpsertResult> results = Database.upsert(logs, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(
                    LoggingLevel.ERROR,
                    'No se pudo guardar el log de ' + logs[i].Message_Id__c + ' (' + logs[i].Delivery_Id__c + '): ' +
                    TelemetryPublisher.describe(results[i].getErrors())
                );
            }
        }
    }
}
