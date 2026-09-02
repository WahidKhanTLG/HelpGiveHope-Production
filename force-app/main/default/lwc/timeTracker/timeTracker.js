import { LightningElement, track } from 'lwc';

import checkTimeEntryStatus from '@salesforce/apex/TimeTrackerController.checkTimeEntryStatus';
import createTimeEntry from '@salesforce/apex/TimeTrackerController.createTimeEntry';
import getTodaysEntries from '@salesforce/apex/TimeTrackerController.getTodaysEntries';

import CHECKIN_IMAGE from '@salesforce/resourceUrl/checkin';
import CHECKOUT_IMAGE from '@salesforce/resourceUrl/checkout';
import logo from '@salesforce/resourceUrl/Logo';
import mission from '@salesforce/resourceUrl/mission';

export default class TimeTracker extends LightningElement {
    @track Email_Phone = '';
    @track showImage = false;
    @track checkInOutImage = '';
    @track imageAltText = '';
    @track isCheckIn = false;

    @track todaysEntries = [];
    @track loadingEntries = false;

    @track isBusy = false;

    // Local toast state
    @track localToast = {
        visible: false,
        title: '',
        message: '',
        variant: 'info'
    };
    _toastTimer;

    logoUrl = logo;
    missionUrl = mission;

    connectedCallback() {
        this.refreshTodaysEntries();
    }

    async refreshTodaysEntries() {
        this.loadingEntries = true;
        try {
            const data = await getTodaysEntries();
            this.todaysEntries = (data || []).map(row => ({
                ...row,
                startStr: this.formatTime(row.startTime),
                endStr: this.formatTime(row.endTime),
                totalHoursStr: this.formatHours(row.totalHours)
            }));
        } catch (e) {
            this.showToast('Error', 'Failed to load today’s entries', 'error');
        } finally {
            this.loadingEntries = false;
        }
    }

    formatTime(dt) {
        if (!dt) return '—';
        try {
            const d = new Date(dt);
            return new Intl.DateTimeFormat(undefined, {
                hour: 'numeric',
                minute: '2-digit'
            }).format(d);
        } catch {
            return '—';
        }
    }

    formatHours(val) {
        if (val === null || val === undefined) return '—';
        const s = (Math.round(val * 100) / 100).toFixed(2);
        return `${parseFloat(s)} h`;
    }

    handleEmail_PhoneChange(event) {
        this.Email_Phone = event.detail.value;

        const input = this.template.querySelector('[data-field="emailPhone"], .validate');
        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    async handleSubmit() {
        if (!this.isInputValid() || this.isBusy) return;

        this.isBusy = true;
        try {
            const result = await checkTimeEntryStatus({ email_phone: this.Email_Phone });
            const splitMsg = result.split('::');

            if (splitMsg[1] === 'Error') {
                this.showToast('Error', splitMsg[0], 'error');
                this.showImage = false;
                return;
            }

            this.isCheckIn = (splitMsg[0] === 'Checked in');
            this.checkInOutImage = this.isCheckIn ? CHECKOUT_IMAGE : CHECKIN_IMAGE;
            this.imageAltText = this.isCheckIn ? 'Check Out' : 'Check In';
            this.showImage = true;
        } catch (error) {
            this.showToast('Error', 'Error checking time entry status: ' + error, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleImageClick() {
        if (this.isBusy) return;
        this.isBusy = true;
        try {
            const result = await createTimeEntry({ email_phone: this.Email_Phone });
            const splitMsg = result.split('::');

            this.showToast(splitMsg[1], splitMsg[0], splitMsg[1]);

            if (splitMsg[1] === 'Success') {
                await this.refreshTodaysEntries();
                this.Email_Phone = '';
                this.showImage = false;
            }
        } catch (error) {
            this.showToast('Error', 'Failed to perform operation: ' + error, 'error');
        } finally {
            this.isBusy = false;
        }
    }

    // Only local toast
    showToast(title, message, variant = 'info', durationMs = 3500) {
        if (this._toastTimer) {
            clearTimeout(this._toastTimer);
        }

        this.localToast = {
            visible: true,
            title,
            message,
            variant
        };

        this._toastTimer = setTimeout(() => {
            this.closeLocalToast();
        }, durationMs);
    }

    closeLocalToast() {
        if (this._toastTimer) {
            clearTimeout(this._toastTimer);
            this._toastTimer = null;
        }
        this.localToast = { ...this.localToast, visible: false };
    }

    // ---- Validation ----
    isInputValid() {
        const input = this.template.querySelector('[data-field="emailPhone"], .validate');
        const value = (this.Email_Phone || '').trim();

        const isEmail = this.isValidEmail(value);
        const isPhone = this.isValidPhone(value);

        if (!value || (!isEmail && !isPhone)) {
            const msg = 'The phone number or email address you’ve provided appears to be invalid. Please enter valid contact information.';
            if (input) {
                input.setCustomValidity(msg);
                input.reportValidity();
            }
            this.showToast('Error', msg, 'error');
            return false;
        }

        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
        return true;
    }

    isValidEmail(v) {
        const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return re.test(v);
    }

    isValidPhone(v) {
        const digits = (v || '').replace(/[^\d]/g, '');
        return digits.length >= 10 && digits.length <= 15;
    }
}