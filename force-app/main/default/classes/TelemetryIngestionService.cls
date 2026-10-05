/**
 * Una corrida de ingesta: abre sesión solo si no hay cursor vigente, pide un lote,
 * publica los eventos y guarda el nextCursor para la corrida siguiente.
 * Los callouts van antes de cualquier DML.
 * Estado y logs son plomería de integración: se leen y escriben en modo sistema.
 * La seguridad por usuario (BR-208) se aplica en lo que consultan Laura, Javier y Camila.
 */
public inherited sharing class TelemetryIngestionService {
    public static final String STATE_NAME = 'default';
    // La ingesta de escenarios usa su propio cursor, para no tocar el de la ingesta normal.
    public static final String SCENARIO_STATE_NAME = 'scenario';
    public static final Integer DEFAULT_BATCH_SIZE = 20;
    public static final Integer MAX_BATCH_SIZE = 200;
    // Los dos edificios reales de Nova Casa; el escenario los pide en el cuerpo de /session.
    public static final List<String> SIMULATOR_BUILDINGS = new List<String>{ 'BLD-BOG-001', 'BLD-BAQ-001' };
    // Escenarios que ofrece el simulador (ver la Ayuda del simulador de Emiliano).
    public static final Set<String> SCENARIOS = new Set<String>{
        'MIXED', 'QA_200', 'BOUNDARIES', 'CRITICAL_BURST', 'LATE_MESSAGES',
        'DUPLICATES', 'CONFLICT', 'INVALID_DATA', 'CAMERA_OUTAGE'
    };

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
        Ingestion_State__c state = loadState(STATE_NAME);
        Boolean sessionStarted = false;
        if (needsNewSession(state)) {
            applySession(state, client.startSession());
            sessionStarted = true;
        }
        return ingest(state, clampSize(batchSize), sessionStarted);
    }

    /**
     * Corre un escenario del simulador para reproducir evidencia determinista (p. ej.
     * CRITICAL_BURST para intervenciones, DUPLICATES para la dedup, LATE_MESSAGES para la
     * recencia). Abre siempre una sesión nueva con el escenario y la semilla, en un cursor
     * aparte ('scenario') para no interferir con la ingesta normal. Luego publica por el bus
     * y el suscriptor procesa igual que siempre.
     */
    public Result runScenario(String scenario, Long seed, Integer batchSize) {
        String normalized = scenario == null ? null : scenario.trim().toUpperCase();
        if (String.isBlank(normalized) || !SCENARIOS.contains(normalized)) {
            throw new NovaSimulatorClient.SimulatorException(
                'Escenario no reconocido: "' + scenario + '". Válidos: ' + String.join(new List<String>(SCENARIOS), ', ') + '.'
            );
        }
        Integer size = clampSize(batchSize);
        Ingestion_State__c state = loadState(SCENARIO_STATE_NAME);
        applySession(state, client.startSession(normalized, seed, SIMULATOR_BUILDINGS, size));
        return ingest(state, size, true);
    }

    private static Integer clampSize(Integer batchSize) {
        return (batchSize == null || batchSize <= 0) ? DEFAULT_BATCH_SIZE : Math.min(batchSize, MAX_BATCH_SIZE);
    }

    private void applySession(Ingestion_State__c state, NovaSimulatorClient.Session session) {
        state.Cursor__c = session.cursor;
        state.Session_Started_At__c = session.startedAt;
        state.Session_Expires_At__c = session.expiresAt;
    }

    /** Pide un lote con el cursor del estado, publica los eventos y guarda el nextCursor. */
    private Result ingest(Ingestion_State__c state, Integer size, Boolean sessionStarted) {
        Result result = new Result();
        result.sessionStarted = sessionStarted;

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

    private static Ingestion_State__c loadState(String name) {
        List<Ingestion_State__c> rows = [
            SELECT Id, Name, Cursor__c, Session_Started_At__c, Session_Expires_At__c
            FROM Ingestion_State__c
            WHERE Name = :name
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return rows.isEmpty() ? new Ingestion_State__c(Name = name) : rows[0];
    }
}
