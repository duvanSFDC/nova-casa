@IsTest
private class SignalLogInvestigationTest {
    @IsTest
    static void summarizesEachBusinessResult() {
        System.assertEquals('Procesada', statusOf('Processed', 'Accepted', null));
        System.assertEquals('Rechazada', statusOf('Processed', 'Rejected', 'UNKNOWN_ASSET'));
        System.assertEquals('Duplicada', statusOf('Processed', 'Duplicate', null));
        System.assertEquals('Atrasada', statusOf('Processed', 'Late', null));
    }

    @IsTest
    static void separatesTechnicalFailuresFromRejections() {
        System.assertEquals('Fallida: no se publicó', statusOf('Publish_Failed', null, null));
        System.assertEquals(
            'Fallida: no se creó la intervención',
            statusOf('Processed', 'Rejected', 'INTERVENTION_FAILED')
        );
    }

    @IsTest
    static void showsSignalsStillWaitingForTheSubscriber() {
        System.assertEquals('Pendiente', statusOf('Published', null, null));
    }

    @IsTest
    static void labelsLogsFromBeforeResultsExisted() {
        System.assertEquals('Procesada sin resultado (anterior a US-202)', statusOf('Processed', null, null));
    }

    @IsTest
    static void everyRejectionReasonSaysWhatToFix() {
        for (Schema.PicklistEntry entry : Signal_Log__c.Reason__c.getDescribe().getPicklistValues()) {
            String guidance = guidanceOf('Processed', 'Rejected', entry.getValue());
            System.assert(
                !guidance.startsWith('Nada que hacer'),
                entry.getValue() + ' needs its own guidance, got: ' + guidance
            );
        }
    }

    @IsTest
    static void guidanceAgreesWithRetrySafe() {
        Map<String, Boolean> retrySafeByReason = new Map<String, Boolean>{
            'UNKNOWN_BUILDING' => true,
            'UNKNOWN_ASSET' => true,
            'ASSET_NOT_IN_BUILDING' => true,
            'UNSUPPORTED_MEASUREMENT' => true,
            'THRESHOLD_MISSING' => true,
            'THRESHOLD_INCOMPLETE' => true,
            'THRESHOLD_CONTRADICTORY' => true,
            'INTERVENTION_FAILED' => true,
            'INCOMPLETE' => false,
            'INCOMPATIBLE_UNIT' => false,
            'UNKNOWN_MESSAGE_TYPE' => false,
            'IDENTITY_CONFLICT' => false
        };
        for (String reason : retrySafeByReason.keySet()) {
            String guidance = guidanceOf('Processed', 'Rejected', reason);
            System.assertEquals(
                !retrySafeByReason.get(reason),
                guidance.startsWith('No reintentar'),
                reason + ': ' + guidance
            );
        }
    }

    @IsTest
    static void signalsWithoutAProblemNeedNothing() {
        System.assertEquals('Nada que hacer.', guidanceOf('Processed', 'Accepted', null));
        System.assertEquals('Nada que hacer: el mensaje original ya se procesó.', guidanceOf('Processed', 'Duplicate', null));
        System.assertEquals('Nada que hacer: ya hay una lectura más reciente.', guidanceOf('Processed', 'Late', null));
    }

    @IsTest
    static void technicalStagesHaveTheirOwnGuidance() {
        System.assert(guidanceOf('Publish_Failed', null, null).startsWith('Seguro reintentar a mano'));
        System.assert(guidanceOf('Published', null, null).startsWith('Esperar'));
    }

    private static String statusOf(String status, String result, String reason) {
        return calculate(status, result, reason).Investigation_Status__c;
    }

    private static String guidanceOf(String status, String result, String reason) {
        return calculate(status, result, reason).Retry_Guidance__c;
    }

    private static Signal_Log__c calculate(String status, String result, String reason) {
        Signal_Log__c log = new Signal_Log__c(Status__c = status, Result__c = result, Reason__c = reason);
        Formula.recalculateFormulas(new List<Signal_Log__c>{ log });
        return log;
    }
}
