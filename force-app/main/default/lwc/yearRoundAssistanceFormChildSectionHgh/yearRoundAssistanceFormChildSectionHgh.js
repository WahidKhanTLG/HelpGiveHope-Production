import { LightningElement, api, wire } from 'lwc';

import getPicklistValues from '@salesforce/apex/YearRoundAssistanceFormController.getPicklistValues';

import DropdownOptions from './dropdown-options';
import RadioGroupOptions from './radio-group-options';

export default class YearRoundAssistanceFormChildSectionHgh extends LightningElement {
    _title;

    genderOptions = DropdownOptions.GenderOptions;
    relationShipOptions = DropdownOptions.RelationShipOptions;

    schoolAttendingOptions = RadioGroupOptions.SchoolAttendingOptions;
    legalGuardianOptions = []; // RadioGroupOptions.LegalGuardianOptions;
    duplicateMessage = "";
    

    @wire(getPicklistValues) /* { 'userId': '$loginId' } */
    getPicklistValuesHandler({data, error}) {
        if(data) {
            this.genderOptions = this.mapToDropdownOptions(data.GenderIdentity);
            this.relationShipOptions = this.mapToDropdownOptions(data.npe4__Type__c);
            
            this.legalGuardianOptions = this.mapToRadioGroupOptions(data.TLG_Are_you_their_legal_guardian__c);
        } else if (error) {
            console.log(error);
        }
    }

    mapToDropdownOptions(picklistOptions) {
        return (picklistOptions || []).map(({ value, label }) => ({ 
            label, 
            value, 
            selected: false 
        }));
    }

    mapToRadioGroupOptions(picklistOptions) {
        return (picklistOptions || []).map(({ value, label }) => ({ 
            label, 
            value
        }));
    }

    // @api clearDuplicateValidation() {
    // const duplicateFieldNames = ["FirstName", "LastName", "DateOfBirth", "RelationShip"];

    // duplicateFieldNames.forEach((fieldName) => {
    //     const field = this.template.querySelector(`[name="${fieldName}"]`);
    //     if (field) {
    //     field.setCustomValidity("");
    //     field.reportValidity();
    //     }
    // });
    // }

    // @api setDuplicateValidation(message = "Duplicate entry detected.") {
    // const duplicateFieldNames = ["FirstName", "LastName", "DateOfBirth", "RelationShip"];

    // duplicateFieldNames.forEach((fieldName) => {
    //     const field = this.template.querySelector(`[name="${fieldName}"]`);
    //     if (field) {
    //     field.setCustomValidity(message);
    //     field.reportValidity();
    //     }
    // });
    // }

    @api set title(value) {
        this._title = (value || '').toString();
    }

    get title() {
        return this._title || 'Child';
    }


    @api clearDuplicateValidation() {
        this.duplicateMessage = "";
    }

    @api setDuplicateValidation(message = "Duplicate entry detected.") {
        this.duplicateMessage = message;
    }

    get isDuplicate() {
        return !!this.duplicateMessage;
    }

    get cardClass() {
        return this.isDuplicate ? "hgh-section-card hgh-section-card--duplicate" : "hgh-section-card";
    }

    @api get payload() {
        const inputSelector = 'c-year-round-assistance-form-input-hgh';
        const maskInputSelector = 'c-year-round-assistance-form-mask-input-hgh';
        const dropdownSelector = 'c-year-round-assistance-form-dropdown-hgh';
        const radioGroupSelector = 'c-year-round-assistance-form-radio-group-hgh';
        const inputs = Array.from(this.template.querySelectorAll(`${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`));

        const fieldsMap = inputs.reduce((data, { name, label, type, value, maskedValue, required, additionalInfo, nodeName }) => ({
            ...data,
            [name]: { name, label, type, value, maskedValue, required, additionalInfo, nodeName }
        }), {});

        const fields = inputs.map(({ name, label, type, value, maskedValue, required, additionalInfo, nodeName }) => ({ 
            name, label, type, value, maskedValue, required, additionalInfo, nodeName 
        }));

        return {
            title: this.title,
            fields,
            fieldsMap,
            computedFields: this.computedFields
        };
    }

    @api get computedFields() {
        return {
            age: Number(this.refs?.age?.value) || 0
        }
    }

    get minimumDateHtmlAttribute() {
        const today = new Date();
        const dt = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate() + 1);
        return this.convertDateToString(dt);
    }

    get maximumDateHtmlAttribute() {
        const today = new Date();
        return this.convertDateToString(today);
    }

    convertDateToString(dt) {
        const year = dt.getFullYear();
        const month = (dt.getMonth() + 1).toString().padStart(2, '0');
        const date = dt.getDate().toString().padStart(2, '0');

        return `${year}-${month}-${date}`;
    }

    convertDateToReadableString(dt) {
        dt = new Date(dt);

        if(isNaN(dt)) dt = new Date();

        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        const year = dt.getFullYear();
        const month = months[dt.getMonth()];
        const date = dt.getDate().toString().padStart(2, '0');

        return `${month} ${date}, ${year}`;
    }

    calculateAge(event) {
        let dob = event.detail.value;
        let age = '';

        const birthDate = new Date(dob);
        if(!isNaN(birthDate)) {

            const today = new Date();
            age = today.getFullYear() - birthDate.getFullYear();
            const monthDiff = today.getMonth() - birthDate.getMonth();
            const dayDiff = today.getDate() - birthDate.getDate();

            if (monthDiff < 0 || (monthDiff === 0 && dayDiff < 0)) {
                age--;
            }
        }

        this.refs.age.value = age.toString();
    }

    @api validate() {
        const inputSelector = 'c-year-round-assistance-form-input-hgh';
        const maskInputSelector = 'c-year-round-assistance-form-mask-input-hgh';
        const dropdownSelector = 'c-year-round-assistance-form-dropdown-hgh';
        const radioGroupSelector = 'c-year-round-assistance-form-radio-group-hgh';
        const fields = Array.from(this.template.querySelectorAll(`${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`));
        
        fields.filter(field => !field.disabled).forEach((field) => {
            let fieldValue = field.value?.trim() || '';
            field.setCustomValidity('');
            if(!fieldValue) {
                field.setCustomValidity('This field is required.');
            } else if (field.dataset.type === 'date') {
                if(isNaN(new Date(fieldValue))) {
                    field.setCustomValidity('Must be a valid date.');
                } else if(fieldValue < this.minimumDateHtmlAttribute || fieldValue > this.maximumDateHtmlAttribute) {
                    const minDate = this.convertDateToReadableString(this.minimumDateHtmlAttribute);
                    const maxDate = this.convertDateToReadableString(this.maximumDateHtmlAttribute);

                    field.setCustomValidity(`The date should be between ${minDate} and ${maxDate}.`);
                }
            } else if (field.nodeName === radioGroupSelector.toUpperCase() && field.hasAdditionalInfo) {
                let additionalInfo = field.additionalInfo?.trim() || '';
                if(!additionalInfo) {
                    field.setCustomValidity('This field is required.');
                }
            }
        });

        return fields.filter(field => !field.disabled && !field.reportValidity());
    }
}