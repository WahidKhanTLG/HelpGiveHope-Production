import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import logoResource from '@salesforce/resourceUrl/HGH_Logo_Web';

import getZones from '@salesforce/apex/BulkVolunteerReassignmentController.getZones';
import getScheduleDates from '@salesforce/apex/BulkVolunteerReassignmentController.getScheduleDates';
import getInterviews from '@salesforce/apex/BulkVolunteerReassignmentController.getInterviews';
import reassignVolunteers from '@salesforce/apex/BulkVolunteerReassignmentController.reassignVolunteers';

const MAX_SELECTION = 20;

export default class BulkVolunteerReassignment extends LightningElement {
    logoUrl = logoResource;
    currentYear = new Date().getFullYear();
    maxSelection = MAX_SELECTION;

    zoneOptions = [];
    dateOptions = [];
    rows = [];

    selectedZoneId = '';
    selectedDate = '';
    selectedVolunteerId = '';

    loadingDates = false;
    loadingRows = false;
    saving = false;

    pageError = '';
    resultMessage = '';
    resultDetails = [];
    resultHasFailures = false;

    volunteerFilter = {
        criteria: [
            { fieldPath: 'IsActive', operator: 'eq', value: true },
            { fieldPath: 'UserType', operator: 'eq', value: 'Standard' }
        ],
        filterLogic: '1 AND 2'
    };

    volunteerDisplayInfo = {
        primaryField: 'Name',
        additionalFields: ['Email']
    };

    volunteerMatchingInfo = {
        primaryField: { fieldPath: 'Name', mode: 'contains' },
        additionalFields: [{ fieldPath: 'Email', mode: 'contains' }]
    };

    connectedCallback() {
        this.loadInitialData();
    }

    async loadInitialData() {
        this.pageError = '';
        try {
            const zones = await getZones();
            this.zoneOptions = zones || [];
        } catch (error) {
            this.pageError = this.normalizeError(error);
        }
    }

    async handleZoneChange(event) {
        this.selectedZoneId = event.detail.value;
        this.selectedDate = '';
        this.dateOptions = [];
        this.rows = [];
        this.clearResult();

        if (!this.selectedZoneId) {
            return;
        }

        this.loadingDates = true;
        this.pageError = '';
        try {
            this.dateOptions = await getScheduleDates({ zoneId: this.selectedZoneId }) || [];
        } catch (error) {
            this.pageError = this.normalizeError(error);
        } finally {
            this.loadingDates = false;
        }
    }

    async handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this.rows = [];
        this.clearResult();
        await this.loadInterviews();
    }

    async handleRefreshInterviews() {
        if (!this.selectedZoneId || !this.selectedDate || this.loadingRows || this.saving) {
            return;
        }

        // Refresh only the interview results for the current Zone/Date.
        // Selection is intentionally cleared so stale rows cannot be reassigned.
        this.rows = this.rows.map((row) => ({ ...row, selected: false }));
        this.clearResult();
        await this.loadInterviews();
    }

    async loadInterviews() {
        if (!this.selectedZoneId || !this.selectedDate) {
            return;
        }

        this.loadingRows = true;
        this.pageError = '';
        try {
            const records = await getInterviews({
                zoneId: this.selectedZoneId,
                interviewDate: this.selectedDate
            });
            this.rows = (records || []).map((row) => this.decorateRow(row, false));
        } catch (error) {
            this.pageError = this.normalizeError(error);
            this.rows = [];
        } finally {
            this.loadingRows = false;
        }
    }

    handleRowSelection(event) {
        const scheduleId = event.target.dataset.id;
        const checked = event.target.checked;
        const currentlySelected = this.selectedCount;

        if (checked && currentlySelected >= MAX_SELECTION) {
            event.target.checked = false;
            this.showToast(
                'Selection limit',
                `A maximum of ${MAX_SELECTION} interviews can be reassigned at one time.`,
                'warning'
            );
            return;
        }

        this.rows = this.rows.map((row) => {
            if (row.scheduleId === scheduleId) {
                return { ...row, selected: checked };
            }
            return row;
        });
        this.clearResult();
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.clearResult();

        if (!checked) {
            this.rows = this.rows.map((row) => ({ ...row, selected: false }));
            return;
        }

        let selected = 0;
        this.rows = this.rows.map((row) => {
            if (!row.disabled && selected < MAX_SELECTION) {
                selected += 1;
                return { ...row, selected: true };
            }
            return { ...row, selected: false };
        });

        if (this.eligibleCount > MAX_SELECTION) {
            this.showToast(
                'First 20 selected',
                `There are more than ${MAX_SELECTION} eligible interviews. The first ${MAX_SELECTION} were selected for this batch.`,
                'info'
            );
        }
    }

    handleVolunteerChange(event) {
        this.selectedVolunteerId = event.detail.recordId || '';
        this.clearResult();
    }

    async handleReassign() {
        const scheduleIds = this.rows
            .filter((row) => row.selected)
            .map((row) => row.scheduleId);

        if (!scheduleIds.length) {
            this.showToast('Select interviews', 'Select at least one interview to reassign.', 'warning');
            return;
        }

        if (!this.selectedVolunteerId) {
            this.showToast('Select a volunteer', 'Choose the new volunteer before continuing.', 'warning');
            return;
        }

        this.saving = true;
        this.pageError = '';
        this.clearResult();

        try {
            const result = await reassignVolunteers({
                scheduleIds,
                volunteerId: this.selectedVolunteerId
            });

            this.resultMessage = result?.message || 'Volunteer reassignment completed.';
            this.resultDetails = result?.details || [];
            this.resultHasFailures = (result?.failedCount || 0) > 0;

            const variant = this.resultHasFailures ? 'warning' : 'success';
            this.showToast('Bulk Volunteer Reassignment', this.resultMessage, variant);

            if (!this.resultHasFailures) {
                // Clear the action inputs, but keep the Zone/Date context so
                // the user can immediately see the updated Current Volunteer.
                this.selectedVolunteerId = '';
                await this.loadInterviews();
            } else {
                await this.loadInterviews();
            }
        } catch (error) {
            this.pageError = this.normalizeError(error);
            this.showToast('Reassignment failed', this.pageError, 'error');
        } finally {
            this.saving = false;
        }
    }

    decorateRow(row, selected) {
        const disabled = row.selectable !== true;
        const assignmentStatus = row.assignmentStatus || 'Unassigned';
        const normalizedStatus = assignmentStatus.toLowerCase().replace(/\s+/g, '-');
        return {
            ...row,
            selected: disabled ? false : selected,
            disabled,
            checkboxLabel: `Select Case ${row.caseNumber || ''}`,
            rowClass: disabled ? 'row-locked' : '',
            statusClass: `status-pill status-${normalizedStatus}`
        };
    }

    clearResult() {
        this.resultMessage = '';
        this.resultDetails = [];
        this.resultHasFailures = false;
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected Salesforce error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get selectedCount() {
        return this.rows.filter((row) => row.selected).length;
    }

    get eligibleCount() {
        return this.rows.filter((row) => !row.disabled).length;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasResultDetails() {
        return this.resultDetails.length > 0;
    }

    get rowCountLabel() {
        const total = this.rows.length;
        const eligible = this.eligibleCount;
        return `${total} record${total === 1 ? '' : 's'} • ${eligible} eligible`;
    }

    get allEligibleSelected() {
        if (!this.eligibleCount) {
            return false;
        }
        const target = Math.min(this.eligibleCount, MAX_SELECTION);
        return this.selectedCount === target;
    }

    get selectAllDisabled() {
        return !this.hasRows || this.eligibleCount === 0 || this.saving;
    }

    get dateDisabled() {
        return !this.selectedZoneId || this.loadingDates || this.dateOptions.length === 0;
    }

    get datePlaceholder() {
        if (!this.selectedZoneId) {
            return 'Select a Zone first';
        }
        if (this.loadingDates) {
            return 'Loading dates...';
        }
        if (!this.dateOptions.length) {
            return `No ${this.currentYear} scheduled dates`;
        }
        return 'Select a Scheduled Date';
    }

    get volunteerDisabled() {
        return this.selectedCount === 0 || this.saving;
    }

    get reassignDisabled() {
        return this.saving || this.selectedCount === 0 || !this.selectedVolunteerId;
    }

    get reassignButtonLabel() {
        if (this.saving) {
            return 'Reassigning...';
        }
        return this.selectedCount > 0
            ? `Reassign ${this.selectedCount} Selected`
            : 'Reassign Selected';
    }

    get emptyStateTitle() {
        if (!this.selectedZoneId) {
            return 'Select a Zone';
        }
        if (!this.selectedDate) {
            return 'Select a Scheduled Date';
        }
        return 'No scheduled interviews found';
    }

    get emptyStateMessage() {
        if (!this.selectedZoneId) {
            return 'Choose a Zone to load the available current-year interview dates.';
        }
        if (!this.selectedDate) {
            return 'Choose one of the scheduled dates available for the selected Zone.';
        }
        return 'There are no booked Case interviews for this Zone and Scheduled Date.';
    }

    get resultMessageClass() {
        return this.resultHasFailures
            ? 'message message-warning'
            : 'message message-success';
    }

    get resultIcon() {
        return this.resultHasFailures ? 'utility:warning' : 'utility:success';
    }
}