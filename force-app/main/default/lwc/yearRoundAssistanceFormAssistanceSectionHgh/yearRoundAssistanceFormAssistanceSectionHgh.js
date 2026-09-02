import { LightningElement, api, wire } from 'lwc';

import getPicklistValues from '@salesforce/apex/YearRoundAssistanceFormController.getPicklistValues';

import MaskConfigs from './mask-configs';
// import RadioGroupOptions from './radio-group-options';

export default class YearRoundAssistanceFormAssistanceSectionHgh extends LightningElement {
    @api assistanceType;

    error = false;
    timeout = null;

    zipCodeMaskOption = MaskConfigs.ZipCode;
    phoneMaskOption = MaskConfigs.Phone;

    shutoffNoticeOptions = []; // RadioGroupOptions.YesNoOptions;
    reachedOutOACACOptions = []; // RadioGroupOptions.YesNoOptions;
    determinationMadeByOACACOptions = []; // RadioGroupOptions.YesNoOptions;

    get displayUsedCarAssistanceOptions() {
        return this.assistanceType === 'User/Repair Car Assitance';
    }

    // get displayChristmasAssistanceOptions() {
    //     this.assistanceType === 'Christmas Assitance';
    // }

    @wire(getPicklistValues) /* { 'userId': '$loginId' } */
    getPicklistValuesHandler({data, error}) {
        if(data) {            
            this.shutoffNoticeOptions = this.mapToRadioGroupOptions(data.TLG_Do_you_have_a_shutoff_notice__c);
            this.reachedOutOACACOptions = this.mapToRadioGroupOptions(data.TLG_Have_you_reached_out_to_OACAC__c);
            this.determinationMadeByOACACOptions = this.mapToRadioGroupOptions(data.TLG_Has_OACAC_made_a_determination__c);
        } else if (error) {
            console.log(error);
        }
    }

    mapToRadioGroupOptions(picklistOptions) {
        return (picklistOptions || []).map(({ value, label }) => ({ 
            label, 
            value
        }));
    }

    toggleBlock(event) {
        if(!event?.target?.value) return;

        const element = this.template.querySelector(`div.slds-card__body.slds-card__body_inner[data-type="block"][data-id="${event.target.value}"]`);

        if(!element) return;

        if(event.target.checked) {
            element.classList.remove('slds-hide');
        } else {
            element.classList.add('slds-hide');
        }
    }

    preventUncheck(event) {
        if(!event?.target?.value) return;

        const { checked } = event.target;

        if(!checked) {
            if (event.preventDefault) {
                event.preventDefault();
            } else {
                event.returnValue = false;
            }
        }
    }

    toggleGroupBlock(event) {
        if(!event?.target?.value) return;

        const { checked, value, dataset: { type, group } } = event.target;

        const element = this.template.querySelector(`div.slds-card__body.slds-card__body_inner[data-type="block"][data-id="${value}"]`);

        if(!element) return;

        if(checked) {
            element.classList.remove('slds-hide');
        } else {
            element.classList.add('slds-hide');
        }

        if(!event.isTrusted) return;

        if(checked) {
            const groupInputSelector = `input[data-group="${group}"][data-type="${type}"][type="checkbox"]`;
            const groupCheckboxes = Array.from(this.template.querySelectorAll(groupInputSelector));
            groupCheckboxes.filter(checkbox => checkbox != event.target && checkbox.checked).forEach(checkbox => {
                checkbox.checked = false;
                
                const changeEvent = new CustomEvent('change');
                Object.defineProperty(changeEvent, 'target', {writable: false, value: checkbox});

                checkbox.dispatchEvent(changeEvent);
            });
        }
    }

    @api get payload() {
        const inputSelector = 'c-year-round-assistance-form-input-hgh';
        const maskInputSelector = 'c-year-round-assistance-form-mask-input-hgh';
        const dropdownSelector = 'c-year-round-assistance-form-dropdown-hgh';
        const radioGroupSelector = 'c-year-round-assistance-form-radio-group-hgh';

        const checkedCheckboxes = Array.from(this.template.querySelectorAll('input[data-type="assistance"][type="checkbox"]:checked'));

        const blocksMap = checkedCheckboxes.reduce((result, { name, value }) => {
            const block = this.template.querySelector(`div.slds-card__body.slds-card__body_inner[data-type="block"][data-id="${value}"]`);

            if(!block) return result;

            const inputs = Array.from(block.querySelectorAll(`${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`));

            const fieldsMap = inputs.reduce((data, { name, label, type, value, maskedValue, required, additionalInfo, nodeName }) => ({
                ...data,
                [name]: { name, label, type, value, maskedValue, required, additionalInfo, nodeName }
            }), {});
    
            const fields = inputs.map(({ name, label, type, value, maskedValue, required, additionalInfo, nodeName }) => ({ 
                name, label, type, value, maskedValue, required, additionalInfo, nodeName 
            }));

            return {
                ...result,
                [name]: {
                    assistanceType: name,
                    fields,
                    fieldsMap
                }
            }

        }, {});

        const blocks = Object.values(blocksMap);

        const fields = blocks.reduce((result, { fields }) => [
            ...result,
            ...fields
        ], []);

        const fieldsMap = blocks.reduce((result, { fieldsMap }) => ({
            ...result,
            ...fieldsMap
        }), {});

        return {
            fields,
            fieldsMap,
            blocks,
            blocksMap
        };
    }

    @api validate() {
        const inputSelector = 'c-year-round-assistance-form-input-hgh';
        const maskInputSelector = 'c-year-round-assistance-form-mask-input-hgh';
        const dropdownSelector = 'c-year-round-assistance-form-dropdown-hgh';
        const radioGroupSelector = 'c-year-round-assistance-form-radio-group-hgh';

        const blocks = Array.from(this.template.querySelectorAll('div.slds-card__body.slds-card__body_inner[data-type="block"][data-id]:not(.slds-hide)'));

        const fields = blocks.reduce((result, block) => [
            ...result, 
            ...block.querySelectorAll(`${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`)
        ] , []);

        fields.filter(field => !field.disabled).forEach((field) => {
            let fieldValue = field.value?.trim() || '';
            field.setCustomValidity('');
            if(!fieldValue) {
                field.setCustomValidity('This field is required.');
            } else if ( ['ZipCode', 'PreviousZipCode'].includes(field.name) &&fieldValue == 0) {
                field.setCustomValidity('This field is required.');
            }else if (field.nodeName === radioGroupSelector.toUpperCase() && field.hasAdditionalInfo) {
                let additionalInfo = field.additionalInfo?.trim() || '';
                if(!additionalInfo) {
                    field.setCustomValidity('This field is required.');
                }
            }
        });

        if(blocks.length === 0) {
            if(this.timeout) clearTimeout(this.timeout);

            this.error = true;
            this.timeout = setTimeout(() => this.error = false, 2000);
        }

        return fields.filter(field => !field.disabled && !field.reportValidity());

    }

    
}