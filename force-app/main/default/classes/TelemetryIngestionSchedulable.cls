/**
 * Dispara la ingesta de forma automática por horario (Cron). Un Schedulable no puede hacer
 * callouts directamente, así que encola el Queueable TelemetryIngestionJob, que sí los hace.
 * Programar con System.schedule (ver scripts/apex/schedule-ingest.apex).
 */
public inherited sharing class TelemetryIngestionSchedulable implements Schedulable {
    private final Integer batchSize;
    private final Integer runs;

    public TelemetryIngestionSchedulable() {
        this(TelemetryIngestionService.MAX_BATCH_SIZE, 1);
    }

    public TelemetryIngestionSchedulable(Integer batchSize, Integer runs) {
        this.batchSize = batchSize;
        this.runs = runs;
    }

    public void execute(SchedulableContext context) {
        System.enqueueJob(new TelemetryIngestionJob(batchSize, runs));
    }
}
