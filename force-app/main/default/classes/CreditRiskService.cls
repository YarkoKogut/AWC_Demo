
public with sharing class CreditRiskService {
    // ── Inner DTO ──────────────────────────────────────────────────────────

    /**
     * Structured result returned to the LWC. Always populated, even on failure,
     * so the UI can display a consistent response shape.
     */
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

    // ── AuraEnabled Methods ────────────────────────────────────────────────

    /**
     * Performs the credit risk callout for the given Contact.
     * Always inserts a Credit_Risk_Log__c record, even when the callout fails,
     * so every button click is fully auditable.
     *
     * @param contactId  The Contact record to assess.
     * @return           CreditRiskResult with outcome details and the new log Id.
     */
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

    /**
     * Returns up to 50 Credit_Risk_Log__c records for the given Contact,
     * ordered by most recent callout first.
     *
     * @param contactId  The Contact whose log history to retrieve.
     * @return           List of log records, newest first.
     */
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

    // ── Private Helpers ────────────────────────────────────────────────────

    /**
     * Builds a log record pre-populated with the contact and timestamp.
     * Defaults Callout_Success__c to false so a crash before DML still records failure.
     */
    private static Credit_Risk_Log__c initLog(Id contactId) {
        Credit_Risk_Log__c log = new Credit_Risk_Log__c();
        log.Contact__c = contactId;
        log.Callout_Timestamp__c = DateTime.now();
        log.Callout_Success__c = false;
        return log;
    }

    /**
     * Sends the HTTP GET request via the YesNoAPI Named Credential.
     * Timeout is 10 seconds — sufficient for a lightweight public API.
     */
    private static HttpResponse makeCallout() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:YesNoAPI/api');
        req.setMethod('GET');
        req.setTimeout(10000);
        return new Http().send(req);
    }

    /**
     * Routes the HTTP response to the appropriate handler based on status code.
     */
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

    /**
     * Parses the JSON body from a 200 response and maps the answer to a risk level.
     * Expected shape: { "answer": "yes|no|maybe", "forced": false, "image": "..." }
     */
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

    /**
     * Maps the API's plain-text answer to a structured risk level picklist value.
     */
    private static String resolveRiskLevel(String answer) {
        if ('yes'.equalsIgnoreCase(answer))
            return 'High';
        if ('no'.equalsIgnoreCase(answer))
            return 'Low';
        return 'Unknown';
    }

    /**
     * Captures any unhandled exception (network timeout, JSON parse error, etc.)
     * into the log and result so nothing is silently swallowed.
     */
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
