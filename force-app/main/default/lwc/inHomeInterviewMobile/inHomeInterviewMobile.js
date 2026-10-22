import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import hghLogo from '@salesforce/resourceUrl/HGH_InHome_Logo_Green';
import hghLoaderLogo from '@salesforce/resourceUrl/HGH_Logo_Web';
import loadAssignedInterviews from '@salesforce/apex/InHomeInterviewMobileController.loadAssignedInterviews';
import loadInterview from '@salesforce/apex/InHomeInterviewMobileController.loadInterview';
import saveInterview from '@salesforce/apex/InHomeInterviewMobileController.saveInterview';

const STORAGE_PREFIX = `hghHomeInterview.flow.${USER_ID}`;
const DIRECT_CATEGORIES = new Set(['Pillows', 'Towels', 'Washcloths']);
const PERSISTENCE_VERSION = 3;
const REVIEW_NOTE_KEYS = new Set(['why_we_should_help', 'why_we_should_not_help']);

const FLOW_SUBCATEGORIES = {
    Beds: ['Twin', 'Full', 'Queen', 'King', 'Bunkbed', 'Crib'],
    Bedding: ['Twin', 'Full', 'Queen', 'King', 'Crib'],
    'Mattress Only': ['Twin', 'Full', 'Queen', 'King'],
    'Bed Frame Only': ['Twin', 'Full', 'Queen', 'King'],
    Furniture: ['Kitchen table', 'Kitchen chairs', 'Washer', 'Dryer', 'Refridgerator', 'Couch', 'Dresser', 'Other'],
    'Small Appliance': [
        'Pots/Pans', 'Dishes', 'Glassware', 'Microwave', 'Toaster', 'Vacuum', 'Flatware',
        'Crockpot', 'Air Fryer', 'Dishes - Melamine', 'Cooking Utensils', 'Electric Can Opener', 'Other'
    ]
};

const STEPS = [
    {
        key: 'newBeds',
        icon: 'utility:home',
        caption: 'New Beds',
        title: 'New Bed Needs',
        help: 'Add Beds, Mattress Only, or Bed Frame Only requests. Gender is required when Category is Beds.',
        categories: ['Beds', 'Mattress Only', 'Bed Frame Only']
    },
    {
        key: 'existingBedding',
        icon: 'utility:layers',
        caption: 'Bedding',
        title: 'For Existing Beds Only',
        help: 'Add Bedding requests for existing beds. Select the size, gender, and quantity required.',
        categories: ['Bedding']
    },
    {
        key: 'linens',
        icon: 'utility:package',
        caption: 'Linens',
        title: 'Pillows / Towels / Washcloths',
        help: 'Add the required quantity for Pillows, Towels, and Washcloths.',
        categories: ['Pillows', 'Towels', 'Washcloths']
    },
    {
        key: 'smallAppliances',
        icon: 'utility:apps',
        caption: 'Household',
        title: 'Household / Small Appliances',
        help: 'Select one or more Small Appliance items and enter a quantity for each selected item.',
        categories: ['Small Appliance']
    },
    {
        key: 'furniture',
        icon: 'utility:table',
        caption: 'Furniture',
        title: 'Furniture / Large Appliances',
        help: 'Select one or more Furniture items and enter a quantity for each selected item.',
        categories: ['Furniture']
    },
    {
        key: 'narratives',
        icon: 'utility:comments',
        caption: 'Review',
        title: 'Family Review',
        help: 'Please answer the below questions carefully. BE SPECIFIC!'
    },
    {
        key: 'complete',
        icon: 'utility:check',
        caption: 'Complete',
        title: 'Complete Interview',
        help: 'Review the interview, save any final changes, and complete the interview.'
    }
];

const RECOMMENDATION_OPTIONS = [
    { label: 'Neutral', value: 'Neutral' },
    { label: 'Strongly Recommend', value: 'Strongly Recommend' },
    { label: 'Recommend', value: 'Recommend' },
    { label: 'Concerns', value: 'Concerns' },
    { label: 'Do Not Recommend', value: 'Do Not Recommend' }
];

export default class InHomeInterviewMobile extends LightningElement {
    @api recordId;

    loading = true;
    saving = false;
    syncingOffline = false;
    errorMessage = '';
    offlineMode = false;
    offlineMessage = '';
    hasOfflineDraft = false;
    draftNeedsReview = false;
    persistenceVersion = 0;
    _serverRecommendation = '';
    _refreshSequence = 0;

    activeRecordId;
    openedFromLanding = false;
    assignedGroups = [];

    caseId = '';
    scheduleId = '';
    caseNumber = '';
    householdName = '';
    address = '';
    interviewDate;
    scheduleMode = '';
    startTime;
    endTime;
    zoneName = '';
    interviewerName = '';
    intervieweeName = '';
    intervieweePhone = '';
    contactPhone = '';
    contactEmail = '';
    assignmentStatus = '';

    whyHelp = '';
    whyNotHelp = '';
    santaInterest = false;
    showSanta = false;
    santaFieldAvailable = true;
    whyHelpFieldAvailable = true;
    whyNotHelpFieldAvailable = true;
    otherBedNeeds = '';
    householdRecommendation = '';
    isChristmasCase = false;

    readOnly = false;
    interviewReady = false;
    notReadyMessage = '';
    configWarnings = [];
    formFieldsAvailable = true;

    categoryOptionsFromOrg = [];
    genderOptionsFromOrg = [];
    requestGroups = [];
    removedItems = [];
    sectionNotes = {
        newBeds: '',
        existingBedding: '',
        linens: '',
        smallAppliances: '',
        furniture: '',
        otherItems: ''
    };

    currentStepIndex = 0;
    activeInfoTab = 'form';
    applicantEmployment = {
        applicantName: 'Applicant',
        employmentStatus: '—',
        currentEmployer: '—',
        employmentLengthMonths: '—',
        previousEmployer: '—',
        previousEmploymentMonths: '—',
        jobsPast36Months: '—',
        totalTimeEmployedMonths: '—',
        currentAddress: '—',
        currentAddressMonths: '—',
        previousAddress: '—',
        previousAddressMonths: '—'
    };
    caseNotes = [];
    hasUnsavedChanges = false;

    networkStatusHandler = () => {
        const wasOffline = this.offlineMode;
        this.offlineMode = !this.isBrowserOnline();
        if (wasOffline && !this.offlineMode && this.activeContextId && !this.loading && !this.hasUnsavedChanges) {
            this.syncOfflineDraft();
        }
    };

    connectedCallback() {
        this.offlineMode = !this.isBrowserOnline();
        window.addEventListener('online', this.networkStatusHandler);
        window.addEventListener('offline', this.networkStatusHandler);

        if (this.recordId) {
            this.activeRecordId = this.recordId;
            this.refreshInterview(true);
        } else {
            this.loadAssignedList();
        }
    }

    disconnectedCallback() {
        window.removeEventListener('online', this.networkStatusHandler);
        window.removeEventListener('offline', this.networkStatusHandler);
    }

    get activeContextId() {
        return this.scheduleId || this.activeRecordId || this.recordId;
    }

    get showLanding() {
        return !this.recordId && !this.activeRecordId;
    }

    get showBackToAssignments() {
        return !this.recordId && Boolean(this.activeRecordId);
    }

    get hasAssignedInterviews() {
        return this.assignedGroups.some((group) => group.rows.length > 0);
    }

    get hasConfigWarnings() {
        return this.configWarnings.length > 0;
    }

    get configWarningText() {
        return this.configWarnings.join(' ');
    }

    get showReadOnlyNotice() {
        return this.readOnly && Boolean(this.notReadyMessage);
    }

    get showOfflineNotice() {
        return this.offlineMode || this.hasOfflineDraft || Boolean(this.offlineMessage);
    }

    get showInitialLoader() {
        return this.loading;
    }

    get showActionLoader() {
        return !this.loading && (this.saving || this.syncingOffline);
    }

    get brandLogoUrl() {
        return hghLogo;
    }

    get loaderLogoUrl() {
        return hghLoaderLogo;
    }

    get connectivityBannerClass() {
        if (this.syncingOffline) return 'connectivity-banner syncing';
        if (this.offlineMode) return 'connectivity-banner offline';
        if (this.hasOfflineDraft) return 'connectivity-banner pending';
        return 'connectivity-banner';
    }

    get busyTitle() {
        if (this.loading) return 'Loading interview';
        if (this.syncingOffline) return 'Syncing offline changes';
        if (this.offlineMode) return 'Saving on this device';
        return 'Saving interview';
    }

    get busyMessage() {
        if (this.loading) return 'Getting the latest interview details...';
        if (this.syncingOffline) return 'Your offline work is being synchronized with Salesforce.';
        if (this.offlineMode) return 'No connection detected. Your changes are being stored locally.';
        return 'Please wait while your changes are saved.';
    }

    get connectionLabel() {
        if (this.syncingOffline) return 'Syncing';
        if (this.offlineMode) return 'Offline';
        if (this.hasOfflineDraft) return 'Sync pending';
        return 'Online';
    }

    get connectionClass() {
        if (this.syncingOffline) return 'connection-pill syncing';
        if (this.offlineMode) return 'connection-pill offline';
        if (this.hasOfflineDraft) return 'connection-pill pending';
        return 'connection-pill online';
    }

    get showConnectionStatusChip() {
        return this.syncingOffline || this.offlineMode || this.hasOfflineDraft;
    }

    get offlineNoticeText() {
        if (this.offlineMessage) return this.offlineMessage;
        if (this.offlineMode) return 'Offline mode: saves are stored on this device and will sync when connection returns.';
        if (this.hasOfflineDraft) return 'This device has an unsynced interview draft.';
        return '';
    }

    get isInterviewFormTab() {
        return this.activeInfoTab === 'form';
    }

    get isEmploymentTab() {
        return this.activeInfoTab === 'employment';
    }

    get isCaseNotesTab() {
        return this.activeInfoTab === 'notes';
    }

    get interviewFormTabClass() {
        return this.infoTabClass('form');
    }

    get employmentTabClass() {
        return this.infoTabClass('employment');
    }

    get caseNotesTabClass() {
        return this.infoTabClass('notes');
    }

    get hasCaseNotes() {
        return this.caseNotes.length > 0;
    }

    get contactNameDisplay() {
        return this.displayOrDash(this.intervieweeName);
    }

    get contactPhoneHref() {
        return `tel:${this.contactPhone.replace(/[^\d+]/g, '')}`;
    }

    // US numbers display as # (###) ###-####; anything else is shown as stored.
    get contactPhoneDisplay() {
        const digits = this.contactPhone.replace(/\D/g, '');
        let national = '';
        if (digits.length === 10) national = digits;
        else if (digits.length === 11 && digits.startsWith('1')) national = digits.slice(1);
        if (!national) return this.contactPhone;
        return `1 (${national.slice(0, 3)}) ${national.slice(3, 6)}-${national.slice(6)}`;
    }

    get contactEmailHref() {
        return `mailto:${this.contactEmail.trim()}`;
    }

    infoTabClass(tabName) {
        return tabName === this.activeInfoTab ? 'info-tab active' : 'info-tab';
    }

    displayOrDash(value) {
        const text = String(value ?? '').trim();
        return text || '—';
    }

    handleInfoTabChange(event) {
        const tabName = event.currentTarget?.dataset?.tab;
        if (!['form', 'employment', 'notes'].includes(tabName)) return;
        this.activeInfoTab = tabName;
    }

    get stepModels() {
        return STEPS.map((step, index) => {
            let buttonClass = 'step-button';
            if (index === this.currentStepIndex) buttonClass += ' active';
            if (index < this.currentStepIndex) buttonClass += ' complete';
            return {
                ...step,
                index,
                number: index + 1,
                buttonClass,
                showConnector: index < STEPS.length - 1,
                connectorClass: index < this.currentStepIndex ? 'step-line complete' : 'step-line'
            };
        });
    }

    get currentStep() {
        return STEPS[this.currentStepIndex];
    }

    get currentStepTitle() {
        return this.currentStep?.title || '';
    }

    get progressPercent() {
        return Math.round(((this.currentStepIndex + 1) / STEPS.length) * 100);
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%;`;
    }

    get progressPercentLabel() {
        return `${this.progressPercent}% complete`;
    }

    get currentStepSubtitle() {
        return this.currentStep?.help || '';
    }

    get isRequestStep() {
        return this.currentStepIndex <= 4;
    }

    get isNarrativeStep() {
        return this.currentStepIndex === 5;
    }

    get isCompleteStep() {
        return this.currentStepIndex === 6;
    }

    get currentSectionKey() {
        return this.isRequestStep ? this.currentStep.key : '';
    }

    get currentSectionNotes() {
        return this.sectionNotes[this.currentSectionKey] || '';
    }

    get isNewBedsStep() {
        return this.currentSectionKey === 'newBeds';
    }

    get genderOptions() {
        const orgValues = (this.genderOptionsFromOrg || []).filter((option) => option.value);
        return orgValues.length ? orgValues : [
            { label: 'Male', value: 'Male' },
            { label: 'Female', value: 'Female' }
        ];
    }

    get recommendationOptions() {
        return RECOMMENDATION_OPTIONS;
    }

    get santaOptions() {
        return [
            { label: 'No', value: 'No' },
            { label: 'Yes', value: 'Yes' }
        ];
    }

    get santaValue() {
        return this.santaInterest ? 'Yes' : 'No';
    }

    get currentRequestCards() {
        if (!this.isRequestStep) return [];
        return this.requestGroups
            .filter((group) => group.section === this.currentSectionKey)
            .map((group, index) => this.decorateGroup(group, index));
    }

    get hasCurrentRequests() {
        return this.currentRequestCards.length > 0;
    }

    get totalRequestedItems() {
        return this.flattenItems().length;
    }

    get completionStatusText() {
        return this.isChristmasCase
            ? 'Completing this Christmas interview will also set the Case Status to Home Interview Complete.'
            : 'Completing the interview will lock volunteer editing. The Case Status is not changed for non-Christmas cases.';
    }

    get saveDisabled() {
        return this.loading || this.saving || this.syncingOffline || this.readOnly || !this.interviewReady;
    }

    get previousDisabled() {
        return this.currentStepIndex === 0 || this.loading || this.saving || this.syncingOffline;
    }

    get nextDisabled() {
        return this.currentStepIndex >= STEPS.length - 1 || this.loading || this.saving || this.syncingOffline;
    }

    get formattedInterviewDate() {
        return this.formatDate(this.interviewDate);
    }

    get formattedTimeRange() {
        return this.formatTimeRange(this.startTime, this.endTime);
    }

    decorateGroup(group, index) {
        const category = group.category || '';
        const subcategoryValues = FLOW_SUBCATEGORIES[category] || [];
        const showSubcategories = subcategoryValues.length > 0;
        const showGender = category === 'Beds' || category === 'Bedding';
        const directQuantity = DIRECT_CATEGORIES.has(category);
        const classificationLocked = Boolean(group.classificationLocked || group.locked);
        const fieldsDisabled = this.saveDisabled || group.locked;
        const selectorsDisabled = fieldsDisabled || classificationLocked;
        const selected = Array.isArray(group.selectedSubcategories) ? group.selectedSubcategories : [];
        const selectedDetails = selected.map((subcategory) => {
            const detail = group.details?.[subcategory] || {};
            const quantityLocked = this.saveDisabled || detail.locked === true;
            const quantity = Number(detail.quantity || 1);
            return {
                key: `${group.key}-${subcategory}`,
                subcategory,
                label: subcategory === 'Refridgerator' ? 'Refrigerator' : subcategory,
                quantity,
                disabled: quantityLocked,
                decrementDisabled: quantityLocked || quantity <= 1
            };
        });
        const directDetail = group.details?.__direct || {};
        const categoryOptions = this.currentStep.categories.map((value) => {
            const orgOption = (this.categoryOptionsFromOrg || []).find((option) => option.value === value);
            return orgOption || { label: value, value };
        });
        const categoryChoices = categoryOptions.map((option) => ({
            ...option,
            selected: option.value === category,
            className: option.value === category ? 'choice-chip selected' : 'choice-chip',
            disabled: selectorsDisabled
        }));
        const genderChoices = this.genderOptions.map((option) => ({
            ...option,
            selected: option.value === group.gender,
            className: option.value === group.gender ? 'choice-chip selected' : 'choice-chip',
            disabled: selectorsDisabled
        }));
        const subcategoryChoices = subcategoryValues.map((value) => {
            const isSelected = selected.includes(value);
            const detail = group.details?.[value] || {};
            const quantity = Number(detail.quantity || 1);
            const detailDisabled = this.saveDisabled || detail.locked === true;
            return {
                label: value === 'Refridgerator' ? 'Refrigerator' : value,
                value,
                selected: isSelected,
                rowClass: isSelected ? 'compact-option-row selected' : 'compact-option-row',
                disabled: selectorsDisabled,
                quantity,
                detailDisabled,
                decrementDisabled: detailDisabled || quantity <= 1,
                quantityAriaLabel: `Quantity for ${value === 'Refridgerator' ? 'Refrigerator' : value}`
            };
        });
        const directQuantityValue = Number(directDetail.quantity || group.quantity || 1);
        return {
            ...group,
            displayIndex: index + 1,
            categoryOptions,
            categoryChoices,
            hasMultipleCategories: categoryChoices.length > 1,
            categoryDisplay: category === 'Small Appliance' ? 'Household / Small Appliance' : category,
            genderOptions: this.genderOptions,
            genderChoices,
            showGender,
            showSubcategories,
            subcategoryLabel: ['Beds', 'Bedding', 'Mattress Only', 'Bed Frame Only'].includes(category) ? 'Select size' : 'Select items',
            directQuantity,
            subcategoryOptions: subcategoryValues.map((value) => ({
                label: value === 'Refridgerator' ? 'Refrigerator' : value,
                value
            })),
            subcategoryChoices,
            selectedDetails,
            hasSelectedDetails: selectedDetails.length > 0,
            showOtherEntry: selected.includes('Other'),
            directQuantityValue,
            directDecrementDisabled: fieldsDisabled || directQuantityValue <= 1,
            fieldsDisabled,
            selectorsDisabled,
            removeDisabled: this.saveDisabled || group.locked || group.classificationLocked,
            statusLabel: group.status || (group.hasExisting ? 'Requested' : 'New')
        };
    }

    async loadAssignedList() {
        this.loading = true;
        this.errorMessage = '';
        this.activeRecordId = undefined;
        this.caseId = '';
        this.scheduleId = '';
        try {
            if (this.offlineMode) {
                const cached = this.getStored(`${STORAGE_PREFIX}.assigned`);
                if (!cached) throw new Error('Assigned interviews are not cached on this device.');
                this.assignedGroups = this.groupAssignedInterviews(cached);
                this.offlineMessage = 'Offline mode: showing the last cached assigned interview list.';
                return;
            }
            const rows = await loadAssignedInterviews();
            this.assignedGroups = this.groupAssignedInterviews(rows || []);
            this.setStored(`${STORAGE_PREFIX}.assigned`, rows || []);
            this.offlineMessage = '';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.loading = false;
        }
    }

    groupAssignedInterviews(rows) {
        const groups = new Map();
        (rows || []).forEach((row) => {
            const label = `${this.formatDate(row.interviewDate)}${row.scheduleMode ? ` - ${this.normalizeMode(row.scheduleMode)}` : ''}`;
            const key = `${row.interviewDate || ''}-${row.scheduleMode || ''}`;
            if (!groups.has(key)) groups.set(key, { key, label, rows: [] });
            groups.get(key).rows.push({
                ...row,
                timeLabel: this.formatTimeRange(row.startTime, row.endTime),
                statusLabel: row.assignmentStatus || 'Assigned'
            });
        });
        return Array.from(groups.values());
    }

    handleOpenAssignedInterview(event) {
        const scheduleId = event.currentTarget.dataset.scheduleId;
        if (!scheduleId) return;
        this.activeRecordId = scheduleId;
        this.openedFromLanding = true;
        this.currentStepIndex = 0;
        this.refreshInterview(true);
    }

    async handleBackToAssignments() {
        if (this.saving || this.syncingOffline) return;
        if (this.hasUnsavedChanges && !window.confirm('Leave this interview without saving the current changes?')) return;
        this.activeRecordId = undefined;
        this.openedFromLanding = false;
        await this.loadAssignedList();
    }

    async refreshInterview(resetStep = false) {
        if (this.saving || this.syncingOffline) return;
        const sequence = ++this._refreshSequence;
        const contextId = this.activeRecordId || this.recordId;
        this.loading = true;
        this.errorMessage = '';
        try {
            let data;
            if (this.offlineMode) {
                data = this.getStored(`${STORAGE_PREFIX}.interview.${contextId}`);
                if (!data) throw new Error('This interview is not cached on this device. Open it once while online first.');
            } else {
                data = await loadInterview({ recordId: contextId });
                this.requireCurrentController(data);
            }
            if (sequence !== this._refreshSequence) return;
            this.applyInterviewData(data, resetStep);
            if (!this.offlineMode) this.cacheInterview(data);

            const draft = this.loadDraft();
            this.hasOfflineDraft = Boolean(draft);
            this.draftNeedsReview = false;
            if (draft) {
                if (!this.offlineMode && !this.canAutomaticallySync(draft)) {
                    this.draftNeedsReview = true;
                    this.offlineMessage = 'A stored draft is older than this screen or conflicts with the saved recommendation. It has not been applied or sent. Review it before saving, or discard it.';
                } else {
                    this.applyOfflineDraft();
                    if (!this.offlineMode) await this.syncOfflineDraft(true);
                }
            }
        } catch (error) {
            if (sequence !== this._refreshSequence) return;
            this.errorMessage = this.reduceError(error);
            // Do not edit against a missing or incompatible server snapshot.
            this.readOnly = true;
        } finally {
            if (sequence === this._refreshSequence) this.loading = false;
        }
    }

    applyInterviewData(data, resetStep) {
        this.persistenceVersion = Number(data.persistenceVersion || 0);
        this._serverRecommendation = String(data.persistedHouseholdRecommendation || '');
        this.caseId = data.caseId || '';
        this.scheduleId = data.scheduleId || '';
        this.caseNumber = data.caseNumber || '';
        this.householdName = data.householdName || '';
        this.address = data.address || '';
        this.interviewDate = data.interviewDate;
        this.scheduleMode = data.scheduleMode || '';
        this.startTime = data.startTime;
        this.endTime = data.endTime;
        this.zoneName = data.zoneName || '';
        this.interviewerName = data.interviewerName || '';
        this.intervieweeName = data.intervieweeName || '';
        this.intervieweePhone = data.intervieweePhone || '';
        this.contactPhone = data.contactPhone || '';
        this.contactEmail = data.contactEmail || '';
        this.assignmentStatus = data.assignmentStatus || '';

        const employment = data.applicantEmployment || {};
        this.applicantEmployment = {
            applicantName: this.displayOrDash(employment.applicantName || this.intervieweeName || 'Applicant'),
            employmentStatus: this.displayOrDash(employment.employmentStatus),
            currentEmployer: this.displayOrDash(employment.currentEmployer),
            employmentLengthMonths: this.displayOrDash(employment.employmentLengthMonths),
            previousEmployer: this.displayOrDash(employment.previousEmployer),
            previousEmploymentMonths: this.displayOrDash(employment.previousEmploymentMonths),
            jobsPast36Months: this.displayOrDash(employment.jobsPast36Months),
            totalTimeEmployedMonths: this.displayOrDash(employment.totalTimeEmployedMonths),
            currentAddress: this.displayOrDash(employment.currentAddress || this.address),
            currentAddressMonths: this.displayOrDash(employment.currentAddressMonths),
            previousAddress: this.displayOrDash(employment.previousAddress),
            previousAddressMonths: this.displayOrDash(employment.previousAddressMonths)
        };
        // Exclude only the two built-in duplicates; retain genuine Enhanced Notes.
        this.caseNotes = (data.caseNotes || []).filter((note) => !REVIEW_NOTE_KEYS.has(note.key)).map((note, index) => ({
            key: note.key || `case-note-${index}`,
            label: note.label || 'Case Note',
            value: note.value || ''
        })).filter((note) => note.value);

        this.whyHelp = data.whyHelp || '';
        this.whyNotHelp = data.whyNotHelp || '';
        this.santaInterest = data.santaInterest === true;
        this.showSanta = data.showSanta === true;
        this.santaFieldAvailable = data.santaFieldAvailable !== false;
        this.whyHelpFieldAvailable = data.whyHelpFieldAvailable !== false;
        this.whyNotHelpFieldAvailable = data.whyNotHelpFieldAvailable !== false;
        this.otherBedNeeds = data.otherBedNeeds || '';
        this.householdRecommendation = String(data.householdRecommendation || '').trim();
        this.isChristmasCase = data.isChristmasCase === true;
        this.readOnly = data.readOnly === true;
        this.interviewReady = data.interviewReady === true;
        this.notReadyMessage = data.notReadyMessage || '';
        this.configWarnings = data.configWarnings || [];
        this.formFieldsAvailable = data.form2026FieldsAvailable !== false;
        this.categoryOptionsFromOrg = data.categoryOptions || [];
        this.genderOptionsFromOrg = data.genderOptions || [];
        this.sectionNotes = {
            newBeds: '', existingBedding: '', linens: '', smallAppliances: '', furniture: '', otherItems: '',
            ...(data.sectionNotes || {})
        };
        this.removedItems = [];
        this.requestGroups = (data.items || []).map((item, index) => this.groupFromLoadedItem(item, index));
        this.hasUnsavedChanges = false;
        if (resetStep) {
            this.currentStepIndex = 0;
            this.activeInfoTab = 'form';
        }
        this.hasOfflineDraft = Boolean(this.loadDraft());
    }

    groupFromLoadedItem(item, index) {
        const category = this.normalizeCategory(item.category || this.categoryForSection(item.sectionKey));
        const subcategory = this.normalizeSubcategory(item.subcategory || '');
        const entryKey = subcategory || '__direct';
        return {
            key: `existing-${item.id || index}`,
            section: item.sectionKey || this.sectionForCategory(category),
            category,
            gender: item.gender || '',
            selectedSubcategories: subcategory ? [subcategory] : [],
            customEntry: item.customEntry || '',
            details: {
                [entryKey]: {
                    id: item.id || null,
                    serviceId: item.serviceId || '',
                    clientKey: item.id || `existing-${index}`,
                    quantity: Number(item.quantity || 1),
                    locked: item.locked === true,
                    status: item.status || 'Requested'
                }
            },
            locked: item.locked === true,
            classificationLocked: Boolean(item.id && item.status && item.status !== 'Requested'),
            hasExisting: Boolean(item.id),
            status: item.status || 'Requested'
        };
    }

    categoryForSection(section) {
        const map = {
            newBeds: 'Beds', existingBedding: 'Bedding', linens: 'Pillows',
            smallAppliances: 'Small Appliance', furniture: 'Furniture'
        };
        return map[section] || '';
    }

    normalizeCategory(value) {
        const text = String(value || '').trim();
        if (text.toLowerCase() === 'small appliances') return 'Small Appliance';
        return text;
    }

    normalizeSubcategory(value) {
        const text = String(value || '').trim();
        const normalized = text.toLowerCase();
        if (normalized === 'refrigerator') return 'Refridgerator';
        if (normalized === 'bunk bed' || normalized === 'bunk-bed') return 'Bunkbed';
        if (normalized === 'kitchen table') return 'Kitchen table';
        if (normalized === 'kitchen chairs' || normalized === 'kitchen chair') return 'Kitchen chairs';
        return text;
    }

    sectionForCategory(category) {
        if (['Beds', 'Mattress Only', 'Bed Frame Only'].includes(category)) return 'newBeds';
        if (category === 'Bedding') return 'existingBedding';
        if (DIRECT_CATEGORIES.has(category)) return 'linens';
        if (category === 'Small Appliance') return 'smallAppliances';
        if (category === 'Furniture') return 'furniture';
        return 'otherItems';
    }

    handleAddRequest() {
        if (this.saveDisabled || !this.isRequestStep) return;
        const defaultCategory = this.currentStep.categories[0];
        const direct = DIRECT_CATEGORIES.has(defaultCategory);
        const key = this.newKey();
        this.requestGroups = [
            ...this.requestGroups,
            {
                key,
                section: this.currentSectionKey,
                category: defaultCategory,
                gender: '',
                selectedSubcategories: [],
                customEntry: '',
                details: direct ? {
                    __direct: { id: null, serviceId: '', clientKey: `${key}-direct`, quantity: 1, status: 'New', locked: false }
                } : {},
                locked: false,
                classificationLocked: false,
                hasExisting: false,
                status: 'New'
            }
        ];
        this.hasUnsavedChanges = true;
    }

    handleCategorySelect(event) {
        if (event.currentTarget.disabled) return;
        const key = event.currentTarget.dataset.key;
        const category = event.detail.value;
        this.changeGroupCategory(key, category);
    }

    handleGenderSelect(event) {
        if (event.currentTarget.disabled) return;
        const key = event.currentTarget.dataset.key;
        const value = event.detail.value;
        this.updateGroup(key, (group) => ({ ...group, gender: value }));
    }

    handleSubcategoryCheckboxChange(event) {
        const input = event.currentTarget;
        if (input.disabled) return;
        const key = input.dataset.key;
        const value = input.dataset.value;
        const group = this.requestGroups.find((row) => row.key === key);
        if (!group) return;
        const current = Array.isArray(group.selectedSubcategories) ? group.selectedSubcategories : [];
        const nextValues = input.checked
            ? (current.includes(value) ? current : [...current, value])
            : current.filter((entry) => entry !== value);
        this.setGroupSubcategories(key, nextValues);
    }

    handleQuantityAdjust(event) {
        if (event.currentTarget.disabled) return;
        const key = event.currentTarget.dataset.key;
        const subcategory = event.currentTarget.dataset.subcategory || '__direct';
        const action = event.currentTarget.dataset.action;
        this.updateGroup(key, (group) => {
            const existing = group.details?.[subcategory] || {};
            const current = Math.max(1, Number(existing.quantity || 1));
            const quantity = action === 'decrement' ? Math.max(1, current - 1) : current + 1;
            return {
                ...group,
                details: {
                    ...(group.details || {}),
                    [subcategory]: { ...existing, quantity }
                }
            };
        });
    }

    changeGroupCategory(key, category) {
        this.updateGroup(key, (group) => {
            if (group.classificationLocked || group.locked || group.category === category) return group;
            this.markGroupExistingForRemoval(group);
            const direct = DIRECT_CATEGORIES.has(category);
            return {
                ...group,
                category,
                section: this.sectionForCategory(category),
                gender: '',
                selectedSubcategories: [],
                customEntry: '',
                details: direct ? {
                    __direct: { id: null, serviceId: '', clientKey: `${group.key}-direct-${Date.now()}`, quantity: 1, status: 'New', locked: false }
                } : {},
                hasExisting: false,
                status: 'New'
            };
        });
    }

    setGroupSubcategories(key, nextValues) {
        this.updateGroup(key, (group) => {
            if (group.classificationLocked || group.locked) return group;
            const oldValues = group.selectedSubcategories || [];
            const removed = oldValues.filter((value) => !nextValues.includes(value));
            removed.forEach((value) => {
                const detail = group.details?.[value];
                if (detail?.id) this.addRemovedItem(detail);
            });
            const nextDetails = {};
            nextValues.forEach((value) => {
                const existing = group.details?.[value];
                nextDetails[value] = existing || {
                    id: null,
                    serviceId: '',
                    clientKey: `${group.key}-${this.keyToken(value)}-${Date.now()}`,
                    quantity: 1,
                    status: 'New',
                    locked: false
                };
            });
            return {
                ...group,
                selectedSubcategories: [...nextValues],
                details: nextDetails,
                customEntry: nextValues.includes('Other') ? group.customEntry : ''
            };
        });
    }

    handleQuantityChange(event) {
        const key = event.currentTarget.dataset.key;
        const subcategory = event.currentTarget.dataset.subcategory || '__direct';
        const quantity = Number(event.target.value);
        this.updateGroup(key, (group) => ({
            ...group,
            details: {
                ...(group.details || {}),
                [subcategory]: {
                    ...(group.details?.[subcategory] || {}),
                    quantity
                }
            }
        }));
    }

    handleOtherEntryChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.target.value;
        this.updateGroup(key, (group) => ({ ...group, customEntry: value }));
    }

    handleRemoveRequest(event) {
        const key = event.currentTarget.dataset.key;
        const group = this.requestGroups.find((row) => row.key === key);
        if (!group || group.locked || group.classificationLocked) return;
        this.markGroupExistingForRemoval(group);
        this.requestGroups = this.requestGroups.filter((row) => row.key !== key);
        this.hasUnsavedChanges = true;
    }

    updateGroup(key, updater) {
        this.requestGroups = this.requestGroups.map((group) => group.key === key ? updater(group) : group);
        this.hasUnsavedChanges = true;
    }

    markGroupExistingForRemoval(group) {
        Object.values(group.details || {}).forEach((detail) => {
            if (detail?.id) this.addRemovedItem(detail);
        });
    }

    addRemovedItem(detail) {
        if (!detail?.id) return;
        if (!this.removedItems.some((row) => row.id === detail.id)) {
            this.removedItems = [...this.removedItems, { id: detail.id, clientKey: detail.clientKey || detail.id }];
        }
    }

    handleSectionNotesChange(event) {
        this.sectionNotes = { ...this.sectionNotes, [this.currentSectionKey]: event.target.value };
        this.hasUnsavedChanges = true;
    }

    handleOtherBedNeedsChange(event) {
        this.otherBedNeeds = event.target.value;
        this.hasUnsavedChanges = true;
    }

    handleRecommendationChange(event) {
        if (this.saveDisabled) return;
        this.householdRecommendation = String(event.detail?.value || '').trim();
        this.hasUnsavedChanges = true;
        this.errorMessage = '';
    }

    handleWhyHelpChange(event) {
        this.whyHelp = event.target.value;
        this.hasUnsavedChanges = true;
    }

    handleWhyNotHelpChange(event) {
        this.whyNotHelp = event.target.value;
        this.hasUnsavedChanges = true;
    }

    handleSantaChange(event) {
        this.santaInterest = event.detail.value === 'Yes';
        this.hasUnsavedChanges = true;
    }

    async handleStepClick(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (Number.isInteger(index)) await this.navigateToStep(index);
    }

    async handlePrevious() {
        await this.navigateToStep(this.currentStepIndex - 1);
    }

    async handleNext() {
        await this.navigateToStep(this.currentStepIndex + 1);
    }

    async navigateToStep(index) {
        const target = Math.max(0, Math.min(index, STEPS.length - 1));
        if (target === this.currentStepIndex || this.loading || this.saving || this.syncingOffline) return;
        if (!this.readOnly && this.interviewReady) {
            this.captureRecommendationInput();
            const enteringComplete = target === STEPS.length - 1;
            if (enteringComplete && !this.householdRecommendation) {
                this.showToast('Recommendation Required', 'Select the interviewer recommendation on Review before continuing.', 'error');
                return;
            }
            // The final summary must be based on an acknowledged save, not a
            // possibly stale dirty flag or a client-only fallback value.
            if (this.hasUnsavedChanges || enteringComplete) {
                const saved = await this.persist(false, false);
                if (!saved) return;
            }
        }
        this.currentStepIndex = target;
        this.scrollToWizard();
    }

    async handleSaveDraft() {
        await this.persist(false, true);
    }

    async handleSaveExit() {
        const saved = await this.persist(false, true);
        if (saved && this.openedFromLanding) await this.handleBackToAssignments();
    }

    async handleComplete() {
        await this.persist(true, true);
    }

    handleRefresh() {
        if (this.saving || this.syncingOffline) return;
        if (this.hasUnsavedChanges && !window.confirm('Reload and discard unsaved changes?')) return;
        this.refreshInterview(false);
    }

    flattenItems() {
        const result = [];
        this.requestGroups.forEach((group) => {
            const category = group.category || '';
            if (DIRECT_CATEGORIES.has(category)) {
                const detail = group.details?.__direct || {};
                result.push(this.itemPayload(group, '', detail));
                return;
            }
            (group.selectedSubcategories || []).forEach((subcategory) => {
                const detail = group.details?.[subcategory] || {};
                result.push(this.itemPayload(group, subcategory, detail));
            });
        });
        return result;
    }

    itemPayload(group, subcategory, detail) {
        return {
            id: detail.id || null,
            clientKey: detail.clientKey || `${group.key}-${this.keyToken(subcategory || 'direct')}`,
            serviceId: detail.serviceId || '',
            section: group.section,
            category: group.category || '',
            subcategory: subcategory || '',
            gender: (group.category === 'Beds' || group.category === 'Bedding') ? (group.gender || '') : '',
            customEntry: subcategory === 'Other' ? (group.customEntry || '') : '',
            quantity: Number(detail.quantity || 1),
            recommendation: this.householdRecommendation || 'Neutral'
        };
    }

    buildSavePayload(completeInterview) {
        return {
            recordId: this.activeContextId,
            itemsJson: JSON.stringify(this.flattenItems()),
            sectionNotesJson: JSON.stringify({
                ...this.sectionNotes,
                __form2026: {
                    version: PERSISTENCE_VERSION,
                    expectedRecommendation: this._serverRecommendation,
                    otherBedNeeds: this.otherBedNeeds,
                    householdRecommendation: this.householdRecommendation,
                    removedItems: this.removedItems
                }
            }),
            whyHelp: this.whyHelp,
            whyNotHelp: this.whyNotHelp,
            santaInterest: this.showSanta && this.santaFieldAvailable ? this.santaInterest : null,
            completeInterview
        };
    }

    validate(completing) {
        if (!this.formFieldsAvailable) {
            this.showToast('Configuration Required', 'Service Delivery Other Bed Needs field is not available.', 'error');
            return false;
        }

        const groupsToValidate = completing
            ? this.requestGroups
            : this.requestGroups.filter((group) => group.section === this.currentSectionKey);

        for (const group of groupsToValidate) {
            if (!group.category) {
                this.showToast('Category Required', 'Choose a Category for every request.', 'error');
                return false;
            }
            if ((group.category === 'Beds' || group.category === 'Bedding') && !group.gender) {
                this.showToast('Gender Required', `Choose Gender for ${group.category}.`, 'error');
                return false;
            }
            if (!DIRECT_CATEGORIES.has(group.category) && !(group.selectedSubcategories || []).length) {
                this.showToast('Subcategory Required', `Select at least one item for ${group.category}.`, 'error');
                return false;
            }
            if ((group.selectedSubcategories || []).includes('Other') && !(group.customEntry || '').trim()) {
                this.showToast('Other Item Required', 'Enter the requested item when Other is selected.', 'error');
                return false;
            }
            for (const detail of Object.values(group.details || {})) {
                const quantity = Number(detail.quantity);
                if (!Number.isInteger(quantity) || quantity <= 0) {
                    this.showToast('Quantity Required', 'Every requested item needs a positive whole-number quantity.', 'error');
                    return false;
                }
            }
        }

        if ((completing || this.isNewBedsStep) && this.otherBedNeeds.length > 32768) {
            this.showToast('Other Bed Needs Too Long', 'Other Bed Needs must be 32,768 characters or fewer.', 'error');
            return false;
        }
        if (completing && this.otherBedNeeds.trim() && this.flattenItems().length === 0) {
            this.showToast('Requested Item Required', 'Add at least one requested item before completing the interview.', 'error');
            return false;
        }
        if (completing && !this.householdRecommendation) {
            this.showToast('Recommendation Required', 'Select the interviewer recommendation before completing the interview.', 'error');
            return false;
        }
        return true;
    }

    async persist(completing, showSuccess) {
        if (this.saveDisabled) return false;
        this.captureRecommendationInput();
        if (!this.validate(completing)) return false;
        if (!this.offlineMode && this.persistenceVersion < PERSISTENCE_VERSION) {
            this.errorMessage = 'The matching controller update is not deployed. Deploy the controller and LWC together, then reload this page. Validation alone does not deploy code.';
            this.showToast('Deployment Required', this.errorMessage, 'error');
            return false;
        }

        this.saving = true;
        this.errorMessage = '';
        const payload = this.buildSavePayload(completing);
        const contextId = this.activeContextId;
        try {
            this.draftNeedsReview = false;
            this.saveDraftLocally(payload);
            if (this.offlineMode) {
                this.hasUnsavedChanges = false;
                this.offlineMessage = completing
                    ? 'Interview completion is queued on this device and will sync when online.'
                    : 'Interview draft is saved on this device and will sync when online.';
                if (completing) {
                    this.readOnly = true;
                    this.assignmentStatus = 'Pending Sync';
                    this.notReadyMessage = 'Completion is queued on this device. Editing is locked until synchronization completes.';
                }
                if (showSuccess) this.showToast(completing ? 'Completion Queued' : 'Draft Saved Offline', this.offlineMessage, 'success');
                return true;
            }

            const result = await saveInterview(payload);
            this.acceptSavedInterview(result, payload, contextId);
            if (showSuccess) {
                this.showToast(
                    completing ? 'Interview Completed' : 'Draft Saved',
                    completing ? 'The interview has been completed successfully.' : 'Interview responses were saved.',
                    'success'
                );
            }
            return true;
        } catch (error) {
            this.hasOfflineDraft = Boolean(this.loadDraft());
            this.draftNeedsReview = this.hasOfflineDraft;
            this.errorMessage = this.reduceError(error);
            this.offlineMessage = this.hasOfflineDraft ? 'Your unsaved draft is retained on this device. Review the error before retrying.' : '';
            this.showToast('Save Failed', this.errorMessage, 'error');
            return false;
        } finally {
            this.saving = false;
        }
    }

    saveDraftLocally(payload) {
        const state = {
            schemaVersion: PERSISTENCE_VERSION,
            payload,
            requestGroups: this.requestGroups,
            removedItems: this.removedItems,
            sectionNotes: this.sectionNotes,
            otherBedNeeds: this.otherBedNeeds,
            householdRecommendation: this.householdRecommendation,
            whyHelp: this.whyHelp,
            whyNotHelp: this.whyNotHelp,
            santaInterest: this.santaInterest,
            currentStepIndex: this.currentStepIndex
        };
        this.setStored(this.draftKey(), state);
        this.hasOfflineDraft = true;
    }

    loadDraft() {
        const key = this.draftKey();
        return key ? this.getStored(key) : null;
    }

    applyOfflineDraft() {
        const draft = this.loadDraft();
        this.hasOfflineDraft = Boolean(draft);
        if (!draft) return;
        this.requestGroups = draft.requestGroups || this.requestGroups;
        this.removedItems = draft.removedItems || [];
        this.sectionNotes = { ...this.sectionNotes, ...(draft.sectionNotes || {}) };
        this.otherBedNeeds = draft.otherBedNeeds ?? this.otherBedNeeds;
        this.householdRecommendation = draft.householdRecommendation ?? this.householdRecommendation;
        this.whyHelp = draft.whyHelp ?? this.whyHelp;
        this.whyNotHelp = draft.whyNotHelp ?? this.whyNotHelp;
        this.santaInterest = draft.santaInterest ?? this.santaInterest;
        this.currentStepIndex = Number.isInteger(draft.currentStepIndex) ? draft.currentStepIndex : this.currentStepIndex;
        this.hasUnsavedChanges = true;
    }

    async syncOfflineDraft(fromRefresh = false) {
        const draft = this.loadDraft();
        if (!draft?.payload || this.offlineMode || this.saving || this.syncingOffline ||
            this.draftNeedsReview || (this.loading && !fromRefresh) ||
            (this.hasUnsavedChanges && !fromRefresh)) return;
        if (this.persistenceVersion < PERSISTENCE_VERSION || !this.canAutomaticallySync(draft)) {
            this.draftNeedsReview = true;
            this.offlineMessage = 'This draft needs review against the latest saved interview before it can be synchronized.';
            return;
        }
        this.syncingOffline = true;
        const contextId = this.activeContextId;
        try {
            const result = await saveInterview(draft.payload);
            this.acceptSavedInterview(result, draft.payload, contextId);
            this.offlineMessage = 'The queued offline interview changes were synchronized.';
            this.showToast('Offline Draft Synced', 'Queued interview changes were saved to Salesforce.', 'success');
        } catch (error) {
            this.draftNeedsReview = true;
            this.offlineMessage = `Offline draft is still pending: ${this.reduceError(error)}`;
        } finally {
            this.syncingOffline = false;
        }
    }

    async handleDiscardLocalDraft() {
        if (!this.hasOfflineDraft || this.loading || this.saving || this.syncingOffline) return;
        if (!window.confirm('Discard this device\'s unsynced interview draft?')) return;
        this.clearDraft();
        await this.refreshInterview(false);
    }

    draftKey() {
        const id = this.activeContextId;
        return id ? `${STORAGE_PREFIX}.draft.${id}` : '';
    }

    clearDraft() {
        const key = this.draftKey();
        if (key) this.removeStored(key);
        this.hasOfflineDraft = false;
        this.draftNeedsReview = false;
        this.offlineMessage = '';
    }

    get recommendationDisplay() {
        return this.householdRecommendation || 'Not selected';
    }

    captureRecommendationInput() {
        const input = this.template.querySelector('[data-field="householdRecommendation"]');
        if (!input || input.disabled) return;
        const value = String(input.value || '').trim();
        if (value !== this.householdRecommendation) {
            this.householdRecommendation = value;
            this.hasUnsavedChanges = true;
        }
    }

    requireCurrentController(data) {
        if (!data || Number(data.persistenceVersion || 0) < PERSISTENCE_VERSION) {
            throw new Error('The matching Home Interview controller is not deployed. Deploy the controller and LWC together, then reload. A successful validation is not a deployment.');
        }
    }

    acceptSavedInterview(result, payload, contextId) {
        if (!result || result.success !== true) throw new Error('Salesforce did not confirm the interview save. Your draft was retained.');
        this.requireCurrentController(result);
        this.requireCurrentController(result.interview);
        const requested = JSON.parse(payload.sectionNotesJson).__form2026;
        const persisted = String(result.persistedHouseholdRecommendation || '');
        if (persisted !== String(requested.householdRecommendation || '').trim() ||
            String(result.interview.persistedHouseholdRecommendation || '') !== persisted) {
            throw new Error('The saved recommendation does not match your selection. Your draft was retained; check Case automation and the deployed controller version.');
        }
        if (this.activeContextId !== contextId) {
            throw new Error('The interview context changed during save. Reload the correct Case before retrying.');
        }
        this.applyInterviewData(result.interview, false);
        this.cacheInterview(result.interview);
        this.clearDraft();
        this.errorMessage = '';
        const records = [result.caseId, result.scheduleId].filter(Boolean).map((recordId) => ({ recordId }));
        // A Lightning Data Service refresh is a UI notification, not a second save.
        Promise.resolve().then(() => notifyRecordUpdateAvailable(records)).catch(() => {});
    }

    cacheInterview(data) {
        const ids = new Set([data.caseId, data.scheduleId, this.activeRecordId, this.recordId].filter(Boolean));
        ids.forEach((id) => this.setStored(`${STORAGE_PREFIX}.interview.${id}`, data));
    }

    canAutomaticallySync(draft) {
        const localCompletion = draft?.payload?.completeInterview === true && this.assignmentStatus === 'Pending Sync';
        if ((this.readOnly && !localCompletion) || !this.interviewReady || Number(draft?.schemaVersion || 0) < PERSISTENCE_VERSION) return false;
        try {
            const form = JSON.parse(draft.payload.sectionNotesJson).__form2026;
            return form && Object.prototype.hasOwnProperty.call(form, 'expectedRecommendation') &&
                String(form.expectedRecommendation || '') === this._serverRecommendation;
        } catch (error) {
            return false;
        }
    }

    handleReviewLocalDraft() {
        if (this.saveDisabled || !this.hasOfflineDraft) return;
        this.applyOfflineDraft();
        this.activeInfoTab = 'form';
        this.currentStepIndex = 5;
        this.draftNeedsReview = true; // Only an explicit Save may replace the old payload.
        this.offlineMessage = 'Local draft loaded for review only. Check the recommendation, then select Save Draft to submit it against the latest Case.';
    }

    isBrowserOnline() {
        return typeof navigator === 'undefined' || navigator.onLine !== false;
    }

    getStored(key) {
        if (!key) return null;
        try {
            const raw = window.localStorage.getItem(key);
            return raw ? JSON.parse(raw) : null;
        } catch (error) {
            return null;
        }
    }

    setStored(key, value) {
        if (!key) return;
        try {
            window.localStorage.setItem(key, JSON.stringify(value));
        } catch (error) {
            // Local storage is optional while online.
        }
    }

    removeStored(key) {
        if (!key) return;
        try {
            window.localStorage.removeItem(key);
        } catch (error) {
            // Ignore cleanup failures.
        }
    }

    scrollToWizard() {
        window.requestAnimationFrame(() => {
            const target = this.template.querySelector('.section-header') || this.template.querySelector('.step-strip');
            target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        });
    }

    newKey() {
        return `req-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    }

    keyToken(value) {
        return String(value || 'item').toLowerCase().replace(/[^a-z0-9]+/g, '-');
    }

    normalizeMode(value) {
        return (value || '').replace('AfterNoon', 'Afternoon');
    }

    formatDate(value) {
        if (!value) return '';
        try {
            return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(`${value}T00:00:00`));
        } catch (error) {
            return String(value);
        }
    }

    formatTimeRange(start, end) {
        const format = (value) => {
            if (value === null || value === undefined || value === '') return '';

            const text = String(value).trim();
            let hours;
            let minutes;

            // Salesforce Time values can arrive from Apex as milliseconds since midnight
            // (for example 30600000 = 8:30 AM).
            if (/^\d+(?:\.\d+)?$/.test(text)) {
                const milliseconds = Number(text);
                if (!Number.isFinite(milliseconds)) return text;
                const dayMilliseconds = 24 * 60 * 60 * 1000;
                const normalized = ((milliseconds % dayMilliseconds) + dayMilliseconds) % dayMilliseconds;
                hours = Math.floor(normalized / 3600000);
                minutes = Math.floor((normalized % 3600000) / 60000);
            } else {
                const match = text.match(/^(\d{1,2}):(\d{2})/);
                if (!match) return text;
                hours = Number(match[1]);
                minutes = Number(match[2]);
            }

            if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return text;

            const suffix = hours >= 12 ? 'PM' : 'AM';
            const displayHour = hours % 12 || 12;
            return `${displayHour}:${String(minutes).padStart(2, '0')} ${suffix}`;
        };

        const startText = format(start);
        const endText = format(end);
        return startText && endText ? `${startText} - ${endText}` : (startText || endText || '');
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}