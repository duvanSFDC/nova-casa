/**
 * Una corrida de ingesta: abre sesión solo si no hay cursor vigente, pide un lote,
 * publica los eventos y guarda el nextCursor para la corrida siguiente.
 * Los callouts van antes de cualquier DML.
 * Estado y logs son plomería de integración: se leen y escriben en modo sistema.
 * La seguridad por usuario (BR-208) se aplica en lo que consultan Laura, Javier y Camila.
 */
public inherited sharing class TelemetryIngestionService {
    public static final String STATE_NAME = 'default';
    public static final Integer DEFAULT_BATCH_SIZE = 20;
    public static final Integer MAX_BATCH_SIZE = 200;

    private final NovaSimulatorClient client;

    public TelemetryIngestionService() {
        this(new NovaSimulatorClient());
    }

    @TestVisible
    private TelemetryIngestionService(NovaSimulatorClient client) {
        this.client = client;
    }

    public class Result {
        public Boolean sessionStarted = false;
        public Integer received = 0;
        public Integer published = 0;
        public Integer publishFailed = 0;
        public Boolean hasMore = false;
        public Integer pollAfterMs;
    }

    public Result run(Integer batchSize) {
        Integer size = (batchSize == null || batchSize <= 0) ? DEFAULT_BATCH_SIZE : Math.min(batchSize, MAX_BATCH_SIZE);
        Ingestion_State__c state = loadState();
        Result result = new Result();

        if (needsNewSession(state)) {
            NovaSimulatorClient.Session session = client.startSession();
            state.Cursor__c = session.cursor;
            state.Session_Started_At__c = session.startedAt;
            state.Session_Expires_At__c = session.expiresAt;
            result.sessionStarted = true;
        }

        NovaSimulatorClient.TelemetryPage page = client.fetchTelemetry(state.Cursor__c, size);

        List<Telemetry_Signal__e> events = new List<Telemetry_Signal__e>();
        for (Map<String, Object> item : page.items) {
            events.add(TelemetrySignalMapper.toEvent(item));
        }
        TelemetryPublisher.Outcome outcome = TelemetryPublisher.publish(events);

        if (String.isNotBlank(page.nextCursor)) {
            state.Cursor__c = page.nextCursor;
        }
        state.Has_More__c = page.hasMore;
        state.Poll_After_Ms__c = page.pollAfterMs;
        state.Last_Run_At__c = Datetime.now();
        state.Last_Batch_Count__c = events.size();
        Database.upsert(state, true, AccessLevel.SYSTEM_MODE);

        result.received = events.size();
        result.published = outcome.published;
        result.publishFailed = outcome.failed;
        result.hasMore = page.hasMore;
        result.pollAfterMs = page.pollAfterMs;
        return result;
    }

    private static Boolean needsNewSession(Ingestion_State__c state) {
        return String.isBlank(state.Cursor__c) ||
            (state.Session_Expires_At__c != null && state.Session_Expires_At__c <= Datetime.now());
    }

    private static Ingestion_State__c loadState() {
        List<Ingestion_State__c> rows = [
            SELECT Id, Name, Cursor__c, Session_Started_At__c, Session_Expires_At__c
            FROM Ingestion_State__c
            WHERE Name = :STATE_NAME
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return rows.isEmpty() ? new Ingestion_State__c(Name = STATE_NAME) : rows[0];
    }
}
