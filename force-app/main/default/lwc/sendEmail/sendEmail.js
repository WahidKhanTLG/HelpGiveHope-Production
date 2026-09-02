import { LightningElement, wire, api, track } from 'lwc';
import getAccount_RelatedContacts from '@salesforce/apex/SendEmailController.getAccount_RelatedContacts';
import getMetaDataValues from '@salesforce/apex/SendEmailController.getMetaDataValues';
import getPicklistValues from '@salesforce/apex/SendEmailController.getPicklistValues';
import sendEmailAndInsertEmailBodyMetadata from '@salesforce/apex/SendEmailController.sendEmailAndInsertEmailBodyMetadata';
import sendEmail from '@salesforce/apex/SendEmailController.sendEmail';
import updateAccount from '@salesforce/apex/SendEmailController.updateAccount';
import updateCaseStatus from '@salesforce/apex/SendEmailController.updateCaseStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class SendEmail extends LightningElement {
    @api recordId;
    relatedAccountId = null;
    getTemplate = true;
    toEmails = '';
    ccEmails = '';
    bccEmails = '';
    selectedSubject = '';
    selectedBody = '';
    selectedDeveloperName = '';
    isCCVisible = false;
    isBCCVisible = false;
    noEmailFound = false;
    // applicationStatus = null;
    caseStatus = null;
    @track templateOptions = [];
    @track statusOptions = [];
    sendEmail_MetadataTemplateLabel = 'Send Email and Save';
    
    fetchingPicklistValues = true;
    fetchingAccountDetails = true;
    fetchingEmailTemplates = false;
    saving = false;
    isLoading = false;

    get loading() {
        return (
            this.fetchingPicklistValues ||
            this.fetchingAccountDetails ||
            this.fetchingEmailTemplates ||
            this.saving
        );
    }

    get emailRequestPayload() {
        return {
            toEmails: this.normalizeEmailList(this.toEmails),
            ccEmails: this.normalizeEmailList(this.ccEmails),
            bccEmails: this.normalizeEmailList(this.bccEmails),
            emailSubject: this.selectedSubject,
            emailBody: this.selectedBody,
            accountId: this.relatedAccountId,
            relatedRecordId: this.recordId
        };
    }

    normalizeEmailList(emails) {
        if (Array.isArray(emails)) {
            return emails.filter(Boolean);
        }

        if (typeof emails === 'string') {
            return emails.split(',').map(email => email.trim()).filter(Boolean);
        }

        return [];
    }

    scrollCardPanelToTop() {
        const cardPanel = this.template.querySelector('.card-panel');
        if (cardPanel) {
            cardPanel.scrollTop = 0;
        }
    }

    startSaving() {
        this.saving = true;
        this.isLoading = true;
        this.scrollCardPanelToTop();
    }

    stopSaving() {
        this.saving = false;
        this.isLoading = false;
    }

    prepareForSubmit() {
        this.startSaving();

        if (this.isInputValid()) {
            return true;
        }

        this.stopSaving();
        return false;
    }

    getErrorMessage(error, fallbackMessage) {
        return error.body?.message || error.message || fallbackMessage;
    }

    handleFailedSend(result, fallbackMessage) {
        this.stopSaving();
        this.showToast('Error', result || fallbackMessage, 'error');
    }

    handleUnexpectedSendError(error, fallbackMessage, logMessage) {
        this.stopSaving();
        console.log(logMessage, error);
        this.showToast('Error', this.getErrorMessage(error, fallbackMessage), 'error');
    }

    // async updateRelatedAccountStatus() {
    //     if (!this.relatedAccountId) {
    //         return 'OK';
    //     }

    //     return updateAccount({
    //         account: {
    //             sobjectType: 'Account',
    //             Id: this.relatedAccountId,
    //             Application_Status__c: this.applicationStatus
    //         }
    //     });
    // }

    async updateRelatedCaseStatus() {
        if (!this.recordId) {
            return 'OK';
        }

        return updateCaseStatus({
            caseRecord: {
                sobjectType: 'Case',
                Id: this.recordId,
                Status: this.caseStatus
            }
        });
    }

    async handleSuccessfulSaveResponse() {
        // const updateAccountResult = await this.updateRelatedAccountStatus();

        // if(updateAccountResult !== 'OK') {
        //     this.showToast('Error', 'Error occurred while updating Account', 'error');
        // }

        const updateCaseResult = await this.updateRelatedCaseStatus();

        if (updateCaseResult !== 'OK') {
            this.showToast('Error', 'Error occurred while updating Case Status', 'error');
            return;
        }

        this.fetchEmailTemplates();
        this.stopSaving();
        this.showToast('Success', 'Email Send successfully', 'success');
        this.closeQuickAction();
    }

    handleSuccessfulOneTimeResponse() {
        this.stopSaving();
        this.showToast('Success', 'Email Send successfully', 'success');
        this.closeQuickAction();
    }

    // @wire(getPicklistValues, { fieldPaths: ['Account.Application_Status__c'] })
    // getPicklistValuesHandler({ data, error }) {
    //     if(data) {
    //         data = data || {};
    //         this.statusOptions = (data['Account.Application_Status__c'] || []).map(({label, value}) => ({
    //             label, value
    //         }));
    //     } else if(error) {
    //         console.log('Error in wired Get Picklist Values:', error);
    //     }

    //     this.fetchingPicklistValues = !!(data || error);
    // }

    @wire(getPicklistValues, { fieldPaths: ['Case.Status'] })
    getPicklistValuesHandler({ data, error }) {
        if (data) {
            data = data || {};
            this.statusOptions = (data['Case.Status'] || []).map(({ label, value }) => ({
                label,
                value
            }));
        } else if (error) {
            console.log('Error in wired Get Picklist Values:', error);
        }

        this.fetchingPicklistValues = !!(data || error);
    }

    @wire(getAccount_RelatedContacts, { recordId: '$recordId' })
    wiredOpp_ContactRole({ error, data }) {
        if (data) {
            const toEmails = data?.toEmails || [];
            this.noEmailFound = toEmails.length <= 0;
            if(this.noEmailFound){
                this.showToast('Error', 'No Email Found', 'error');
                return;
            } else {
                this.relatedAccountId = data?.account?.Id || null;
                // this.applicationStatus = data.account.Application_Status__c || null;
                this.caseStatus = data.caseStatus || null;
                this.toEmails = (data?.toEmails || []).join(', ');
                this.ccEmails = (data?.ccEmails || []).join(', ');
                this.bccEmails = '';
            }
        } else if (error) {
            console.error('Error retrieving opportunity and Opp Contact Role:', error);
        }

        this.fetchingAccountDetails = !!(data || error);
    }

    connectedCallback() {
        this.fetchEmailTemplates();
    }

    fetchEmailTemplates() {
        this.fetchingEmailTemplates = true;
        getMetaDataValues()
            .then(result => {
                if (result) {
                    this.templateOptions = [];
                    this.templateOptions = result.map(template => {
                        return {
                            label: template.subject,
                            value: `${template.subject}|${template.body}|${template.developerName}`
                        };
                    });
                    // Optionally, add the "Type a response" option at the top
                    this.templateOptions.unshift({ label: 'Add New (Blank)', value: 'add_new' });
                }
            })
            .catch(error => {
                console.error('Error retrieving email templates:', error);
            }).then(() => {
                this.fetchingEmailTemplates = false;
            });
    }

    toggleCC() {
        this.isCCVisible = !this.isCCVisible;
    }

    toggleBCC() {
        this.isBCCVisible = !this.isBCCVisible;
    }

    handleCCChange(event) {
        this.ccEmails = event.detail.value;
    }

    handleBCCChange(event) {
        this.bccEmails = event.detail.value;
    }

    handleTemplateChange(event) {
        const selectedValue = event.detail.value;
        if (selectedValue === 'add_new') {
            this.sendEmail_MetadataTemplateLabel = 'Send Email and Save';
            this.selectedSubject = '';
            this.selectedBody = '';
            this.selectedDeveloperName = '';
            return;
        }
        this.sendEmail_MetadataTemplateLabel = 'Send Email and Update';
        const [subject, body, developerName] = selectedValue.split('|');
        this.selectedDeveloperName = developerName;
        this.selectedSubject = subject;
        this.selectedBody = body;
    }

    handleStatusChange(event) {
        const selectedValue = event.detail.value;
        // this.applicationStatus = selectedValue;
        this.caseStatus = selectedValue;
    }

    handleSubjectChange(event){
        const selectedValue = event.detail.value;
        this.selectedSubject = selectedValue;    
    }

    handleBodyChange(event){
        this.selectedBody = event.target.value;
    }

    async handleSaveResponse(){
        if(!this.prepareForSubmit()) {
            return;
        }

        try {
            const result = await sendEmailAndInsertEmailBodyMetadata({
                ...this.emailRequestPayload,
                developerName: this.selectedDeveloperName
            });
            console.log('result handleSaveResponse :: '+result);
            
            if(result === 'OK') {
                await this.handleSuccessfulSaveResponse();
                return;
            }

            this.handleFailedSend(result, 'Error occured while sending email');
        } catch (err) {
            this.handleUnexpectedSendError(
                err,
                'Error occured while sending email and creating template',
                'Error sending emails and creating template:'
            );
        }
    }

    async handleOneTimeResponse() {
        if(!this.prepareForSubmit()) {
            return;
        }

        try { 
            const result = await sendEmail(this.emailRequestPayload);
    
            console.log('result handleOneTimeResponse :: '+result);
            if (result === 'OK') {
                // const updateAccountResult = await this.updateRelatedAccountStatus();

                // if (updateAccountResult !== 'OK') {
                //     this.stopSaving();
                //     this.showToast('Error', 'Email sent but Account was not updated', 'error');
                //     return;
                // }

                const updateCaseResult = await this.updateRelatedCaseStatus();

                if (updateCaseResult !== 'OK') {
                    this.stopSaving();
                    this.showToast('Error', 'Email sent but Case Status was not updated', 'error');
                    return;
                }

                this.handleSuccessfulOneTimeResponse();
                return;
            }

            this.handleFailedSend(result, 'Error occurred while sending email');
        } catch (err) {
            this.handleUnexpectedSendError(err, 'Error occurred while sending email', 'Error sending emails:');
        }
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    isInputValid(){
        let isValid = true;
        const inputFields = this.template.querySelectorAll('.validate');
        inputFields.forEach(inputField => {
            if(!inputField.checkValidity()) {
                inputField.reportValidity();
                isValid = false;
            } 
        });
        return isValid;
    }
}