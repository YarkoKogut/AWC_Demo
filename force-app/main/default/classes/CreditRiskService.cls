
public with sharing class CreditRiskService {
    public class CreditRiskResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String riskLevel;
        @AuraEnabled
        public String answer;
        @AuraEnabled
        public String imageUrl;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public Id logId;
    }

    @AuraEnabled
    public static CreditRiskResult checkCreditRisk(Id contactId) {
        CreditRiskResult result = new CreditRiskResult();
        Credit_Risk_Log__c log = initLog(contactId);

        try {
            HttpResponse res = makeCallout();
            processResponse(res, log, result);
        } catch (Exception ex) {
            handleException(ex, log, result);
        }

        insert log;
        result.logId = log.Id;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Credit_Risk_Log__c> getCreditRiskLogs(Id contactId) {
        return [
            SELECT
                Id,
                Risk_Level__c,
                API_Answer__c,
                HTTP_Status_Code__c,
                Callout_Success__c,
                Error_Message__c,
                Callout_Timestamp__c
            FROM Credit_Risk_Log__c
            WHERE Contact__c = :contactId
            ORDER BY Callout_Timestamp__c DESC
            LIMIT 50
        ];
    }

    private static Credit_Risk_Log__c initLog(Id contactId) {
        Credit_Risk_Log__c log = new Credit_Risk_Log__c();
        log.Contact__c = contactId;
        log.Callout_Timestamp__c = DateTime.now();
        log.Callout_Success__c = false;
        return log;
    }

    private static HttpResponse makeCallout() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:YesNoAPI/api');
        req.setMethod('GET');
        req.setTimeout(10000);
        return new Http().send(req);
    }

    private static void processResponse(
        HttpResponse res,
        Credit_Risk_Log__c log,
        CreditRiskResult result
    ) {
        log.HTTP_Status_Code__c = res.getStatusCode();
        log.API_Response__c = res.getBody();

        if (res.getStatusCode() == 200) {
            parseSuccessResponse(res.getBody(), log, result);
        } else {
            String msg =
                'HTTP ' + res.getStatusCode() + ' — ' + res.getStatus();
            log.Error_Message__c = msg;
            log.Risk_Level__c = 'Unknown';
            result.success = false;
            result.errorMessage = msg;
        }
    }

    private static void parseSuccessResponse(
        String body,
        Credit_Risk_Log__c log,
        CreditRiskResult result
    ) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
            body
        );
        String answer = (String) payload.get('answer');
        String imageUrl = (String) payload.get('image');

        log.API_Answer__c = answer;
        log.Image_URL__c = imageUrl;
        log.Callout_Success__c = true;
        log.Risk_Level__c = resolveRiskLevel(answer);

        result.success = true;
        result.riskLevel = log.Risk_Level__c;
        result.answer = answer;
        result.imageUrl = imageUrl;
    }

    private static String resolveRiskLevel(String answer) {
        if ('yes'.equalsIgnoreCase(answer))
            return 'High';
        if ('no'.equalsIgnoreCase(answer))
            return 'Low';
        return 'Unknown';
    }

    private static void handleException(
        Exception ex,
        Credit_Risk_Log__c log,
        CreditRiskResult result
    ) {
        String msg = ex.getMessage();
        log.Error_Message__c = msg;
        log.Risk_Level__c = 'Unknown';
        log.Callout_Success__c = false;

        result.success = false;
        result.errorMessage = msg;
    }
}
