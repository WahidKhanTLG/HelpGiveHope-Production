import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import ACCOUNT_ID from '@salesforce/schema/Case.AccountId';
import ACCOUNT_NAME from '@salesforce/schema/Case.Account.Name';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

export default class ViewHouseholdAction extends NavigationMixin(LightningElement) {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_ID, ACCOUNT_NAME] })
    caseRecord;

    get accountId() {
        return getFieldValue(this.caseRecord.data, ACCOUNT_ID);
    }

    get householdName() {
        return getFieldValue(this.caseRecord.data, ACCOUNT_NAME) || 'Household';
    }

    get hasHousehold() {
        return Boolean(this.accountId);
    }

    get noHousehold() {
        return !this.hasHousehold;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$accountId',
        relatedListId: 'Contacts',
        fields: ['Contact.Id', 'Contact.Name', 'Contact.Phone', 'Contact.Email', 'Contact.TLG_Relationship_with_Applicant__c']
    })
    contacts;

    get memberList() {
        if (!this.contacts?.data?.records) return [];
        return this.contacts.data.records.map(r => ({
            Id: r.fields.Id.value,
            Name: r.fields.Name.value,
            Phone: r.fields.Phone.value,
            Email: r.fields.Email.value,
            TLG_Relationship_with_Applicant__c: r.fields.TLG_Relationship_with_Applicant__c?.value
        }));
    }

    openHousehold() {
        if (!this.accountId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.accountId,
                actionName: 'view'
            }
        });
        this.closeAction();
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}