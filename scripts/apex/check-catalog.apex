// Verifica la salud del simulador y muestra el catálogo: edificios, activos, sensores,
// escenarios y umbrales de referencia. Útil para contrastar los datos semilla y los límites.
// sf apex run --file scripts/apex/check-catalog.apex --target-org novacasa
NovaSimulatorClient client = new NovaSimulatorClient();
System.debug(LoggingLevel.ERROR, '>>> HEALTHY=' + client.isHealthy());
System.debug(LoggingLevel.ERROR, '>>> CATALOG=' + JSON.serialize(client.fetchCatalog()));
