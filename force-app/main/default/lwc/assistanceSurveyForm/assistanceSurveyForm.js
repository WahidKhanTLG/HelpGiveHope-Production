import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDetailById from '@salesforce/apex/AssistanceSurveyController.getDetailById';
import newSurvey from '@salesforce/apex/AssistanceSurveyController.newSurvey';
import getFormStatus from '@salesforce/apex/FormVisibilityController.getFormStatus';
import LOGO from '@salesforce/resourceUrl/LogoFull';

export default class AssistanceSurveyForm extends LightningElement {
    // ------- internal state -------
    _recordId = null;
    resolvedAccountId = null;
    resolvedCaseId = null;
    utmContent = '';
    isValidId = false;
    isCheckingFormStatus = true;
    logoUrl = LOGO;

    // form values
    satisfactionValue = undefined;       // string label like "Very Satisfied"
    recommendValue = null;               // boolean
    resourcesValue = '';                 // string (min 100 chars)
    financialImprovementValue = null;    // boolean
    suggestionsValue = '';               // string (min 100 chars)

    // ui state
    isSubmitted = false;
    isSubmitting = false;

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
        const cleaned = (value || '').toString().trim();
        this._recordId = cleaned || null;
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
    @wire(getDetailById, { recordId: '$recordId' })
    getDetailByIdHandler({ data, error }) {
        if (data?.statusCode === 200) {
            this.isValidId = !!data.isValidId;
            this.resolvedAccountId = data.accountId || null;
            this.resolvedCaseId = data.caseId || null;
        } else if (error) {
            // optional: surface/log error
            // this.showToast('Error', error.body?.message || 'Failed to validate record id', 'error');
            this.isValidId = false;
            this.resolvedAccountId = null;
            this.resolvedCaseId = null;
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
    async handleSubmit() {
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
            const msg = error?.body?.message || error?.message || 'Unknown error occurred';
            this.showToast('Error', msg, 'error');
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