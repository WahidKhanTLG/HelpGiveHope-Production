import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadAssignedInterviews from '@salesforce/apex/InHomeInterviewMobileController.loadAssignedInterviews';
import loadInterview from '@salesforce/apex/InHomeInterviewMobileController.loadInterview';
import saveInterview from '@salesforce/apex/InHomeInterviewMobileController.saveInterview';

const OFFLINE_INTERVIEW_PREFIX = 'hghHomeInterview.offline.interview.';
const OFFLINE_ASSIGNED_LIST_KEY = 'hghHomeInterview.offline.assignedList';
const OFFLINE_DRAFT_PREFIX = 'hghHomeInterview.offline.draft.';

const BASE_SECTIONS = [
    {
        key: 'newBeds',
        label: 'New Bed Needs',
        shortLabel: 'Bed Needs',
        helpText: 'Select bed type, quantity, gender when applicable, and volunteer recommendation.'
    },
    {
        key: 'existingBedding',
        label: 'Existing Bed / Bedding',
        shortLabel: 'Bedding',
        helpText: 'Capture bedding type or size and quantity using the existing PMM catalog.'
    },
    {
        key: 'linens',
        label: 'Pillows / Towels / Washcloths',
        shortLabel: 'Linens',
        helpText: 'Capture pillows, towels, and washcloth quantities from the existing questionnaire catalog.'
    },
    {
        key: 'smallAppliances',
        label: 'Small Appliances',
        shortLabel: 'Appliances',
        helpText: 'Add each requested small appliance from the existing PMM catalog.'
    },
    {
        key: 'furniture',
        label: 'Furniture / Large Appliances',
        shortLabel: 'Furniture',
        helpText: 'Add each requested furniture or large-appliance item from the existing PMM catalog.'
    },
    {
        key: 'otherItems',
        label: 'Other Requested Items',
        shortLabel: 'Other',
        helpText: 'Capture any additional PMM catalog items that do not belong to the standard sections.'
    }
];

export default class InHomeInterviewMobile extends LightningElement {
    @api recordId;

    loading = true;
    saving = false;
    errorMessage;
    offlineMode = false;
    hasOfflineDraft = false;
    offlineMessage = '';

    caseId = '';
    scheduleId = '';

    activeRecordId;
    openedFromLanding = false;
    assignedGroups = [];

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
    assignmentStatus = '';

    whyHelp = '';
    whyNotHelp = '';
    santaInterest = false;
    whyHelpFieldAvailable = true;
    whyNotHelpFieldAvailable = true;
    santaFieldAvailable = true;
    showSanta = false;

    readOnly = false;
    interviewReady = false;
    isSystemAdministrator = false;
    notReadyMessage = '';
    configWarnings = [];

    serviceOptions = [];
    items = [];
    sectionNotes = {
        newBeds: '',
        existingBedding: '',
        linens: '',
        smallAppliances: '',
        furniture: '',
        otherItems: ''
    };

    currentStepIndex = 0;

    showAddItemModal = false;
    modalSectionKey;
    draftItem = { serviceId: '', quantity: 1, recommendation: 'Neutral', gender: '' };
    modalViewportStyle = '';
    modalLockApplied = false;
    previousBodyOverflow = '';
    previousDocumentOverflow = '';
    previousBodyTouchAction = '';
    previousDocumentTouchAction = '';
    modalPositionHandler = () => {
        if (this.showAddItemModal) {
            this.updateModalViewportStyle();
        }
    };

    networkStatusHandler = () => {
        const wasOffline = this.offlineMode;
        this.updateNetworkStatus();

        if (wasOffline && !this.offlineMode) {
            this.syncOfflineDraftIfAvailable();
        }
    };

    recommendationOptions = [
        { label: 'Strongly Recommend', value: 'Strongly Recommend' },
        { label: 'Recommend', value: 'Recommend' },
        { label: 'Neutral', value: 'Neutral' },
        { label: 'Concerns', value: 'Concerns' },
        { label: 'Do Not Recommend', value: 'Do Not Recommend' }
    ];

    connectedCallback() {
        this.updateNetworkStatus();
        window.addEventListener('online', this.networkStatusHandler);
        window.addEventListener('offline', this.networkStatusHandler);

        if (this.recordId) {
            this.activeRecordId = this.recordId;
            this.openedFromLanding = false;
            this.currentStepIndex = 0;
            this.refreshInterview(true);
        } else {
            this.loadAssignedList();
        }

        if (!this.offlineMode) {
            this.syncOfflineDraftIfAvailable();
        }
    }

    renderedCallback() {
        if (this.showAddItemModal) {
            this.updateModalViewportStyle();
        }
    }

    disconnectedCallback() {
        window.removeEventListener('online', this.networkStatusHandler);
        window.removeEventListener('offline', this.networkStatusHandler);
        this.releaseModalViewportLock();
    }

    newDraftItem() {
        return {
            serviceId: '',
            quantity: 1,
            recommendation: 'Neutral',
            gender: ''
        };
    }

    async loadAssignedList() {
        this.loading = true;
        this.errorMessage = undefined;
        this.activeRecordId = undefined;
        this.currentStepIndex = 0;

        try {
            if (this.offlineMode) {
                const cachedRows = this.loadCachedAssignedInterviews();
                if (!cachedRows) {
                    throw new Error('Assigned interview list is not available offline. Open the list once while online before using airplane mode.');
                }
                this.assignedGroups = this.groupAssignedInterviews(cachedRows || []);
                this.offlineMessage = 'Offline mode: showing the last cached assigned interview list.';
                return;
            }

            const rows = await loadAssignedInterviews();
            this.assignedGroups = this.groupAssignedInterviews(rows || []);
            this.cacheAssignedInterviews(rows || []);
            this.offlineMessage = '';
        } catch (error) {
            const cachedRows = this.loadCachedAssignedInterviews();
            if (cachedRows) {
                this.assignedGroups = this.groupAssignedInterviews(cachedRows || []);
                this.offlineMessage = 'Offline mode: showing the last cached assigned interview list.';
            } else {
                this.errorMessage = this.reduceError(error);
            }
        } finally {
            this.loading = false;
        }
    }

    groupAssignedInterviews(rows) {
        const groups = new Map();

        rows.forEach((row) => {
            const dateLabel = this.formatDate(row.interviewDate);
            const mode = this.normalizeMode(row.scheduleMode);
            const key = `${String(row.interviewDate || '')}-${mode}`;

            if (!groups.has(key)) {
                groups.set(key, {
                    key,
                    label: `${dateLabel}${mode ? ` - ${mode}` : ''}`,
                    rows: []
                });
            }

            groups.get(key).rows.push({
                ...row,
                timeLabel: this.formatTimeRange(row.startTime, row.endTime),
                statusLabel: row.assignmentStatus || 'Assigned'
            });
        });

        return Array.from(groups.values());
    }

    async refreshInterview(resetStep = false) {
        this.loading = true;
        this.errorMessage = undefined;

        try {
            const contextId = this.activeRecordId || this.recordId;

            if (this.offlineMode) {
                const cachedData = this.loadCachedInterviewData(contextId);
                if (!cachedData) {
                    throw new Error('This interview is not available offline yet. Open this interview once while online, then try airplane mode again.');
                }
                this.applyInterviewData(cachedData, resetStep);
                this.applyQueuedOfflineDraft();
                this.offlineMessage = 'Offline mode: using cached interview data. Saves will queue on this device until connection returns.';
                return;
            }

            const data = await loadInterview({ recordId: contextId });
            this.cacheInterviewData(data, contextId);
            this.applyInterviewData(data, resetStep);
            this.applyQueuedOfflineDraft();
            this.offlineMessage = '';
        } catch (error) {
            const cachedData = this.loadCachedInterviewData(this.activeRecordId || this.recordId);
            if (cachedData) {
                this.applyInterviewData(cachedData, resetStep);
                this.applyQueuedOfflineDraft();
                this.offlineMessage = 'Offline mode: using cached interview data. Saves will queue on this device until connection returns.';
            } else {
                this.errorMessage = this.reduceError(error);
            }
        } finally {
            this.loading = false;
        }
    }

    async refreshInterviewSilently() {
        if (this.offlineMode) {
            const cachedData = this.loadCachedInterviewData(this.activeRecordId || this.recordId);
            if (cachedData) {
                this.applyInterviewData(cachedData, false);
                this.applyQueuedOfflineDraft();
            }
            return;
        }

        const data = await loadInterview({ recordId: this.activeRecordId || this.recordId });
        this.cacheInterviewData(data, this.activeRecordId || this.recordId);
        this.applyInterviewData(data, false);
        this.applyQueuedOfflineDraft();
    }

    applyInterviewData(data, resetStep) {
        this.caseId = data.caseId || this.caseId || '';
        this.scheduleId = data.scheduleId || this.scheduleId || '';
        this.hasOfflineDraft = Boolean(this.loadOfflineDraft());
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
        this.assignmentStatus = data.assignmentStatus || '';
        this.whyHelp = data.whyHelp || '';
        this.whyNotHelp = data.whyNotHelp || '';
        this.santaInterest = data.santaInterest === true;
        this.whyHelpFieldAvailable = data.whyHelpFieldAvailable !== false;
        this.whyNotHelpFieldAvailable = data.whyNotHelpFieldAvailable !== false;
        this.santaFieldAvailable = data.santaFieldAvailable !== false;
        this.showSanta = data.showSanta === true;
        this.readOnly = data.readOnly === true;
        this.interviewReady = data.interviewReady === true;
        this.isSystemAdministrator = data.isSystemAdministrator === true;
        this.notReadyMessage = data.notReadyMessage || '';
        this.configWarnings = data.configWarnings || [];
        this.serviceOptions = data.serviceOptions || [];
        this.sectionNotes = {
            newBeds: '',
            existingBedding: '',
            linens: '',
            smallAppliances: '',
            furniture: '',
            otherItems: '',
            ...(data.sectionNotes || {})
        };

        this.items = (data.items || []).map((item, index) => this.decorateItem({
            ...item,
            clientKey: item.id || `existing-${index}`,
            section: item.sectionKey || this.inferSection(item.serviceName),
            quantity: item.quantity || 1,
            recommendation: item.recommendation || 'Neutral'
        }));

        if (resetStep) {
            this.currentStepIndex = 0;
        } else if (this.currentStepIndex >= this.totalSteps) {
            this.currentStepIndex = Math.max(this.totalSteps - 1, 0);
        }
    }

    decorateItem(item) {
        const section = item.section || item.sectionKey || this.currentSectionKey || 'otherItems';
        const isNew = !item.id;
        const showGender = this.sectionUsesGender(section);
        const gender = item.gender || '';
        const serviceOptions = this.getServiceOptionsForItem(section, gender);
        const selectedService = this.serviceOptions.find((option) => option.value === item.serviceId);
        const serviceName = selectedService?.label || item.serviceName || '';

        return {
            ...item,
            section,
            serviceName,
            recommendation: item.recommendation || 'Neutral',
            quantity: item.quantity || 1,
            gender,
            hasGender: Boolean(gender),
            isNew,
            showRemove: isNew && !this.readOnly,
            showGender,
            genderOptions: this.getGenderOptionsForSection(section),
            serviceOptions,
            itemTitle: serviceName || 'New Requested Item'
        };
    }

    sectionUsesGender(sectionKey) {
        if (!['newBeds', 'existingBedding'].includes(sectionKey)) {
            return false;
        }
        return this.serviceOptions.some(
            (option) => option.sectionKey === sectionKey && option.gender
        );
    }

    getGenderOptionsForSection(sectionKey) {
        const values = new Set(
            this.serviceOptions
                .filter((option) => option.sectionKey === sectionKey && option.gender)
                .map((option) => option.gender)
        );
        return Array.from(values).sort().map((value) => ({ label: value, value }));
    }

    getServiceOptionsForItem(sectionKey, gender) {
        let filtered = this.serviceOptions.filter(
            (option) => option.sectionKey === sectionKey
        );

        if (this.sectionUsesGender(sectionKey) && gender) {
            filtered = filtered.filter(
                (option) => !option.gender || option.gender === gender
            );
        }

        return filtered;
    }

    get showLanding() {
        return !this.recordId && !this.activeRecordId;
    }

    get hasAssignedInterviews() {
        return this.assignedGroups.some((group) => group.rows.length > 0);
    }

    get showBackToAssignments() {
        return !this.recordId && Boolean(this.activeRecordId);
    }

    get totalSteps() {
        return BASE_SECTIONS.length + 2;
    }

    get narrativeStepIndex() {
        return BASE_SECTIONS.length;
    }

    get completeStepIndex() {
        return BASE_SECTIONS.length + 1;
    }

    get stepModels() {
        const steps = BASE_SECTIONS.map((section, index) => this.buildStepModel({
            index,
            key: section.key,
            caption: section.shortLabel,
            title: section.label
        }));

        steps.push(this.buildStepModel({
            index: this.narrativeStepIndex,
            key: 'narratives',
            caption: 'Narratives',
            title: 'Why Help / Why Not Help'
        }));

        steps.push(this.buildStepModel({
            index: this.completeStepIndex,
            key: 'complete',
            caption: 'Complete',
            title: 'Complete Interview'
        }));

        return steps.map((step, index) => ({
            ...step,
            showConnector: index < steps.length - 1,
            connectorClass: index < this.currentStepIndex ? 'step-connector step-connector-complete' : 'step-connector'
        }));
    }

    buildStepModel({ index, key, caption, title }) {
        let buttonClass = 'step-button';
        if (index === this.currentStepIndex) {
            buttonClass += ' step-button-active';
        } else if (index < this.currentStepIndex) {
            buttonClass += ' step-button-complete';
        }

        return {
            index,
            key,
            number: index + 1,
            caption,
            title,
            buttonClass,
            disabled: this.saving
        };
    }

    get isSectionStep() {
        return this.currentStepIndex < BASE_SECTIONS.length;
    }

    get isNarrativeStep() {
        return this.currentStepIndex === this.narrativeStepIndex;
    }

    get isCompleteStep() {
        return this.currentStepIndex === this.completeStepIndex;
    }

    get currentSection() {
        return this.isSectionStep ? BASE_SECTIONS[this.currentStepIndex] : null;
    }

    get currentSectionKey() {
        return this.currentSection?.key || '';
    }

    get currentSectionItems() {
        if (!this.currentSectionKey) {
            return [];
        }
        return this.items.filter((item) => item.section === this.currentSectionKey);
    }

    get hasCurrentSectionItems() {
        return this.currentSectionItems.length > 0;
    }

    get currentStepTitle() {
        if (this.isSectionStep) {
            return this.currentSection.label;
        }
        if (this.isNarrativeStep) {
            return 'Family Narratives';
        }
        return 'Complete Interview';
    }

    get currentStepSubtitle() {
        if (this.isSectionStep) {
            return this.currentSection.helpText;
        }
        if (this.isNarrativeStep) {
            return 'Capture Why Help and Why Not Help together before completing the interview.';
        }
        return 'Confirm the interview is ready, then complete it to lock volunteer editing.';
    }

    get currentStepCounter() {
        return `Step ${this.currentStepIndex + 1} of ${this.totalSteps}`;
    }

    get currentSectionNotes() {
        if (!this.currentSectionKey) {
            return '';
        }
        return this.sectionNotes[this.currentSectionKey] || '';
    }

    get canAddAnotherItem() {
        return this.isSectionStep && !this.readOnly;
    }

    get showOfflineNotice() {
        return this.offlineMode || this.hasOfflineDraft || Boolean(this.offlineMessage);
    }

    get offlineNoticeText() {
        if (this.offlineMessage) {
            return this.offlineMessage;
        }
        if (this.hasOfflineDraft) {
            return 'Offline draft is stored on this device and will sync when connection returns.';
        }
        if (this.offlineMode) {
            return 'Offline mode: cached interview data is available. Saves will queue on this device until connection returns.';
        }
        return '';
    }

    get formattedInterviewDate() {
        return this.formatDate(this.interviewDate);
    }

    get formattedTimeRange() {
        const time = this.formatTimeRange(this.startTime, this.endTime);
        const mode = this.normalizeMode(this.scheduleMode);
        return `${mode ? `${mode}${time ? ' - ' : ''}` : ''}${time}`;
    }

    get narrativesReadOnly() {
        return this.readOnly || !this.whyHelpFieldAvailable || !this.whyNotHelpFieldAvailable;
    }

    get santaReadOnly() {
        return this.readOnly || !this.santaFieldAvailable;
    }

    get previousDisabled() {
        return this.currentStepIndex === 0 || this.saving;
    }

    get nextDisabled() {
        return this.currentStepIndex >= this.completeStepIndex || this.saving;
    }

    get saveDisabled() {
        return !this.interviewReady || this.readOnly || this.saving;
    }

    get showReadOnlyNotice() {
        return this.readOnly && Boolean(this.notReadyMessage);
    }

    get hasConfigWarnings() {
        return this.configWarnings.length > 0;
    }

    get configWarningText() {
        return this.configWarnings.join(' ');
    }

    get modalServiceOptions() {
        let filtered = this.serviceOptions;

        if (this.modalSectionKey) {
            filtered = this.serviceOptions.filter(
                (option) => option.sectionKey === this.modalSectionKey
            );
        }

        if (this.showDraftGender && this.draftItem.gender) {
            filtered = filtered.filter(
                (option) => !option.gender || option.gender === this.draftItem.gender
            );
        }

        return filtered;
    }

    get hasModalServiceOptions() {
        return this.modalServiceOptions.length > 0;
    }

    get showDraftGender() {
        if (!['newBeds', 'existingBedding'].includes(this.modalSectionKey)) {
            return false;
        }
        return this.serviceOptions.some(
            (option) => option.sectionKey === this.modalSectionKey && option.gender
        );
    }

    get genderOptions() {
        const values = new Set(
            this.serviceOptions
                .filter((option) => option.sectionKey === this.modalSectionKey && option.gender)
                .map((option) => option.gender)
        );
        return Array.from(values).sort().map((value) => ({ label: value, value }));
    }

    get modalSectionLabel() {
        return BASE_SECTIONS.find((section) => section.key === this.modalSectionKey)?.label || 'Requested Items';
    }

    handleOpenAssignedInterview(event) {
        this.activeRecordId = event.currentTarget.dataset.scheduleId;
        this.openedFromLanding = true;
        this.currentStepIndex = 0;
        this.refreshInterview(true);
    }

    handleBackToAssignments() {
        this.closeAddItemModal();
        this.loadAssignedList();
    }

    handleOpenAddItemFromCurrent() {
        if (!this.currentSectionKey || this.readOnly) {
            return;
        }

        const clientKey = `new-${Date.now()}-${Math.random().toString(36).slice(2)}`;
        this.items = [
            ...this.items,
            this.decorateItem({
                id: null,
                clientKey,
                section: this.currentSectionKey,
                serviceId: '',
                serviceName: '',
                gender: '',
                quantity: 1,
                recommendation: 'Neutral'
            })
        ];

        this.scrollInlineDraftIntoView(clientKey);
    }

    openAddItemModal() {
        this.showAddItemModal = true;
        this.applyModalViewportLock();

        window.requestAnimationFrame(() => {
            this.updateModalViewportStyle();
        });
    }

    closeAddItemModal() {
        this.showAddItemModal = false;
        this.releaseModalViewportLock();
    }

    handleCloseAddItem() {
        this.closeAddItemModal();
    }

    handleModalOverlayClick() {
        this.handleCloseAddItem();
    }

    handleModalOverlayTouchMove(event) {
        if (event && typeof event.preventDefault === 'function') {
            event.preventDefault();
        }
    }

    stopModalEventPropagation(event) {
        if (event && typeof event.stopPropagation === 'function') {
            event.stopPropagation();
        }
    }

    applyModalViewportLock() {
        this.updateModalViewportStyle();

        if (this.modalLockApplied) {
            return;
        }

        this.modalLockApplied = true;
        this.previousBodyOverflow = document.body.style.overflow || '';
        this.previousDocumentOverflow = document.documentElement.style.overflow || '';
        this.previousBodyTouchAction = document.body.style.touchAction || '';
        this.previousDocumentTouchAction = document.documentElement.style.touchAction || '';

        document.body.style.overflow = 'hidden';
        document.documentElement.style.overflow = 'hidden';
        document.body.style.touchAction = 'none';
        document.documentElement.style.touchAction = 'none';

        window.addEventListener('resize', this.modalPositionHandler);
        window.addEventListener('orientationchange', this.modalPositionHandler);
        window.addEventListener('scroll', this.modalPositionHandler, true);
    }

    releaseModalViewportLock() {
        if (!this.modalLockApplied) {
            return;
        }

        this.modalLockApplied = false;
        document.body.style.overflow = this.previousBodyOverflow;
        document.documentElement.style.overflow = this.previousDocumentOverflow;
        document.body.style.touchAction = this.previousBodyTouchAction;
        document.documentElement.style.touchAction = this.previousDocumentTouchAction;

        window.removeEventListener('resize', this.modalPositionHandler);
        window.removeEventListener('orientationchange', this.modalPositionHandler);
        window.removeEventListener('scroll', this.modalPositionHandler, true);
    }

    updateModalViewportStyle() {
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 700;
        const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 360;
        const hostRect = this.template.host.getBoundingClientRect();

        // Salesforce mobile puts record pages inside nested scroll containers.
        // Position the modal relative to the LWC host, but size it to the
        // currently visible viewport instead of the component's content height.
        const visibleTop = Math.max(0, hostRect.top);
        const modalTop = Math.max(0, visibleTop - hostRect.top);
        const modalLeft = 0 - hostRect.left;
        const modalHeight = Math.max(420, viewportHeight - visibleTop);

        const nextStyle = [
            `--hgh-modal-top: ${modalTop}px`,
            `--hgh-modal-left: ${modalLeft}px`,
            `--hgh-modal-width: ${viewportWidth}px`,
            `--hgh-modal-height: ${modalHeight}px`
        ].join('; ') + ';';

        if (this.modalViewportStyle !== nextStyle) {
            this.modalViewportStyle = nextStyle;
        }
    }

    handleDraftGenderChange(event) {
        this.draftItem = {
            ...this.draftItem,
            gender: event.detail.value,
            serviceId: ''
        };
    }

    handleDraftServiceChange(event) {
        const serviceId = event.detail.value;
        const service = this.serviceOptions.find((option) => option.value === serviceId);
        this.draftItem = {
            ...this.draftItem,
            serviceId,
            gender: service?.gender || this.draftItem.gender
        };
    }

    handleDraftQuantityChange(event) {
        this.draftItem = { ...this.draftItem, quantity: event.target.value };
    }

    handleDraftRecommendationChange(event) {
        this.draftItem = { ...this.draftItem, recommendation: event.detail.value };
    }

    handleAddItem() {
        if (!this.draftItem.serviceId) {
            this.showToast('Missing Item', 'Select a requested item before adding it.', 'error');
            return;
        }

        const quantity = Number(this.draftItem.quantity);
        if (!Number.isFinite(quantity) || quantity <= 0) {
            this.showToast('Invalid Quantity', 'Quantity must be greater than zero.', 'error');
            return;
        }

        const service = this.serviceOptions.find(
            (option) => option.value === this.draftItem.serviceId
        );
        const clientKey = `new-${Date.now()}-${Math.random().toString(36).slice(2)}`;

        this.items = [
            ...this.items,
            this.decorateItem({
                id: null,
                clientKey,
                section: service?.sectionKey || this.modalSectionKey || 'otherItems',
                serviceId: this.draftItem.serviceId,
                serviceName: service?.label || 'Requested Item',
                gender: service?.gender || this.draftItem.gender || '',
                quantity,
                recommendation: this.draftItem.recommendation || 'Neutral'
            })
        ];

        this.closeAddItemModal();
    }

    handleItemChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = event.detail?.value ?? event.target.value;

        this.items = this.items.map((item) => {
            if (item.clientKey !== key) {
                return item;
            }

            let nextItem = { ...item, [field]: value };

            if (field === 'gender') {
                nextItem = {
                    ...nextItem,
                    serviceId: '',
                    serviceName: ''
                };
            }

            if (field === 'serviceId') {
                const service = this.serviceOptions.find((option) => option.value === value);
                nextItem = {
                    ...nextItem,
                    serviceName: service?.label || '',
                    section: service?.sectionKey || item.section,
                    gender: service?.gender || item.gender || ''
                };
            }

            return this.decorateItem(nextItem);
        });
    }

    handleRemoveItem(event) {
        const key = event.currentTarget.dataset.key;
        this.items = this.items.filter((item) => item.clientKey !== key);
    }

    handleCurrentSectionNotesChange(event) {
        if (!this.currentSectionKey) {
            return;
        }
        this.sectionNotes = {
            ...this.sectionNotes,
            [this.currentSectionKey]: event.target.value
        };
    }

    handleWhyHelpChange(event) {
        this.whyHelp = event.target.value;
    }

    handleWhyNotHelpChange(event) {
        this.whyNotHelp = event.target.value;
    }

    handleSantaChange(event) {
        this.santaInterest = event.target.checked;
    }

    handleRefresh() {
        this.refreshInterview(false);
    }

    async handleStepClick(event) {
        const targetIndex = Number(event.currentTarget.dataset.index);
        if (!Number.isInteger(targetIndex)) {
            return;
        }
        await this.navigateToStep(targetIndex);
    }

    async handlePrevious() {
        await this.navigateToStep(this.currentStepIndex - 1);
    }

    async handleNext() {
        await this.navigateToStep(this.currentStepIndex + 1);
    }

    async navigateToStep(targetIndex) {
        const boundedIndex = Math.max(0, Math.min(targetIndex, this.completeStepIndex));
        if (boundedIndex === this.currentStepIndex || this.saving) {
            return;
        }

        if (!this.readOnly && this.interviewReady) {
            const saved = await this.persistDraft(false, true);
            if (!saved) {
                return;
            }
        }

        this.currentStepIndex = boundedIndex;
        this.scrollWizardIntoView();
    }

    async handleSaveDraft() {
        await this.persistDraft(true, true);
    }

    async handleSaveExit() {
        const saved = await this.persistDraft(true, true);
        if (!saved) {
            return;
        }

        if (this.openedFromLanding) {
            await this.loadAssignedList();
        }
    }

    async persistDraft(showToast, refreshAfterSave) {
        this.saving = true;

        try {
            if (this.offlineMode) {
                this.saveOfflineDraft(false);
                this.assignmentStatus = this.assignmentStatus || 'In Progress';
                this.hasOfflineDraft = true;
                this.offlineMessage = 'Offline draft saved on this device. It will sync automatically when connection returns.';

                if (showToast) {
                    this.showToast('Offline Draft Saved', 'Your changes were saved on this device and will sync when you are online.', 'success');
                }
                return true;
            }

            await saveInterview(this.buildSavePayload(false));
            this.clearOfflineDraft();
            this.assignmentStatus = 'In Progress';

            if (refreshAfterSave) {
                await this.refreshInterviewSilently();
            }

            if (showToast) {
                this.showToast('Draft Saved', 'Interview responses were saved.', 'success');
            }
            return true;
        } catch (error) {
            this.showToast('Save Failed', this.reduceError(error), 'error');
            return false;
        } finally {
            this.saving = false;
        }
    }

    async handleComplete() {
        if (!this.validateForCompletion()) {
            return;
        }

        this.saving = true;
        try {
            if (this.offlineMode) {
                this.saveOfflineDraft(true);
                this.hasOfflineDraft = true;
                this.assignmentStatus = 'Pending Sync';
                this.offlineMessage = 'Interview completion is saved on this device and will sync when connection returns.';
                this.showToast(
                    'Completion Queued Offline',
                    'The completion is stored on this device and will sync when you are online.',
                    'success'
                );
                return;
            }

            await saveInterview(this.buildSavePayload(true));
            this.clearOfflineDraft();
            this.readOnly = true;
            this.assignmentStatus = 'Completed';
            this.notReadyMessage = 'This Home Interview has been completed and is read only.';
            this.closeAddItemModal();
            this.showToast(
                'Interview Completed',
                'The interview was completed successfully. The form is now read only.',
                'success'
            );
        } catch (error) {
            this.showToast('Save Failed', this.reduceError(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    isBrowserOnline() {
        return typeof navigator === 'undefined' || navigator.onLine !== false;
    }

    updateNetworkStatus() {
        this.offlineMode = !this.isBrowserOnline();
    }

    getStorageValue(key) {
        try {
            const rawValue = window.localStorage.getItem(key);
            return rawValue ? JSON.parse(rawValue) : null;
        } catch (error) {
            return null;
        }
    }

    setStorageValue(key, value) {
        try {
            window.localStorage.setItem(key, JSON.stringify(value));
        } catch (error) {
            this.showToast('Offline Storage Warning', 'This device could not store the latest offline draft.', 'warning');
        }
    }

    removeStorageValue(key) {
        try {
            window.localStorage.removeItem(key);
        } catch (error) {
            // Ignore storage cleanup failures.
        }
    }

    interviewStorageIds(extraId) {
        return Array.from(new Set([
            extraId,
            this.activeRecordId,
            this.recordId,
            this.caseId,
            this.scheduleId
        ].filter(Boolean)));
    }

    cacheAssignedInterviews(rows) {
        this.setStorageValue(OFFLINE_ASSIGNED_LIST_KEY, {
            cachedAt: new Date().toISOString(),
            rows
        });
    }

    loadCachedAssignedInterviews() {
        return this.getStorageValue(OFFLINE_ASSIGNED_LIST_KEY)?.rows || null;
    }

    cacheInterviewData(data, contextId) {
        const cachedRecord = {
            cachedAt: new Date().toISOString(),
            data
        };

        this.interviewStorageIds(contextId || data?.scheduleId || data?.caseId).forEach((id) => {
            this.setStorageValue(`${OFFLINE_INTERVIEW_PREFIX}${id}`, cachedRecord);
        });
    }

    loadCachedInterviewData(contextId) {
        for (const id of this.interviewStorageIds(contextId)) {
            const cachedRecord = this.getStorageValue(`${OFFLINE_INTERVIEW_PREFIX}${id}`);
            if (cachedRecord?.data) {
                return cachedRecord.data;
            }
        }
        return null;
    }

    offlineDraftKey() {
        const keyId = this.activeRecordId || this.recordId || this.scheduleId || this.caseId;
        return keyId ? `${OFFLINE_DRAFT_PREFIX}${keyId}` : null;
    }

    saveOfflineDraft(completeInterview) {
        const key = this.offlineDraftKey();
        if (!key) {
            throw new Error('Offline draft cannot be saved because the interview context is missing.');
        }

        const payload = this.buildSavePayload(completeInterview);
        const draftRecord = {
            savedAt: new Date().toISOString(),
            completeInterview,
            payload,
            state: {
                items: this.items,
                sectionNotes: this.sectionNotes,
                whyHelp: this.whyHelp,
                whyNotHelp: this.whyNotHelp,
                santaInterest: this.santaInterest,
                currentStepIndex: this.currentStepIndex
            }
        };

        this.setStorageValue(key, draftRecord);
    }

    loadOfflineDraft() {
        const key = this.offlineDraftKey();
        return key ? this.getStorageValue(key) : null;
    }

    applyQueuedOfflineDraft() {
        const draftRecord = this.loadOfflineDraft();
        if (!draftRecord?.state) {
            this.hasOfflineDraft = false;
            return;
        }

        this.items = (draftRecord.state.items || []).map((item) => this.decorateItem(item));
        this.sectionNotes = {
            ...this.sectionNotes,
            ...(draftRecord.state.sectionNotes || {})
        };
        this.whyHelp = draftRecord.state.whyHelp ?? this.whyHelp;
        this.whyNotHelp = draftRecord.state.whyNotHelp ?? this.whyNotHelp;
        this.santaInterest = draftRecord.state.santaInterest === true;
        this.currentStepIndex = Number.isInteger(draftRecord.state.currentStepIndex)
            ? draftRecord.state.currentStepIndex
            : this.currentStepIndex;
        this.hasOfflineDraft = true;
    }

    clearOfflineDraft() {
        const key = this.offlineDraftKey();
        if (key) {
            this.removeStorageValue(key);
        }
        this.hasOfflineDraft = false;
    }

    async syncOfflineDraftIfAvailable() {
        if (this.offlineMode || this.saving) {
            return;
        }

        const draftRecord = this.loadOfflineDraft();
        if (!draftRecord?.payload) {
            this.hasOfflineDraft = false;
            return;
        }

        this.saving = true;
        try {
            await saveInterview(draftRecord.payload);
            this.clearOfflineDraft();
            this.offlineMessage = '';
            await this.refreshInterviewSilently();
            this.showToast('Offline Changes Synced', 'Your offline interview changes were synced to Salesforce.', 'success');
        } catch (error) {
            this.hasOfflineDraft = true;
            this.offlineMessage = `Offline sync failed: ${this.reduceError(error)}`;
            this.showToast('Offline Sync Failed', this.reduceError(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    scrollInlineDraftIntoView(clientKey) {
        window.requestAnimationFrame(() => {
            const card = this.template.querySelector(`[data-card-key="${clientKey}"]`);
            if (card) {
                card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });
    }

    buildSavePayload(completeInterview) {
        return {
            recordId: this.activeRecordId || this.recordId,
            itemsJson: JSON.stringify(
                this.items.map((item) => ({
                    id: item.id,
                    serviceId: item.serviceId,
                    quantity: item.quantity,
                    recommendation: item.recommendation || 'Neutral'
                }))
            ),
            sectionNotesJson: JSON.stringify(this.sectionNotes),
            whyHelp: this.whyHelp,
            whyNotHelp: this.whyNotHelp,
            santaInterest: this.santaInterest,
            completeInterview
        };
    }

    validateForCompletion() {
        const invalidItem = this.items.find(
            (item) => !item.serviceId || Number(item.quantity) <= 0 || !item.recommendation
        );

        if (invalidItem) {
            this.showToast(
                'Missing Requested Item Details',
                'Every requested item must have an item, quantity, and volunteer recommendation.',
                'error'
            );
            return false;
        }
        return true;
    }

    scrollWizardIntoView() {
        window.requestAnimationFrame(() => {
            const panel = this.template.querySelector('.wizard-shell');
            if (panel) {
                panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        });
    }

    inferSection(serviceName) {
        const name = (serviceName || '').toLowerCase();
        if (name.includes('pillow') || name.includes('towel') || name.includes('washcloth')) return 'linens';
        if (name.includes('sheet') || name.includes('blanket') || name.includes('comforter') || name.includes('bedding')) return 'existingBedding';
        if (
            name.includes('sofa') || name.includes('couch') || name.includes('dresser') ||
            name.includes('furniture') || name.includes('refrigerator') || name.includes('washer') ||
            name.includes('dryer')
        ) return 'furniture';
        if (
            name.includes('microwave') || name.includes('toaster') || name.includes('vacuum') ||
            name.includes('appliance') || name.includes('dishes') || name.includes('glassware')
        ) return 'smallAppliances';
        if (
            name.includes('bed') || name.includes('mattress') || name.includes('twin') ||
            name.includes('full') || name.includes('queen') || name.includes('king')
        ) return 'newBeds';
        return 'otherItems';
    }

    normalizeMode(value) {
        return (value || '').replace('AfterNoon', 'Afternoon');
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        const raw = String(value).substring(0, 10);
        const [year, month, day] = raw.split('-').map(Number);
        if (!year || !month || !day) {
            return raw;
        }
        return new Intl.DateTimeFormat('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(new Date(year, month - 1, day));
    }

    formatTimeRange(startValue, endValue) {
        const start = this.formatSalesforceTime(startValue);
        const end = this.formatSalesforceTime(endValue);
        return `${start}${start && end ? ' - ' : ''}${end}`;
    }

    formatSalesforceTime(value) {
        if (value === null || value === undefined || value === '') {
            return '';
        }

        const numericValue = Number(value);
        if (Number.isFinite(numericValue) && /^\d+$/.test(String(value))) {
            const totalMinutes = Math.floor(numericValue / 60000);
            const hour24 = Math.floor(totalMinutes / 60);
            const minute = totalMinutes % 60;
            const suffix = hour24 >= 12 ? 'PM' : 'AM';
            const hour12 = hour24 % 12 || 12;
            return `${hour12}:${String(minute).padStart(2, '0')} ${suffix}`;
        }

        const text = String(value);
        const match = text.match(/(\d{2}):(\d{2})/);
        if (!match) {
            return text;
        }

        const hour24 = Number(match[1]);
        const minute = match[2];
        const suffix = hour24 >= 12 ? 'PM' : 'AM';
        const hour12 = hour24 % 12 || 12;
        return `${hour12}:${minute} ${suffix}`;
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}