import { LightningElement, api, track, wire } from 'lwc';

import getInterviewDays
    from '@salesforce/apex/SelectInterviewSlotController.getInterviewDays';

import updateInterviewSchedule
    from '@salesforce/apex/SelectInterviewSlotController.updateInterviewSchedule';

import bookAndAssignInterview
    from '@salesforce/apex/SelectInterviewSlotController.bookAndAssignInterview';

import unscheduleInterview
    from '@salesforce/apex/SelectInterviewSlotController.unscheduleInterview';

import getCurrentBooking
    from '@salesforce/apex/SelectInterviewSlotController.getCurrentBooking';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import {
    getRecord,
    getFieldValue
} from 'lightning/uiRecordApi';

import { CurrentPageReference } from 'lightning/navigation';

import ACCOUNT_SCHEDULE_FIELD
    from '@salesforce/schema/Account.Interview_Day_Schedule__c';

import CASE_ACCOUNT_FIELD
    from '@salesforce/schema/Case.AccountId';

import CASE_SCHEDULE_FIELD
    from '@salesforce/schema/Case.Interview_Day_Schedule__c';


export default class SelectInterviewSlot extends LightningElement {

    @api accountId;

    @track interviewDays = [];
    @track selectedScheduleId = '';
    @track selectedDate = '';
    @track selectedVolunteerId = '';

    @track dateOptions = [];
    @track slotOptions = [];

    @track isLoading = false;
    @track isUnscheduling = false;

    @track hasExistingBooking = false;

    @track contextAccountId = '';
    @track contextCaseId = '';

    _recordId;
    wiredAccountResult;
    wiredCaseResult;


    // =========================================================
    // RECORD CONTEXT
    // =========================================================

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;

        if (!value) {
            return;
        }

        /*
         * Case Id
         * Wait for wiredCaseRecord to resolve Account Id.
         */
        if (value.startsWith('500')) {
            this.contextCaseId = value;
            this.contextAccountId = '';
            return;
        }

        /*
         * Account context
         */
        const newContext =
            this.accountId ||
            value;

        const changed =
            newContext &&
            newContext !== this.contextAccountId;

        this.contextAccountId =
            newContext;

        if (changed) {
            this.loadInterviewDays();
        }
    }


    connectedCallback() {
        const initialId =
            this.accountId ||
            this._recordId ||
            '';

        if (!initialId) {
            return;
        }

        /*
         * Case context
         */
        if (initialId.startsWith('500')) {
            this.contextCaseId =
                initialId;

            this.contextAccountId =
                '';

            return;
        }

        /*
         * Account context
         */
        this.contextAccountId =
            initialId;

        this.loadInterviewDays();
    }


    // =========================================================
    // CASE -> ACCOUNT
    // =========================================================

    get _caseIdForLookup() {
        const id = this._recordId;

        return id?.startsWith('500')
            ? id
            : null;
    }


    @wire(
        getRecord,
        {
            recordId: '$_caseIdForLookup',
            fields: [CASE_ACCOUNT_FIELD, CASE_SCHEDULE_FIELD]
        }
    )
    wiredCaseRecord(result) {

        const { data, error } = result || {};
        this.wiredCaseResult = result;

        if (data) {

            const accountId =
                getFieldValue(
                    data,
                    CASE_ACCOUNT_FIELD
                );

            const bookedScheduleId =
                getFieldValue(
                    data,
                    CASE_SCHEDULE_FIELD
                );

            this.hasExistingBooking =
                !!bookedScheduleId;

            if (!this.hasExistingBooking) {
                this.selectedVolunteerId = '';
                this.loadLegacyCaseBookingState();
            }

            if (
                accountId &&
                accountId !== this.contextAccountId
            ) {
                this.contextAccountId =
                    accountId;

                this.loadInterviewDays();
            }

        } else if (error) {

            this.hasExistingBooking = false;

            this.showToast(
                'Error',
                'Unable to resolve the Account for this Case.',
                'error'
            );
        }
    }




    get _accountIdForBookingLookup() {
        return this.contextCaseId
            ? null
            : (this.contextAccountId || null);
    }

    async loadLegacyCaseBookingState() {
        if (!this.contextCaseId) {
            return;
        }
        try {
            const booking = await getCurrentBooking({
                accountId: this.contextCaseId
            });
            this.hasExistingBooking = !!booking?.scheduleId;
        } catch (error) {
            // The Case field remains authoritative; legacy fallback failure must not block the action.
            this.hasExistingBooking = false;
        }
    }


    // =========================================================
    // CURRENT ACCOUNT BOOKING
    // =========================================================

    @wire(
        getRecord,
        {
            recordId: '$_accountIdForBookingLookup',
            fields: [ACCOUNT_SCHEDULE_FIELD]
        }
    )
    wiredAccount(result) {

        const {
            data,
            error
        } = result || {};

        if (data) {

            const bookedScheduleId =
                getFieldValue(
                    data,
                    ACCOUNT_SCHEDULE_FIELD
                );

            this.hasExistingBooking =
                !!bookedScheduleId;

            this.wiredAccountResult =
                result;

            /*
             * If booking does not exist,
             * reset volunteer selection.
             */
            if (!this.hasExistingBooking) {
                this.selectedVolunteerId = '';
            }

        } else if (error) {

            this.hasExistingBooking =
                false;
        }
    }


    // =========================================================
    // PAGE REFERENCE FALLBACK
    // =========================================================

    @wire(CurrentPageReference)
    handlePageRef(ref) {

        if (!ref) {
            return;
        }

        const state =
            ref.state || {};

        const urlRecordId =
            state.recordId ||
            state.c__recordId;

        if (
            !urlRecordId ||
            this.contextAccountId ||
            this.contextCaseId
        ) {
            return;
        }

        if (urlRecordId.startsWith('500')) {

            this._recordId =
                urlRecordId;

            this.contextCaseId =
                urlRecordId;

            return;
        }

        this.contextAccountId =
            urlRecordId;

        this.loadInterviewDays();
    }


    // =========================================================
    // GETTERS
    // =========================================================

    get isCaseContext() {
        return !!this.contextCaseId;
    }


    get hasAvailableInterviewDays() {
        return (
            Array.isArray(this.interviewDays) &&
            this.interviewDays.length > 0
        );
    }


    get showNoAvailability() {
        return (
            !this.hasExistingBooking &&
            !this.hasAvailableInterviewDays
        );
    }


    get dateDisabled() {
        return this.isLoading;
    }


    get slotDisabled() {
        return (
            this.isLoading ||
            !this.selectedDate
        );
    }


    get bookButtonLabel() {

        if (this.isCaseContext) {
            return 'Book & Assign Volunteer';
        }

        return 'Book Selected Slot';
    }


    get bookDisabled() {

        if (this.isLoading) {
            return true;
        }

        if (!this.selectedDate) {
            return true;
        }

        if (!this.selectedScheduleId) {
            return true;
        }

        /*
         * Volunteer is mandatory
         * when booking from Case.
         */
        if (
            this.isCaseContext &&
            !this.selectedVolunteerId
        ) {
            return true;
        }

        return false;
    }


    // =========================================================
    // LOAD INTERVIEW DAYS
    // =========================================================

    async loadInterviewDays() {

        const accountId =
            this.contextAccountId;

        if (!accountId) {
            return;
        }

        this.isLoading =
            true;

        try {

            const days =
                await getInterviewDays({
                    accountId
                });

            this.interviewDays =
                days || [];

            const dateSet =
                new Set();

            for (
                const day of this.interviewDays
            ) {
                if (day.Interview_Date__c) {
                    dateSet.add(
                        day.Interview_Date__c
                    );
                }
            }

            const dateArray =
                Array.from(dateSet);

            dateArray.sort(
                (a, b) =>
                    a.localeCompare(b)
            );

            this.dateOptions =
                dateArray.map(
                    dateValue => ({
                        label:
                            formatDateLabel(
                                dateValue
                            ),
                        value:
                            dateValue
                    })
                );

            /*
             * Preserve selection only
             * if date still exists.
             */
            const dateStillExists =
                this.dateOptions.some(
                    option =>
                        option.value ===
                        this.selectedDate
                );

            if (dateStillExists) {

                this.buildSlotOptionsForSelectedDate();

            } else {

                this.selectedDate =
                    '';

                this.selectedScheduleId =
                    '';

                this.slotOptions =
                    [];
            }

        } catch (error) {

            this.showToast(
                'Error loading interview days',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isLoading =
                false;
        }
    }


    // =========================================================
    // DATE SELECTION
    // =========================================================

    handleSelectDate(event) {

        this.selectedDate =
            event.detail.value;

        this.selectedScheduleId =
            '';

        this.buildSlotOptionsForSelectedDate();
    }


    buildSlotOptionsForSelectedDate() {

        if (!this.selectedDate) {

            this.slotOptions =
                [];

            this.selectedScheduleId =
                '';

            return;
        }

        const combined =
            [];

        this.interviewDays
            .filter(
                day =>
                    day.Interview_Date__c ===
                    this.selectedDate
            )
            .forEach(day => {

                const mode =
                    day.Schedule_Mode__c;

                const modeLabel =
                    mode === 'AfterNoon'
                        ? 'Afternoon'
                        : mode;

                const modeOrder =
                    mode === 'Morning'
                        ? 0
                        : 1;

                const schedules =
                    day.Interview_Day_Schedules__r ||
                    [];

                schedules.forEach(
                    schedule => {

                        const namePart =
                            (
                                schedule.Name ||
                                ''
                            ).replace(
                                'AfterNoon',
                                'Afternoon'
                            );

                        combined.push({
                            label:
                                `${modeLabel}: ${namePart}`,
                            value:
                                schedule.Id,
                            sortKey:
                                `${modeOrder}|${namePart}`
                        });
                    }
                );
            });


        combined.sort(
            (a, b) =>
                (
                    a.sortKey ||
                    ''
                ).localeCompare(
                    b.sortKey ||
                    ''
                )
        );


        this.slotOptions =
            dedupeOptions(combined)
                .map(
                    ({
                        label,
                        value
                    }) => ({
                        label,
                        value
                    })
                );


        const selectedStillExists =
            this.slotOptions.some(
                option =>
                    option.value ===
                    this.selectedScheduleId
            );

        if (!selectedStillExists) {
            this.selectedScheduleId =
                '';
        }
    }


    // =========================================================
    // SLOT
    // =========================================================

    handleSelectSlot(event) {
        this.selectedScheduleId =
            event.detail.value;
    }


    // =========================================================
    // VOLUNTEER
    // =========================================================

    handleVolunteerChange(event) {
        this.selectedVolunteerId =
            event.detail.recordId ||
            '';
    }


    // =========================================================
    // BOOK + ASSIGN
    // =========================================================

    async handleBook() {

        const contextId =
            this.contextCaseId ||
            this.contextAccountId;

        if (
            !contextId ||
            !this.selectedScheduleId
        ) {
            return;
        }

        /*
         * Additional protection.
         */
        if (
            this.isCaseContext &&
            !this.selectedVolunteerId
        ) {

            this.showToast(
                'Volunteer Required',
                'Please select a volunteer before booking the interview.',
                'warning'
            );

            return;
        }


        this.isLoading =
            true;

        try {

            /*
             * CASE:
             * Book slot + assign volunteer.
             */
            if (this.isCaseContext) {

                await bookAndAssignInterview({
                    scheduleId:
                        this.selectedScheduleId,

                    accountId:
                        this.contextCaseId,

                    volunteerId:
                        this.selectedVolunteerId
                });


                this.showToast(
                    'Success',
                    'Interview booked and volunteer assigned successfully.',
                    'success'
                );

            } else {

                /*
                 * ACCOUNT fallback:
                 * Preserve previous booking behavior.
                 */
                await updateInterviewSchedule({
                    scheduleId:
                        this.selectedScheduleId,

                    accountId:
                        this.contextAccountId
                });


                this.showToast(
                    'Success',
                    'Interview slot booked successfully.',
                    'success'
                );
            }


            /*
             * Clear local selections.
             */
            this.selectedDate =
                '';

            this.selectedScheduleId =
                '';

            this.selectedVolunteerId =
                '';

            this.slotOptions =
                [];


            /*
             * Refresh the booking pointer for the current context.
             */
            if (this.isCaseContext && this.wiredCaseResult) {
                await refreshApex(
                    this.wiredCaseResult
                );
            } else if (this.wiredAccountResult) {
                await refreshApex(
                    this.wiredAccountResult
                );
            }


            /*
             * Reload available schedules.
             */
            await this.loadInterviewDays();


        } catch (error) {

            this.showToast(
                'Error booking interview',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isLoading =
                false;
        }
    }


    // =========================================================
    // UNSCHEDULE
    // =========================================================

    async handleUnschedule() {

        const bookingContextId =
            this.contextCaseId ||
            this.contextAccountId;

        if (!bookingContextId) {
            return;
        }

        this.isUnscheduling =
            true;

        try {

            await unscheduleInterview({
                accountId:
                    bookingContextId
            });


            this.showToast(
                'Success',
                'Interview unscheduled successfully.',
                'success'
            );


            this.selectedDate =
                '';

            this.selectedScheduleId =
                '';

            this.selectedVolunteerId =
                '';

            this.slotOptions =
                [];


            if (this.isCaseContext && this.wiredCaseResult) {
                await refreshApex(
                    this.wiredCaseResult
                );
            } else if (this.wiredAccountResult) {
                await refreshApex(
                    this.wiredAccountResult
                );
            }


            await this.loadInterviewDays();


        } catch (error) {

            this.showToast(
                'Error',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isUnscheduling =
                false;
        }
    }


    // =========================================================
    // TOAST / ERROR
    // =========================================================

    showToast(
        title,
        message,
        variant
    ) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }


    reduceError(error) {

        if (
            error?.body?.message
        ) {
            return error.body.message;
        }

        if (
            Array.isArray(
                error?.body
            )
        ) {
            return error.body
                .map(
                    item =>
                        item.message
                )
                .join(', ');
        }

        return (
            error?.message ||
            'Unknown error'
        );
    }
}


// =========================================================
// HELPERS
// =========================================================

function dedupeOptions(options) {

    const seen =
        new Set();

    const output =
        [];

    (options || [])
        .forEach(option => {

            if (
                !seen.has(
                    option.value
                )
            ) {

                seen.add(
                    option.value
                );

                output.push(
                    option
                );
            }
        });

    return output;
}


const WEEKDAYS = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat'
];


const MONTHS = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
];


function formatDateLabel(
    isoDate
) {

    if (!isoDate) {
        return '';
    }

    const parts =
        isoDate.split('-');

    if (parts.length !== 3) {
        return isoDate;
    }

    const year =
        Number(parts[0]);

    const month =
        Number(parts[1]);

    const day =
        Number(parts[2]);


    if (
        Number.isNaN(year) ||
        Number.isNaN(month) ||
        Number.isNaN(day)
    ) {
        return isoDate;
    }


    const dateObj =
        new Date(
            year,
            month - 1,
            day
        );


    const weekday =
        WEEKDAYS[
            dateObj.getDay()
        ];


    const monthLabel =
        MONTHS[
            dateObj.getMonth()
        ];


    return `${weekday} ${monthLabel} ${day}, ${year}`;
}