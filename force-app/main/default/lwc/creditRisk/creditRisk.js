/**
 * creditRisk
 * ─────────────────────────────────────────────────────────────────────────────
 * LWC component for the Contact record page. Triggers a credit risk assessment
 * via the YesNo API and displays the full history in a sortable datatable.
 *
 * UI logic   : state, getters, event handlers (this file)
 * Service    : CreditRiskService Apex class — callouts + DML
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
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Risk Level',
        fieldName: 'Risk_Level__c',
        type: 'text',
        sortable: true
    },
    {
        label: 'API Answer',
        fieldName: 'API_Answer__c',
        type: 'text'
    },
    {
        label: 'HTTP Status',
        fieldName: 'HTTP_Status_Code__c',
        type: 'number',
        cellAttributes: { alignment: 'left' }
    },
    {
        label: 'Status',
        fieldName: 'statusText',
        type: 'text',
        cellAttributes: {
            iconName: { fieldName: 'statusIconName' },
            iconAlternativeText: { fieldName: 'statusText' }
        }
    },
    {
        label: 'Error Details',
        fieldName: 'Error_Message__c',
        type: 'text',
        wrapText: true
    }
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
    sortedBy = 'Callout_Timestamp__c';
    sortedDirection = 'desc';

    // ── Wired Data ─────────────────────────────────────────────────────────

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

    get riskBadgeClass() {
        if (!this.latestResult) return 'risk-badge';
        return (
            RISK_BADGE_CLASS[this.latestResult.riskLevel] ??
            'risk-badge risk-badge-unknown'
        );
    }

    // ── Event Handlers (UI Logic) ──────────────────────────────────────────

    handleCheckCreditRisk() {
        this._performCreditRiskCheck();
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
        this.logs = this._sortLogs([...this.logs], fieldName, sortDirection);
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
            if (this._wiredLogsResult) {
                await refreshApex(this._wiredLogsResult);
            }
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

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
     * Maps frozen Apex SObject proxies to plain objects. Computes display
     * fields (statusText, statusIconName) expected by the datatable columns.
     */
    _transformLogs(rawLogs) {
        return rawLogs.map((log) => ({
            Id: log.Id,
            Risk_Level__c: log.Risk_Level__c ?? '—',
            API_Answer__c: log.API_Answer__c ?? '—',
            HTTP_Status_Code__c: log.HTTP_Status_Code__c,
            Callout_Success__c: log.Callout_Success__c,
            statusText: log.Callout_Success__c ? 'Success' : 'Failed',
            statusIconName: log.Callout_Success__c
                ? 'utility:success'
                : 'utility:error',
            Error_Message__c: log.Error_Message__c ?? '',
            Callout_Timestamp__c: log.Callout_Timestamp__c
        }));
    }

    _sortLogs(data, field, direction) {
        const factor = direction === 'asc' ? 1 : -1;
        return data.sort((a, b) => {
            const valA = a[field] ?? '';
            const valB = b[field] ?? '';
            if (valA < valB) return -1 * factor;
            if (valA > valB) return 1 * factor;
            return 0;
        });
    }
}
