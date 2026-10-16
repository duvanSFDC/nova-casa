/**
 * BR-205: reconoce reenvíos y conflictos por identidad del mensaje (messageId), antes de que
 * el lote toque el estado o cree intervenciones. Así un mensaje repetido no vuelve a actualizar
 * la lectura actual ni genera otra intervención (acuerdo de Discovery).
 *
 * - Reenvío (mismo messageId, mismo contenido) de una señal ya aceptada: queda Duplicate y
 *   reutiliza el resultado existente (enlaza su Work Order si lo hubo).
 * - Misma identidad con contenido distinto: queda Rejected con IDENTITY_CONFLICT, no es un aviso nuevo.
 *
 * Reconoce duplicados dentro de la colección y entre entregas. Solo bloquea contra una señal
 * previa Accepted; si la anterior falló, un reenvío se procesa como nuevo (reintento seguro).
 * Corre como Automated Process (modo sistema). Una sola consulta por lote, sin SOQL por señal.
 */
public inherited sharing class SignalIdentityService {
    /**
     * Marca como Duplicate o conflicto las señales aceptadas cuya identidad ya se procesó.
     * Modifica la lista outcomes en las posiciones que cambian; el resto sigue igual.
     */
    public static void classifyDuplicates(List<Telemetry_Signal__e> events, List<TelemetrySignalOutcome> outcomes) {
        Set<String> messageIds = new Set<String>();
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].result == TelemetrySignalOutcome.RESULT_ACCEPTED && String.isNotBlank(events[i].Message_Id__c)) {
                messageIds.add(events[i].Message_Id__c);
            }
        }
        if (messageIds.isEmpty()) {
            return;
        }

        // Señal previa Accepted por identidad (entregas anteriores). La identidad es sesión + messageId:
        // el simulador reinicia la numeración de messageId en cada sesión, así que el mismo número en
        // otra sesión no es un conflicto. Sin sesión (p. ej. pruebas), la identidad es solo el messageId.
        Map<String, Signal_Log__c> priorByIdentity = new Map<String, Signal_Log__c>();
        for (Signal_Log__c log : [
            SELECT Session_Key__c, Message_Id__c, Building_Id__c, Asset_Id__c, Message_Type__c, Occurred_At__c, Work_Order__c
            FROM Signal_Log__c
            WHERE Message_Id__c IN :messageIds AND Result__c = :TelemetrySignalOutcome.RESULT_ACCEPTED
            WITH SYSTEM_MODE
        ]) {
            String identity = identityKey(log.Session_Key__c, log.Message_Id__c);
            if (!priorByIdentity.containsKey(identity)) {
                priorByIdentity.put(identity, log);
            }
        }

        Set<String> seenInBatch = new Set<String>();
        for (Integer i = 0; i < outcomes.size(); i++) {
            if (outcomes[i].result != TelemetrySignalOutcome.RESULT_ACCEPTED) {
                continue;
            }
            String identity = identityKey(events[i].Session_Key__c, events[i].Message_Id__c);
            Signal_Log__c prior = priorByIdentity.get(identity);
            if (prior != null) {
                outcomes.set(i, classifyAgainstPrior(events[i], outcomes[i], prior));
            } else if (seenInBatch.contains(identity)) {
                // Reenvío dentro del mismo lote: la primera queda Accepted; esta reutiliza el resultado.
                // El Work Order se enlaza después de crearlo (InterventionService).
                outcomes.set(
                    i,
                    TelemetrySignalOutcome.duplicate(
                        outcomes[i].assetId,
                        outcomes[i].locationId,
                        null,
                        'Reenvío dentro del lote del mensaje ' + events[i].Message_Id__c + '; reutiliza el resultado.'
                    )
                );
            } else {
                seenInBatch.add(identity);
            }
        }
    }

    /** Identidad de deduplicación: sesión + messageId. Sin sesión (pruebas), solo el messageId. */
    @TestVisible
    private static String identityKey(String sessionKey, String messageId) {
        return String.isBlank(sessionKey) ? messageId : sessionKey + '|' + messageId;
    }

    private static TelemetrySignalOutcome classifyAgainstPrior(
        Telemetry_Signal__e evt,
        TelemetrySignalOutcome current,
        Signal_Log__c prior
    ) {
        if (sameContent(evt, prior)) {
            return TelemetrySignalOutcome.duplicate(
                current.assetId,
                current.locationId,
                prior.Work_Order__c,
                'Reenvío del mensaje ' + evt.Message_Id__c + '; reutiliza el resultado ya procesado.'
            );
        }
        return TelemetrySignalOutcome.rejected(
                TelemetrySignalOutcome.REASON_IDENTITY_CONFLICT,
                'El mensaje ' + evt.Message_Id__c + ' ya se procesó con otro contenido; es un conflicto, no un aviso nuevo.',
                false
            )
            .withReferences(current.assetId, current.locationId)
            .withSeverity(current.severity);
    }

    /** Un reenvío legítimo repite edificio, equipo, tipo de mensaje y hora de origen. */
    private static Boolean sameContent(Telemetry_Signal__e evt, Signal_Log__c prior) {
        return equalCode(evt.Building_Id__c, prior.Building_Id__c) &&
            equalCode(evt.Asset_Id__c, prior.Asset_Id__c) &&
            equalCode(evt.Message_Type__c, prior.Message_Type__c) &&
            evt.Occurred_At__c == prior.Occurred_At__c;
    }

    private static Boolean equalCode(String a, String b) {
        String na = a == null ? '' : a.trim().toUpperCase();
        String nb = b == null ? '' : b.trim().toUpperCase();
        return na == nb;
    }
}
