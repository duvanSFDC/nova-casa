// Corre un escenario del simulador para reproducir evidencia determinista.
// Edita SCENARIO (y, si quieres, SEED/BATCH) y ejecuta:
//   sf apex run --file scripts/apex/ingest-scenario.apex --target-org novacasa
// Escenarios: MIXED, QA_200, BOUNDARIES, CRITICAL_BURST, LATE_MESSAGES,
//             DUPLICATES, CONFLICT, INVALID_DATA, CAMERA_OUTAGE.
// Usa un cursor aparte ('scenario'), así no toca la ingesta normal.
String SCENARIO = 'CRITICAL_BURST';
Long SEED = 20260922L;
Integer BATCH = 200;

TelemetryIngestionService.Result result = new TelemetryIngestionService().runScenario(SCENARIO, SEED, BATCH);
System.debug(LoggingLevel.ERROR, '>>> ESCENARIO ' + SCENARIO + ' ' + JSON.serialize(result));
