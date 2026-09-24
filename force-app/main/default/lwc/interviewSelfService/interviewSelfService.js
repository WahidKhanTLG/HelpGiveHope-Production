import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getBooking from '@salesforce/apex/InterviewSelfServiceController.getBooking';
import selectSlot from '@salesforce/apex/InterviewSelfServiceController.selectSlot';
import DEFAULT_LOGO from '@salesforce/resourceUrl/HGH_Logo_Web';

const MONTHS_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTHS_LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/**
 * Applicant-facing interview scheduling page. Reads the token from ?t=..., shows the current booking
 * and the open slots for the household's zone, and lets the applicant pick or change a slot.
 * All rules are enforced in Apex; this component only renders what the server returns.
 */
export default class InterviewSelfService extends LightningElement {
    @api pageHeading = 'Your Home Interview';
    @api organizationName = 'Help Give Hope';
    @api brandColor;          // e.g. #0d7995 — set from Builder to match the site theme
    @api accentColor;
    @api showLogo = false;    // Builder toggle (design attribute default: true)
    @api logoUrl;             // optional override, e.g. a CMS image URL

    get logoSrc() {
        return this.logoUrl || DEFAULT_LOGO;
    }
    get displayLogo() {
        return this.showLogo === true || this.showLogo === 'true';
    }

    @track booking;
    token;
    loading = true;
    saving = false;
    showConfirm = false;
    errorMessage;
    successMessage;
    expandedDayId;
    selectedSlotId;
    selectedSlotLabel;
    selectedDayLabel;

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const state = (pageRef && pageRef.state) || {};
        const token = state.t || state.token;
        if (token && token !== this.token) {
            this.token = token;
            this.load();
        } else if (!token && !this.token) {
            this.loading = false;
            this.booking = { status: 'INVALID', message: 'This scheduling link is not valid. Please use the link from your email.' };
        }
    }

    async load() {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            this.booking = await getBooking({ token: this.token });
            if (this.booking && this.booking.days && this.booking.days.length > 0) {
                const stillThere = this.booking.days.some((d) => d.interviewDayId === this.expandedDayId);
                if (!stillThere) {
                    this.expandedDayId = this.booking.days[0].interviewDayId;
                }
            }
        } catch (error) {
            this.booking = undefined;
            this.errorMessage = this.extractError(error);
        } finally {
            this.loading = false;
        }
    }

    // ---------- theme ----------
    get brandStyle() {
        const parts = [];
        if (this.brandColor) {
            parts.push(`--hgh-primary:${this.brandColor}`);
            parts.push(`--hgh-primary-dark:${this.brandColor}`);
        }
        if (this.accentColor) {
            parts.push(`--hgh-accent:${this.accentColor}`);
        }
        return parts.join(';');
    }

    // ---------- state helpers ----------
    get isOk() {
        return this.booking && this.booking.status === 'OK';
    }
    get isBlocked() {
        return this.booking && this.booking.status !== 'OK' && this.booking.status !== 'ERROR';
    }
    get showStandaloneError() {
        return !!this.errorMessage && !this.isOk;
    }
    get statusMessage() {
        return this.booking ? this.booking.message : undefined;
    }
    get greeting() {
        const name = this.booking && this.booking.firstName;
        return name ? `Hi ${name}, here are the details of your home interview.` : 'Here are the details of your home interview.';
    }
    get hasBooking() {
        return this.booking && this.booking.hasBooking;
    }
    get canChange() {
        return this.booking && this.booking.canChange;
    }
    get hasDays() {
        return this.booking && this.booking.days && this.booking.days.length > 0;
    }
    get showNoSlotsMessage() {
        return this.isOk && this.canChange && !this.hasDays;
    }
    get sectionTitle() {
        return this.hasBooking ? 'Need a different time?' : 'Choose your interview time';
    }
    get pickerNote() {
        const notes = [];
        const hours = this.booking && this.booking.cutoffHours;
        if (hours) {
            notes.push(`Times can be chosen or changed online up to ${hours} hours before the interview.`);
        }
        const remaining = this.booking ? this.booking.reschedulesRemaining : null;
        if (this.hasBooking && remaining !== null && remaining !== undefined) {
            notes.push(remaining === 1 ? 'You can change your time once more online.' : `You can change your time ${remaining} more times online.`);
        }
        return notes.join(' ');
    }
    get supportLine() {
        const phone = this.booking && this.booking.supportPhone;
        return phone ? `Need help? Call ${this.organizationName} at ${phone}.` : `Need help? Contact ${this.organizationName}.`;
    }

    // ---------- current booking presentation ----------
    get currentParts() {
        // currentDateLabel arrives as "Friday, October 2, 2026"
        const label = (this.booking && this.booking.currentDateLabel) || '';
        const [weekday, rest] = label.split(/,\s*(.+)/);
        const match = /^(\w+)\s+(\d+),\s*(\d{4})$/.exec(rest || '');
        return {
            weekday: weekday || '',
            longDate: rest || '',
            monthShort: match ? (match[1] || '').substring(0, 3) : '',
            dayNumber: match ? match[2] : ''
        };
    }
    get currentWeekday() {
        return this.currentParts.weekday;
    }
    get currentLongDate() {
        return this.currentParts.longDate;
    }
    get currentMonthShort() {
        return this.currentParts.monthShort;
    }
    get currentDayNumber() {
        return this.currentParts.dayNumber;
    }
    get currentTimeRange() {
        const label = (this.booking && this.booking.currentTimeLabel) || '';
        const [start, end] = label.split(' - ');
        return this.range(start, end);
    }

    // ---------- days / slots ----------
    get days() {
        if (!this.hasDays) {
            return [];
        }
        return this.booking.days.map((day) => {
            const expanded = day.interviewDayId === this.expandedDayId;
            const date = this.parseDate(day.dateValue);
            const weekday = date ? WEEKDAYS[date.getDay()] : '';
            const longDate = date ? `${MONTHS_LONG[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}` : day.dateLabel;
            const isMorning = (day.mode || '').toLowerCase().startsWith('morn');
            return {
                ...day,
                expanded,
                weekday,
                longDate,
                fullLabel: `${weekday}, ${longDate}`,
                openCount: day.slots.filter((s) => s.selectable).length,
                cardClass: expanded ? 'hgh-day hgh-day_open' : 'hgh-day',
                modeClass: isMorning ? 'hgh-badge hgh-badge_morning' : 'hgh-badge hgh-badge_afternoon',
                iconName: expanded ? 'utility:chevronup' : 'utility:chevrondown',
                slots: day.slots.map((slot) => {
                    const selected = slot.scheduleId === this.selectedSlotId;
                    return {
                        ...slot,
                        selected,
                        rangeLabel: this.range(slot.startLabel, slot.endLabel),
                        disabled: !slot.selectable || this.saving,
                        chipClass: selected ? 'hgh-chip hgh-chip_selected' : 'hgh-chip',
                        title: slot.reason || `Choose ${slot.label}`
                    };
                })
            };
        });
    }

    /** "8:00 AM", "8:15 AM" -> "8:00 – 8:15 AM"; keeps both suffixes when they differ. */
    range(start, end) {
        if (!start) {
            return '';
        }
        if (!end) {
            return start;
        }
        const s = start.trim();
        const e = end.trim();
        const sSuffix = s.slice(-2);
        const eSuffix = e.slice(-2);
        if (sSuffix === eSuffix) {
            return `${s.slice(0, -3)} – ${e}`;
        }
        return `${s} – ${e}`;
    }

    parseDate(value) {
        if (!value) {
            return null;
        }
        const [y, m, d] = value.split('-').map((n) => parseInt(n, 10));
        if (!y || !m || !d) {
            return null;
        }
        return new Date(y, m - 1, d);
    }

    // ---------- confirmation ----------
    get confirmTitle() {
        return this.hasBooking ? 'Change your interview time?' : 'Book this interview time?';
    }
    get confirmNote() {
        return this.hasBooking
            ? 'Your current time will be released and you will receive an updated calendar invitation.'
            : 'You will receive a confirmation email and a calendar invitation.';
    }
    get confirmButtonLabel() {
        if (this.saving) {
            return 'Saving…';
        }
        return this.hasBooking ? 'Yes, change my time' : 'Yes, book this time';
    }

    // ---------- events ----------
    handleToggleDay(event) {
        const dayId = event.currentTarget.dataset.dayId;
        this.expandedDayId = this.expandedDayId === dayId ? undefined : dayId;
    }

    handleSlotClick(event) {
        const { scheduleId, slotLabel, dayLabel } = event.currentTarget.dataset;
        this.selectedSlotId = scheduleId;
        this.selectedSlotLabel = slotLabel;
        this.selectedDayLabel = dayLabel;
        this.successMessage = undefined;
        this.errorMessage = undefined;
        this.showConfirm = true;
    }

    handleCancelConfirm() {
        if (this.saving) {
            return;
        }
        this.showConfirm = false;
        this.selectedSlotId = undefined;
    }

    async handleConfirm() {
        if (!this.selectedSlotId) {
            return;
        }
        this.saving = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            const result = await selectSlot({ token: this.token, scheduleId: this.selectedSlotId });
            this.booking = result;
            if (result && result.status === 'OK') {
                this.successMessage = result.message || 'Your interview time is confirmed.';
            } else {
                this.errorMessage = (result && result.message) || 'We could not save your selection.';
            }
        } catch (error) {
            this.errorMessage = this.extractError(error);
        } finally {
            this.saving = false;
            this.showConfirm = false;
            this.selectedSlotId = undefined;
        }
    }

    handleRefresh() {
        this.successMessage = undefined;
        this.load();
    }

    extractError(error) {
        if (!error) {
            return 'Something went wrong. Please try again.';
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body) && error.body.length && error.body[0].message) {
            return error.body[0].message;
        }
        return error.message || 'Something went wrong. Please try again.';
    }
}