/**
 * creditRisk
 * ─────────────────────────────────────────────────────────────────────────────
 * LWC component for the Contact record page that lets users trigger a credit
 * risk assessment via the YesNo API and browse the full history of past checks.
 *
 * UI logic   : state management, getters, event handlers (this file)
 * Service    : CreditRiskService Apex class handles callouts and DML
 */
import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import checkCreditRisk from '@salesforce/apex/CreditRiskService.checkCreditRisk';
import getCreditRiskLogs from '@salesforce/apex/CreditRiskService.getCreditRiskLogs';

const RISK_BADGE_CLASS = {
    High: 'risk-badge risk-badge-high',
    Low: 'risk-badge risk-badge-low',
    Unknown: 'risk-badge risk-badge-unknown'
};

const COLUMNS = [
    {
        label: 'Date / Time',
        fieldName: 'Callout_Timestamp__c',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { label: 'Risk Level',   fieldName: 'Risk_Level__c',       type: 'text' },
    { label: 'API Answer',   fieldName: 'API_Answer__c',        type: 'text' },
    { label: 'HTTP Status',  fieldName: 'HTTP_Status_Code__c',  type: 'number', cellAttributes: { alignment: 'left' } },
    {
        label: 'Status',
        fieldName: 'statusText',
        type: 'text',
        cellAttributes: {
            iconName: { fieldName: 'statusIconName' },
            iconAlternativeText: { fieldName: 'statusText' }
        }
    },
    { label: 'Error Details', fieldName: 'Error_Message__c',   type: 'text', wrapText: true }
];

export default class CreditRisk extends LightningElement {
    // ── Public API ─────────────────────────────────────────────────────────

    /** Injected by the record page; used as the contactId for all Apex calls. */
    @api recordId;

    // ── UI State ───────────────────────────────────────────────────────────

    isLoading = false;
    errorMessage = '';
    latestResult = null;
    columns = COLUMNS;

    // ── Wired Data ─────────────────────────────────────────────────────────

    /** Stored so refreshApex can invalidate the cache after each callout. */
    _wiredLogsResult;
    logs = [];

    @wire(getCreditRiskLogs, { contactId: '$recordId' })
    wiredLogs(result) {
        this._wiredLogsResult = result;
        if (result.data) {
            this.logs = this._transformLogs(result.data);
        } else if (result.error) {
            this.errorMessage =
                'Unable to load assessment history. Please refresh the page.';
        }
    }

    // ── Getters (UI Logic) ─────────────────────────────────────────────────

    get hasLogs() {
        return this.logs && this.logs.length > 0;
    }

    /** CSS classes applied to the risk badge in the "Latest Result" summary. */
    get riskBadgeClass() {
        if (!this.latestResult) return 'risk-badge';
        return RISK_BADGE_CLASS[this.latestResult.riskLevel] ?? 'risk-badge risk-badge-unknown';
    }

    // ── Event Handlers (UI Logic) ──────────────────────────────────────────

    handleCheckCreditRisk() {
        // Delegate to private service method to keep the handler thin
        this._performCreditRiskCheck();
    }

    // ── Service Methods ────────────────────────────────────────────────────

    async _performCreditRiskCheck() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await checkCreditRisk({ contactId: this.recordId });
            this.latestResult = result;
            this._handleCheckResult(result);
        } catch (error) {
            this._handleCheckError(error);
        } finally {
            this.isLoading = false;
            // Refresh the wired log list to include the new record
            if (this._wiredLogsResult) {
                await refreshApex(this._wiredLogsResult);
            }
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    /**
     * Dispatches an appropriate toast based on whether the Apex call reported
     * a successful API response or an API-level failure (log still created).
     */
    _handleCheckResult(result) {
        if (result.success) {
            this._dispatchToast(
                'Assessment Complete',
                `Risk Level: ${result.riskLevel}`,
                'success'
            );
        } else {
            this.errorMessage = `API responded with an error: ${result.errorMessage}`;
            this._dispatchToast('API Error', result.errorMessage, 'warning');
        }
    }

    /**
     * Handles unexpected Apex/network exceptions (e.g., callout limit exceeded,
     * timeout). The log is still created by Apex before the exception propagates.
     */
    _handleCheckError(error) {
        const message =
            error?.body?.message ??
            error?.message ??
            'An unexpected error occurred. Please try again.';
        this.errorMessage = message;
        this._dispatchToast('Error', message, 'error');
    }

    _dispatchToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * Maps frozen Apex SObject proxies to plain objects so we can attach
     * computed display properties (riskBadgeClass) for use in the template.
     */
    _transformLogs(rawLogs) {
        return rawLogs.map((log) => ({
            Id: log.Id,
            Risk_Level__c: log.Risk_Level__c ?? '—',
            API_Answer__c: log.API_Answer__c ?? '—',
            HTTP_Status_Code__c: log.HTTP_Status_Code__c,
            Callout_Success__c: log.Callout_Success__c,
            statusText: log.Callout_Success__c ? 'Success' : 'Failed',
            statusIconName: log.Callout_Success__c ? 'utility:success' : 'utility:error',
            Error_Message__c: log.Error_Message__c ?? '',
            Callout_Timestamp__c: log.Callout_Timestamp__c
        }));
    }
}
