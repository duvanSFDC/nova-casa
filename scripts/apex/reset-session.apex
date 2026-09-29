// Borra el cursor guardado. La próxima ingesta abrirá una sesión nueva (otro escenario del simulador).
// sf apex run --file scripts/apex/reset-session.apex
delete [SELECT Id FROM Ingestion_State__c];
