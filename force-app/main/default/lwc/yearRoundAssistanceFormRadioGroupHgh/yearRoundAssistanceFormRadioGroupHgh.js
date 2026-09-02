import { LightningElement, api } from 'lwc';

export default class YearRoundAssistanceFormRadioGroupHgh extends LightningElement {
    @api name;
    @api label;
    @api required;
    @api options;
    errorMessage = '';
    showError = false;

    prefix = null;

    connectedCallback() {
        // if(this.prefix === null) return;
        this.prefix = `${Date.now().toString(36)}${Math.random().toString(36).substring(2)}`.toUpperCase();
    }

    get id() {
        return this.name.replaceAll(/[^a-zA-Z0-9]+/g, '-')
    }

    get uniqueName() {
        return `${this.prefix}--${this.name}`;
    }

    @api get value() {
        const inputEl = this.template.querySelector(`input[name=${this.uniqueName}]:checked`);
        return inputEl?.value || '';
    } 

    set value(newValue) {
        const inputEl = this.template.querySelector(`input[name=${this.uniqueName}][value="${newValue}"]`);
        if(inputEl) inputEl.checked = true;
    }

    @api get hasAdditionalInfo() {
        let selectedOption = this.options.find(({ value }) => value === this.value);
        if(!selectedOption || !selectedOption.additionalInfo) return false;

        return (
            selectedOption.additionalInfo == true 
            || toString.call(selectedOption.additionalInfo) === '[object Object]'
        )
    }

    @api get additionalInfo() {
        const inputEl = this.template.querySelector(`input[name="AdditionalInfo"]`);
        return inputEl?.value || '';
    } 

    @api setCustomValidity(errorMessage) {
        this.errorMessage = (errorMessage || '').trim();
    }

    @api reportValidity() {
        this.showError = this.errorMessage && true;
        return !this.showError;
    }
    
    @api scrollIntoView() {
        const containerEl = this.template.querySelector(`fieldset[data-id="container"]`);
        if(!containerEl) return;

        const y = containerEl.getBoundingClientRect().top + window.scrollY;
        window.scroll({
            top: y,
            behavior: 'smooth'
        });
    }

    get styling() {
        return this.showError ? 'slds-form-element slds-has-error' : 'slds-form-element';
    }
    
    get optionList() {
        return this.options.map(({ label, value, additionalInfo }) => {

            const hasAdditionalInfo = (
                additionalInfo == true 
                || toString.call(additionalInfo) === '[object Object]'
            );
            const placeholder = (additionalInfo?.placeholder || '').toString().trim();

            return ({
                key: `${this.uniqueName}--${value}`,
                label,
                value,
                additionalInfo: {
                    show: (hasAdditionalInfo && this.value === value),
                    fieldContainerStyling: (hasAdditionalInfo && this.value === value) ? 'slds-radio has-description-box' : 'slds-radio',
                    placeholder
                }
            })
        });
    }

    changeHandler(event) {
        this.options = [...this.options];

        const changeEvent = new CustomEvent('change', {
            detail: {
                value: this.value,
                additionalInfo: this.additionalInfo
            }
        });

        this.dispatchEvent(changeEvent);
    }

    additionalInfoChangeHandler() {
        const changeEvent = new CustomEvent('changeinfo', {
            detail: {
                value: this.value,
                additionalInfo: this.additionalInfo
            }
        });

        this.dispatchEvent(changeEvent);
    }

    additionalInfoBlurHandler() {
        const changeEvent = new CustomEvent('blurinfo', {
            detail: {
                value: this.value,
                additionalInfo: this.additionalInfo
            }
        });

        this.dispatchEvent(changeEvent);
    }

    additionalInfoInputHandler() {
        const changeEvent = new CustomEvent('inputinfo', {
            detail: {
                value: this.value,
                additionalInfo: this.additionalInfo
            }
        });

        this.dispatchEvent(changeEvent);
    }
}