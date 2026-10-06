/**
 * Publica las señales en el bus y deja un Signal_Log__c "Publicada" por cada una.
 * Telemetry_Signal__e es PublishAfterCommit: si el insert del log falla, tampoco sale el evento.
 */
public inherited sharing class TelemetryPublisher {
    public static final String STATUS_PUBLISHED = 'Published';
    public static final String STATUS_PROCESSED = 'Processed';
    public static final String STATUS_PUBLISH_FAILED = 'Publish_Failed';

    public class Outcome {
        public Integer published = 0;
        public Integer failed = 0;
        public List<Signal_Log__c> logs = new List<Signal_Log__c>();
    }

    public static Outcome publish(List<Telemetry_Signal__e> events) {
        Outcome outcome = new Outcome();
        if (events.isEmpty()) {
            return outcome;
        }

        List<Database.SaveResult> results = EventBus.publish(events);
        Datetime publishedAt = Datetime.now();

        for (Integer i = 0; i < events.size(); i++) {
            Telemetry_Signal__e evt = events[i];
            Database.SaveResult result = results[i];
            Signal_Log__c log = baseLog(evt);

            if (result.isSuccess()) {
                log.Status__c = STATUS_PUBLISHED;
                log.Published_At__c = publishedAt;
                log.Event_Uuid__c = evt.EventUuid;
                outcome.published++;
            } else {
                log = failedLog(evt, describe(result.getErrors()));
                outcome.failed++;
            }
            outcome.logs.add(log);
        }

        Database.insert(outcome.logs, true, AccessLevel.SYSTEM_MODE);
        return outcome;
    }

    /**
     * Log de una señal que no pudo publicarse. Volver a publicar es seguro (nada quedó en el bus),
     * así que se marca Retry_Safe__c para que quien investigue (BR-209) sepa que puede reintentar.
     */
    @TestVisible
    private static Signal_Log__c failedLog(Telemetry_Signal__e evt, String errorDetail) {
        Signal_Log__c log = baseLog(evt);
        log.Status__c = STATUS_PUBLISH_FAILED;
        log.Error__c = errorDetail;
        log.Retry_Safe__c = true;
        return log;
    }

    public static Signal_Log__c baseLog(Telemetry_Signal__e evt) {
        return new Signal_Log__c(
            Delivery_Id__c = evt.Delivery_Id__c,
            Message_Id__c = evt.Message_Id__c,
            Message_Type__c = evt.Message_Type__c,
            Building_Id__c = evt.Building_Id__c,
            Asset_Id__c = evt.Asset_Id__c,
            Occurred_At__c = evt.Occurred_At__c,
            Source_Published_At__c = evt.Source_Published_At__c
        );
    }

    public static String describe(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getStatusCode() + ': ' + error.getMessage());
        }
        return String.join(messages, ' | ').left(255);
    }
}
