// Una corrida síncrona: pide un lote al simulador y publica los eventos.
// sf apex run --file scripts/apex/ingest-once.apex
TelemetryIngestionService.Result result = new TelemetryIngestionService().run(20);
System.debug(LoggingLevel.ERROR, '>>> INGESTA ' + JSON.serialize(result));
