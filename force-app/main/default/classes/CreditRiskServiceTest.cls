@isTest
private class CreditRiskServiceTest {
    private class YesMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{"answer":"yes","forced":false,"image":"https://yesno.wtf/assets/yes/1.gif"}'
            );
            return res;
        }
    }

    private class NoMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{"answer":"no","forced":false,"image":"https://yesno.wtf/assets/no/1.gif"}'
            );
            return res;
        }
    }

    private class MaybeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{"answer":"maybe","forced":false,"image":"https://yesno.wtf/assets/maybe/1.gif"}'
            );
            return res;
        }
    }

    private class ServerErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('Internal Server Error');
            return res;
        }
    }

    @TestSetup
    static void makeData() {
        insert new Contact(FirstName = 'Test', LastName = 'RiskContact');
    }

    private static Contact getContact() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    @isTest
    static void checkCreditRisk_returnsHighRisk_whenApiAnswersYes() {
        Test.setMock(HttpCalloutMock.class, new YesMock());
        Contact c = getContact();

        Test.startTest();
        CreditRiskService.CreditRiskResult result = CreditRiskService.checkCreditRisk(
            c.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected success = true');
        Assert.areEqual('High', result.riskLevel, 'Expected High risk level');
        Assert.areEqual('yes', result.answer, 'Expected answer = yes');
        Assert.isNotNull(result.logId, 'Expected a log record Id');

        Credit_Risk_Log__c log = [
            SELECT Risk_Level__c, Callout_Success__c, API_Answer__c
            FROM Credit_Risk_Log__c
            WHERE Id = :result.logId
        ];
        Assert.areEqual('High', log.Risk_Level__c, 'Log Risk_Level__c should be High');
        Assert.isTrue(log.Callout_Success__c, 'Log Callout_Success__c should be true');
        Assert.areEqual('yes', log.API_Answer__c, 'Log API_Answer__c should be yes');
    }

    @isTest
    static void checkCreditRisk_returnsLowRisk_whenApiAnswersNo() {
        Test.setMock(HttpCalloutMock.class, new NoMock());
        Contact c = getContact();

        Test.startTest();
        CreditRiskService.CreditRiskResult result = CreditRiskService.checkCreditRisk(
            c.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected success = true');
        Assert.areEqual('Low', result.riskLevel, 'Expected Low risk level');
        Assert.areEqual('no', result.answer, 'Expected answer = no');
    }

    @isTest
    static void checkCreditRisk_returnsUnknownRisk_whenApiAnswersMaybe() {
        Test.setMock(HttpCalloutMock.class, new MaybeMock());
        Contact c = getContact();

        Test.startTest();
        CreditRiskService.CreditRiskResult result = CreditRiskService.checkCreditRisk(
            c.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Expected success = true (callout itself worked)');
        Assert.areEqual('Unknown', result.riskLevel, 'Expected Unknown risk level for maybe');
    }

    @isTest
    static void checkCreditRisk_recordsFailedLog_whenApiReturns500() {
        Test.setMock(HttpCalloutMock.class, new ServerErrorMock());
        Contact c = getContact();

        Test.startTest();
        CreditRiskService.CreditRiskResult result = CreditRiskService.checkCreditRisk(
            c.Id
        );
        Test.stopTest();

        Assert.isFalse(result.success, 'Expected success = false on API error');
        Assert.isNotNull(result.errorMessage, 'Expected an error message');
        Assert.isNotNull(result.logId, 'Expected a log record even on failure');

        Credit_Risk_Log__c log = [
            SELECT Callout_Success__c, HTTP_Status_Code__c, Error_Message__c
            FROM Credit_Risk_Log__c
            WHERE Id = :result.logId
        ];
        Assert.isFalse(log.Callout_Success__c, 'Log should record callout failure');
        Assert.areEqual(
            500,
            (Integer) log.HTTP_Status_Code__c,
            'Log should capture HTTP 500 status'
        );
        Assert.isTrue(
            log.Error_Message__c.contains('500'),
            'Error message should reference the status code'
        );
    }

    @isTest
    static void getCreditRiskLogs_returnsLogsForContact_orderedByTimestampDesc() {
        Contact c = getContact();
        DateTime earlier = DateTime.now().addMinutes(-5);
        DateTime later = DateTime.now();

        insert new List<Credit_Risk_Log__c>{
            new Credit_Risk_Log__c(
                Contact__c = c.Id,
                Risk_Level__c = 'Low',
                API_Answer__c = 'no',
                Callout_Success__c = true,
                Callout_Timestamp__c = earlier
            ),
            new Credit_Risk_Log__c(
                Contact__c = c.Id,
                Risk_Level__c = 'High',
                API_Answer__c = 'yes',
                Callout_Success__c = true,
                Callout_Timestamp__c = later
            )
        };

        Test.startTest();
        List<Credit_Risk_Log__c> logs = CreditRiskService.getCreditRiskLogs(c.Id);
        Test.stopTest();

        Assert.areEqual(2, logs.size(), 'Should return 2 logs');
        Assert.areEqual(
            'High',
            logs[0].Risk_Level__c,
            'Most recent log (High) should be first'
        );
        Assert.areEqual(
            'Low',
            logs[1].Risk_Level__c,
            'Older log (Low) should be second'
        );
    }

    @isTest
    static void getCreditRiskLogs_returnsEmptyList_forContactWithNoLogs() {
        Contact c = getContact();

        Test.startTest();
        List<Credit_Risk_Log__c> logs = CreditRiskService.getCreditRiskLogs(c.Id);
        Test.stopTest();

        Assert.areEqual(0, logs.size(), 'Should return empty list');
    }
}
