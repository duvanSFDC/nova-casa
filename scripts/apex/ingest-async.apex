// Ingesta en segundo plano: hasta 5 lotes de 20, uno por minuto mientras el simulador diga hasMore.
// sf apex run --file scripts/apex/ingest-async.apex
System.debug(LoggingLevel.ERROR, '>>> JOB ' + System.enqueueJob(new TelemetryIngestionJob(20, 5)));
