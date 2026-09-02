import { LightningElement, api, track, wire } from 'lwc';
import getInterviewDays from '@salesforce/apex/SelectInterviewSlotController.getInterviewDays';
import updateInterviewSchedule from '@salesforce/apex/SelectInterviewSlotController.updateInterviewSchedule';
import unscheduleInterview from '@salesforce/apex/SelectInterviewSlotController.unscheduleInterview'; 
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
import ACCOUNT_SCHEDULE_FIELD from '@salesforce/schema/Account.Interview_Day_Schedule__c';
import CASE_ACCOUNT_FIELD from '@salesforce/schema/Case.AccountId';

export default class SelectInterviewSlot extends LightningElement {
    // @api recordId;
    @api accountId;

    @track interviewDays = [];
    @track selectedScheduleId = '';
    @track selectedDate = '';
    @track dateOptions = [];
    @track slotOptions = [];
    
    @track isLoading = false;
    @track isUnscheduling = false;
    @track hasExistingBooking = false;
    @track contextAccountId = '';
    @track contextCaseId = '';

    _recordId;
    wiredAccountResult;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        // Case Ids start with '500' — wait for wiredCaseRecord to resolve the Account Id.
        // Account Ids (start with '001') or other non-Case Ids can be used directly.
        if (value?.startsWith('500')) {
            // contextAccountId will be set by wiredCaseRecord once it resolves
            this.contextCaseId = value;
            return;
        }
        const newContext = this.accountId || value || this.contextAccountId;
        const changed = newContext && newContext !== this.contextAccountId;
        this.contextAccountId = newContext;
        if (changed) {
            this.loadInterviewDays();
        }
    }
    

    connectedCallback() {
        this.contextAccountId = this.accountId || this.recordId || '';
        this.loadInterviewDays();
    }

    // Computed: only wire Case record when recordId is a Case (prefix '500')
    get _caseIdForLookup() {
        const id = this._recordId;
        return id?.startsWith('500') ? id : null;
    }

    // Resolve Case → Account Id so existing-booking check works on Case pages
    @wire(getRecord, { recordId: '$_caseIdForLookup', fields: [CASE_ACCOUNT_FIELD] })
    wiredCaseRecord({ data }) {
        if (data) {
            const acctId = getFieldValue(data, CASE_ACCOUNT_FIELD);
            if (acctId && acctId !== this.contextAccountId) {
                this.contextAccountId = acctId;
                this.loadInterviewDays();
            }
        }
        // If error, recordId was not a Case — no action needed
    }

    @wire(getRecord, { recordId: '$contextAccountId', fields: [ACCOUNT_SCHEDULE_FIELD] })
    wiredAccount(result) {
        const { data, error } = result || {};
        if (data) {
            const bookedId = getFieldValue(data, ACCOUNT_SCHEDULE_FIELD);
            this.hasExistingBooking = !!bookedId;
            this.wiredAccountResult = result;
        } else if (error) {
            this.hasExistingBooking = false;
        }
    }

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (!ref) return;
        // Fallback: get recordId from URL state if not provided as @api
        const state = ref.state || {};
        const urlRecordId = state.recordId || state.c__recordId;
        if (!this.contextAccountId && urlRecordId) {
            if (urlRecordId.startsWith('500')) {
                this._recordId = urlRecordId;
                this.contextCaseId = urlRecordId;
                return;
            }
            this.contextAccountId = urlRecordId;
            this.loadInterviewDays();
        }
    }

    get bookDisabled() {
        return this.isLoading || !this.selectedScheduleId || this.hasExistingBooking;
    }

    get slotDisabled() {
        return this.isLoading || this.hasExistingBooking || !this.selectedDate;
    }

    get dateDisabled() {
        return this.isLoading || this.hasExistingBooking;
    }

    async loadInterviewDays() {
        const acctId = this.contextAccountId;
        if (!acctId) return;
        this.isLoading = true;
        try {
            const days = await getInterviewDays({ accountId: acctId });
            this.interviewDays = days || [];

            // Build unique date list for Date dropdown
            const dateSet = new Set();
            for (const d of (this.interviewDays || [])) {
                if (d.Interview_Date__c) dateSet.add(d.Interview_Date__c);
            }
            const dateArray = Array.from(dateSet);
            dateArray.sort((a, b) => a.localeCompare(b)); // ISO date asc
            this.dateOptions = dateArray.map(dt => ({ label: formatDateLabel(dt), value: dt }));

            // If previously selected date no longer exists, clear it and slots
            if (this.dateOptions.some(o => o.value === this.selectedDate)) {
                // Rebuild slots for the selected date in case data changed
                this.buildSlotOptionsForSelectedDate();
            } else {
                this.selectedDate = '';
                this.slotOptions = [];
                this.selectedScheduleId = '';
            }
        } catch (error) {
            this.showToast('Error loading interview days', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSelectDate(event) {
        this.selectedDate = event.detail.value;
        this.selectedScheduleId = '';
        this.buildSlotOptionsForSelectedDate();
    }

    buildSlotOptionsForSelectedDate() {
        if (!this.selectedDate) {
            this.slotOptions = [];
            return;
        }
        const combined = [];
        (this.interviewDays || [])
            .filter(day => day.Interview_Date__c === this.selectedDate)
            .forEach(day => {
                const mode = day.Schedule_Mode__c; // 'Morning' or 'AfterNoon'
                const modeLabel = mode === 'AfterNoon' ? 'Afternoon' : mode;
                const modeOrder = mode === 'Morning' ? 0 : 1; // Morning first, then Afternoon
                (day.Interview_Day_Schedules__r || []).forEach(s => {
                    const namePart = (s.Name || '').replace('AfterNoon', 'Afternoon');
                    const label = `${modeLabel}: ${namePart}`;
                    combined.push({ label, value: s.Id, sortKey: `${modeOrder}|${namePart}` });
                });
            });
        combined.sort((a, b) => (a.sortKey || '').localeCompare(b.sortKey || ''));
        this.slotOptions = dedupeOptions(combined).map(({ label, value }) => ({ label, value }));
        if (!this.slotOptions.some(o => o.value === this.selectedScheduleId)) {
            this.selectedScheduleId = '';
        }
    }

    handleSelectSlot(event) {
        this.selectedScheduleId = event.detail.value;
    }

    async handleBook() {
        const acctId = this.contextCaseId || this.contextAccountId;
        if (!this.selectedScheduleId || !acctId) return;
        this.isLoading = true;
        try {
            await updateInterviewSchedule({ scheduleId: this.selectedScheduleId, accountId: acctId });
            this.showToast('Success', 'Interview slot booked!', 'success');
            // Clear selection and refresh options
            this.selectedScheduleId = '';
            
            await refreshApex(this.wiredAccountResult);
            await this.loadInterviewDays();
        } catch (error) {
            this.showToast('Error booking slot', error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleUnschedule() {
        this.isUnscheduling = true;
        try {
            await unscheduleInterview({ accountId: this.contextAccountId });
            this.showToast('Success', 'Interview unscheduled successfully.', 'success');
            
            this.selectedDate = '';
            this.selectedScheduleId = '';
            
            await refreshApex(this.wiredAccountResult);
            await this.loadInterviewDays();
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        } finally {
            this.isUnscheduling = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    
}

// Deduplicate options by value; Name already unique enough but keep safe
function dedupeOptions(options) {
    const seen = new Set();
    const out = [];
    (options || []).forEach(o => {
        if (!seen.has(o.value)) { seen.add(o.value); out.push(o); }
    });
    return out;
}

// Format YYYY-MM-DD to "DayName Mon DD, YYYY" (e.g., "Mon Oct 04, 2025")
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function formatDateLabel(isoDate) {
    if (!isoDate) return '';
    const parts = isoDate.split('-');
    if (parts.length !== 3) return isoDate;
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) return isoDate;
    const dateObj = new Date(y, m - 1, d);
    const wd = WEEKDAYS[dateObj.getDay()];
    const mon = MONTHS[dateObj.getMonth()];
    // Do not pad day with leading zero to match format like "Wed Oct 3, 2025"
    const dd = String(d);
    return `${wd} ${mon} ${dd}, ${y}`;
}