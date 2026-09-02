import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getFormStatus from '@salesforce/apex/FormVisibilityController.getFormStatus';

export default class WishListFormRecordIdFetch extends LightningElement {
    // --- state ---
    currentPageReference;
    isCheckingFormStatus = true;        // <-- you were using this in template; now defined
    formStatus = { isActive: false, message: '', formId: '' };

    // --- config ---
    flowName = 'WishList_Form';         // Flow API Name
    formName = 'Wishlist Christmas Aid Requests';

    // Capture page ref so getters can read URL params
    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        this.currentPageReference = pageRef;
    }

    // Try common URL/state keys for the record Id
    get recId() {
        const pr = this.currentPageReference;
        const s = pr?.state || {};
        return (
            s.recordId ||        // ?recordId=001...
            s.c__recordId ||     // ?c__recordId=001...
            s.id ||              // ?id=001...
            s.c__id ||           // ?c__id=001...
            s.caseId ||          // ?caseId=500...
            s.c__caseId ||       // ?c__caseId=500...
            pr?.attributes?.recordId || // record page attribute
            null
        );
    }

    // Provide inputs only when we actually have recId
    get inputVariables() {
        return this.recId
            ? [{ name: 'recordId', type: 'String', value: this.recId }]
            : [];
    }

    // Lifecycle
    connectedCallback() {
        this.loadFormStatus();
    }

    // Form visibility
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

    // Convenience getters for template
    get isFormActive() {
        return this.formStatus?.isActive === true;
    }
    get isFormInactive() {
        return !this.isFormActive;
    }

    handleStatusChange(event) {
        // optional: const { status } = event.detail;
    }
}