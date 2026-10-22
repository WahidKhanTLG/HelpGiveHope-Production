import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDetailById from '@salesforce/apex/AssistanceSurveyController.getDetailById';
import newSurvey from '@salesforce/apex/AssistanceSurveyController.newSurvey';
import getFormStatus from '@salesforce/apex/FormVisibilityController.getFormStatus';
import LOGO from '@salesforce/resourceUrl/LogoFull';

const MSG_NO_ID = 'This survey link is missing its reference. Please open the survey from the link we sent you, or contact Help Give Hope.';
const MSG_INVALID_ID = 'This survey link is not valid. Please open the survey from the link we sent you, or contact Help Give Hope.';
const MSG_OFFLINE = 'We could not reach the server. Please check your internet connection and try again.';
const MSG_STILL_CHECKING = 'We are still checking your survey link. Please try again in a moment.';
const MSG_GENERIC = 'Something went wrong. Please try again, or contact Help Give Hope if the problem continues.';

export default class AssistanceSurveyForm extends LightningElement {
    // ------- internal state -------
    _recordId = null;
    resolvedAccountId = null;
    resolvedCaseId = null;
    utmContent = '';
    isValidId = false;
    lookupResolved = false;              // getDetailById has answered for the current Id
    lookupConnectionError = false;       // getDetailById failed without a server response
    isCheckingFormStatus = true;
    logoUrl = LOGO;

    // form values
    satisfactionValue = undefined;       // string label like "Very Satisfied"
    recommendValue = false;              // boolean (toggle shows "No" until switched on, so untouched = No)
    resourcesValue = '';                 // string (min 100 chars)
    financialImprovementValue = false;   // boolean (untouched = No, same as above)
    suggestionsValue = '';               // string (min 100 chars)

    // ui state
    isSubmitted = false;
    isSubmitting = false;
    submitError = '';

    // validation messages
    satisfactionError = '';
    recommendError = '';
    resourcesError = '';
    financialError = '';
    suggestionsError = '';

    // config
    // If you want to expose these to App Builder later, decorate with @api.
    formName = 'Survey Form'; // must match Form_Catalog__c.Name

    // form visibility status (set as a new object when updated to keep reactivity)
    formStatus = {
        isActive: false,
        message: '',
        formId: ''
    };

    // rating options (we always reassign with map => no @track needed)
    ratingOptions = [
        { label: 'Very Satisfied', value: '5', icon: '😊', selected: false, highlighted: false, classes: 'rating-option' },
        { label: 'Satisfied', value: '4', icon: '🙂', selected: false, highlighted: false, classes: 'rating-option' },
        { label: 'Neutral', value: '3', icon: '😐', selected: false, highlighted: false, classes: 'rating-option' },
        { label: 'Dissatisfied', value: '2', icon: '🙁', selected: false, highlighted: false, classes: 'rating-option' },
        { label: 'Very Dissatisfied', value: '1', icon: '😞', selected: false, highlighted: false, classes: 'rating-option' }
    ];

    // ------- lifecycle -------
    connectedCallback() {
        this.loadFormStatus();
    }

    // ------- form visibility -------
    async loadFormStatus() {
        this.isCheckingFormStatus = true;
        try {
            const result = await getFormStatus({ formName: this.formName });
            this.formStatus = result
                ? {
                    isActive: !!result.isActive,
                    message: result.message || 'This form is currently unavailable.',
                    formId: result.formId || ''
                }
                : {
                    isActive: false,
                    message: 'Could not determine form status. Please try again later.',
                    formId: ''
                };
        } catch (error) {
            this.formStatus = {
                isActive: false,
                message: error?.body?.message || 'Error loading form status. Please try again later.',
                formId: ''
            };
        } finally {
            this.isCheckingFormStatus = false;
        }
    }

    get isFormActive() {
        return this.formStatus?.isActive === true;
    }

    // ------- page params & recordId -------
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const cleaned = (value || '').toString().trim() || null;
        if (cleaned !== this._recordId) {
            this._recordId = cleaned;
            this.lookupResolved = false;
            this.lookupConnectionError = false;
            this.isValidId = false;
            this.resolvedAccountId = null;
            this.resolvedCaseId = null;
        }
    }

    // undefined (not null) keeps the wire from calling Apex when the URL has no Id
    get wireRecordId() {
        return this._recordId || undefined;
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        const recordId = currentPageReference?.state?.Id || currentPageReference?.state?.id;
        const utmContent = currentPageReference?.state?.utm_content || '';
        this.utmContent = utmContent.toString().trim() || null;
        if (recordId) {
            this.recordId = recordId;
        }
    }

    // ------- detail validation wire -------
    @wire(getDetailById, { recordId: '$wireRecordId' })
    getDetailByIdHandler({ data, error }) {
        if (data) {
            const ok = data.statusCode === 200 && !!data.isValidId;
            this.isValidId = ok;
            this.resolvedAccountId = ok ? data.accountId || null : null;
            this.resolvedCaseId = ok ? data.caseId || null : null;
            this.lookupConnectionError = false;
            this.lookupResolved = true;
        } else if (error) {
            this.isValidId = false;
            this.resolvedAccountId = null;
            this.resolvedCaseId = null;
            // no body means the request never got a server answer (offline, dropped connection)
            this.lookupConnectionError = !error.body;
            this.lookupResolved = true;
        }
    }

    // ------- rating handlers -------
    handleRatingHover(event) {
        const value = event.currentTarget.dataset.value;
        this.ratingOptions = this.ratingOptions.map(option => {
            const isHighlighted = option.value <= value;
            const classes = ['rating-option'];
            if (option.selected) classes.push('selected');
            if (isHighlighted) classes.push('highlighted');
            return { ...option, highlighted: isHighlighted, classes: classes.join(' ') };
        });
    }

    handleRatingLeave() {
        this.ratingOptions = this.ratingOptions.map(option => {
            const classes = ['rating-option'];
            if (option.selected) classes.push('selected');
            return { ...option, highlighted: false, classes: classes.join(' ') };
        });
    }

    handleRatingSelect(event) {
        const value = event.currentTarget.dataset.value;
        const selectedOption = this.ratingOptions.find(o => o.value === value);
        this.satisfactionValue = selectedOption?.label; // store label, per your Apex expectation
        this.validateSatisfaction();
        this.ratingOptions = this.ratingOptions.map(option => {
            const isSelected = option.value === value;
            const classes = ['rating-option'];
            if (isSelected) classes.push('selected');
            return { ...option, selected: isSelected, highlighted: false, classes: classes.join(' ') };
        });
    }

    // ------- field change handlers -------
    handleRecommendChange(event) {
        this.recommendValue = event.detail.checked;
        this.validateRecommend();
    }

    handleResourcesChange(event) {
        this.resourcesValue = event.detail.value || '';
        this.validateResources();
    }

    handleFinancialImprovementChange(event) {
        this.financialImprovementValue = event.detail.checked;
        this.validateFinancial();
    }

    handleSuggestionsChange(event) {
        this.suggestionsValue = event.detail.value || '';
        this.validateSuggestions();
    }

    // ------- validation -------
    validateSatisfaction() {
        this.satisfactionError = this.satisfactionValue ? '' : 'Please select a satisfaction level.';
        return !this.satisfactionError;
    }

    validateRecommend() {
        if (this.recommendValue === null) {
            this.recommendError = 'Please indicate if you would recommend.';
        } else {
            this.recommendError = '';
        }
        return !this.recommendError;
    }

    validateResources() {
        const len = (this.resourcesValue || '').length;
        this.resourcesError = len >= 100 ? '' : `Please enter at least 100 characters (${len}/100).`;
        return !this.resourcesError;
    }

    validateFinancial() {
        if (this.financialImprovementValue === null) {
            this.financialError = 'Please indicate financial improvement.';
        } else {
            this.financialError = '';
        }
        return !this.financialError;
    }

    validateSuggestions() {
        const len = (this.suggestionsValue || '').length;
        this.suggestionsError = len >= 100 ? '' : `Please enter at least 100 characters (${len}/100).`;
        return !this.suggestionsError;
    }

    validateForm() {
        const a = this.validateSatisfaction();
        const b = this.validateRecommend();
        const c = this.validateResources();
        const d = this.validateFinancial();
        const e = this.validateSuggestions();
        return a && b && c && d && e;
    }

    // ------- submit -------
    // Problems we can detect before calling Apex; returns '' when the form can be sent.
    getPreSubmitError() {
        if (typeof navigator !== 'undefined' && navigator.onLine === false) {
            return MSG_OFFLINE;
        }
        if (!this._recordId) {
            return MSG_NO_ID;
        }
        if (!this.lookupResolved) {
            return MSG_STILL_CHECKING;
        }
        if (this.lookupConnectionError) {
            return MSG_OFFLINE;
        }
        if (!this.isValidId) {
            return MSG_INVALID_ID;
        }
        return '';
    }

    async handleSubmit() {
        this.submitError = '';

        const preSubmitError = this.getPreSubmitError();
        if (preSubmitError) {
            this.submitError = preSubmitError;
            this.showToast('Error', preSubmitError, 'error');
            return;
        }

        if (!this.validateForm()) {
            this.showToast('Error', 'Please complete all required fields.', 'error');
            return;
        }

        this.isSubmitting = true;

        try {
            const survey = {
                Account__c: this.isValidId ? this.resolvedAccountId : null,
                Case__c: this.isValidId ? this.resolvedCaseId : null,
                Program_Satisfaction__c: this.satisfactionValue,       // label (e.g., "Very Satisfied")
                Recommend_to_Others__c: this.recommendValue,           // boolean
                Resource_Satisfaction__c: this.resourcesValue,         // long text
                Financial_Improvement__c: this.financialImprovementValue, // boolean
                Suggestions_for_Improvement__c: this.suggestionsValue, // long text
                UTM_Content__c: this.utmContent || null
            };

            await newSurvey({ surveyJson: JSON.stringify(survey) });
            this.isSubmitted = true;
            this.showToast('Success', 'Survey submitted successfully!', 'success');
        } catch (error) {
            // an error without a body never reached Apex (offline, dropped connection)
            this.submitError = error?.body ? MSG_GENERIC : MSG_OFFLINE;
            this.showToast('Error', this.submitError, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    // ------- helpers -------
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get resourcesCharCount() {
        return `${(this.resourcesValue || '').length}/100`;
    }

    get suggestionsCharCount() {
        return `${(this.suggestionsValue || '').length}/100`;
    }

    get satisfactionSectionClasses() {
        return this.satisfactionError ? 'form-section' : 'form-section valid';
    }
    get recommendSectionClasses() {
        return this.recommendError ? 'form-section' : 'form-section valid';
    }
    get resourcesSectionClasses() {
        return this.resourcesError ? 'form-section' : 'form-section valid';
    }
    get financialSectionClasses() {
        return this.financialError ? 'form-section' : 'form-section valid';
    }
    get suggestionsSectionClasses() {
        return this.suggestionsError ? 'form-section' : 'form-section valid';
    }
}