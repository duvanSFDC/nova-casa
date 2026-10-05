// Programa la ingesta automática. CRON: segundos minutos horas día mes día_semana.
// Aquí: cada hora, en el minuto 0. Ajusta a tu gusto.
// sf apex run --file scripts/apex/schedule-ingest.apex --target-org novacasa
// Para detenerla: Setup > Scheduled Jobs > abortar, o System.abortJob('<id>').
String cron = '0 0 * * * ?';
System.schedule('Nova Casa · ingesta', cron, new TelemetryIngestionSchedulable());
System.debug(LoggingLevel.ERROR, '>>> Ingesta programada con CRON ' + cron);
