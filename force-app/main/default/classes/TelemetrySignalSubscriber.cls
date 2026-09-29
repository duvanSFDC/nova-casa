/**
 * Suscriptor de Telemetry_Signal__e. En US-201 solo confirma que la señal llegó:
 * pasa el log de "Publicada" a "Procesada". Clasificar y actualizar Condition viene después.
 */
public inherited sharing class TelemetrySignalSubscriber {
    public static void handle(List<Telemetry_Signal__e> events) {
        Set<String> uuids = new Set<String>();
        for (Telemetry_Signal__e evt : events) {
            if (evt.EventUuid != null) {
                uuids.add(evt.EventUuid);
            }
        }

        Map<String, Signal_Log__c> logsByUuid = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [SELECT Id, Event_Uuid__c FROM Signal_Log__c WHERE Event_Uuid__c IN :uuids WITH SYSTEM_MODE]) {
            logsByUuid.put(log.Event_Uuid__c, log);
        }

        Datetime processedAt = Datetime.now();
        List<Signal_Log__c> toSave = new List<Signal_Log__c>();
        for (Telemetry_Signal__e evt : events) {
            Signal_Log__c log = logsByUuid.get(evt.EventUuid);
            if (log == null) {
                // Publicado fuera de TelemetryPublisher (p. ej. a mano): igual queda rastro.
                log = TelemetryPublisher.baseLog(evt);
                log.Event_Uuid__c = evt.EventUuid;
            }
            log.Status__c = TelemetryPublisher.STATUS_PROCESSED;
            log.Processed_At__c = processedAt;
            log.Replay_Id__c = evt.ReplayId;
            toSave.add(log);
        }

        // Corre como Automated Process: modo sistema explícito.
        Database.upsert(toSave, false, AccessLevel.SYSTEM_MODE);
    }
}
