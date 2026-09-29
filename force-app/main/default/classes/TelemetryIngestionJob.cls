/**
 * Ingesta asíncrona. Pide un lote y, si el simulador dice que hay más, se vuelve a encolar.
 * El simulador sugiere esperar 10 s (pollAfterMs); un Queueable no baja de 1 minuto de espera.
 */
public inherited sharing class TelemetryIngestionJob implements Queueable, Database.AllowsCallouts {
    private final Integer batchSize;
    private final Integer remainingRuns;

    public TelemetryIngestionJob(Integer batchSize, Integer remainingRuns) {
        this.batchSize = batchSize;
        this.remainingRuns = remainingRuns == null ? 1 : remainingRuns;
    }

    public void execute(QueueableContext context) {
        TelemetryIngestionService.Result result = new TelemetryIngestionService().run(batchSize);

        if (result.hasMore && remainingRuns > 1 && !Test.isRunningTest()) {
            System.enqueueJob(new TelemetryIngestionJob(batchSize, remainingRuns - 1), 1);
        }
    }
}
