import { LightningElement, api } from 'lwc';

export default class YearRoundAssistanceFormDropdownHgh extends LightningElement {
    @api name;
    @api label;
    @api placeholder;
    @api required;
    _options;
    selectedOption = null;
    errorMessage = '';
    showError = false;

    renderedCallback() {
        if (this.inputEl && this.inputEl.value !== this.value) {
            this.inputEl.value = this.value;
        }
    }

    get id() {
        return this.name.replaceAll(/[^a-zA-Z0-9]+/g, '-')
    }

    get inputEl() {
        return this.template.querySelector('select');
    }

    get isRequired() {
        return /^(true|yes|y)$/i.test(this.required);
    }

    @api set options(newValue) {
        this._options = (newValue || []).map(({ label, value, selected }) => ({
            label,
            value,
            selected
        }));

        this.selectedOption = this._options.find(option => option.selected)?.value || null;
    }

    get options() {
        return this._options || [];
    }

    get placeholderText() {
        return this.placeholder || 'Select an Option...';
    }

    get styling() {
        return this.showError ? 'slds-form-element slds-has-error' : 'slds-form-element';
    }

    @api get value() {
        return this.inputEl?.value || this.selectedOption || '';
    } 

    set value(newValue) {
        this.selectedOption = newValue || '';

        if (this.inputEl) {
            this.inputEl.value = this.selectedOption;
        }
    }

    @api setCustomValidity(errorMessage) {
        this.errorMessage = (errorMessage || '').trim();
    }

    @api reportValidity() {
        this.showError = Boolean(this.errorMessage);
        this.showError && this.scrollIntoView();
        return !this.showError;
    }
    
    @api scrollIntoView() {
        const containerEl = this.template.querySelector(`div[data-id="container"]`);
        if(!containerEl) return;

        const y = containerEl.getBoundingClientRect().top + globalThis.scrollY;
        globalThis.scroll({
            top: y,
            behavior: 'smooth'
        });
    }

    changeHandler(event) {
        const val = event.target.value || '';
        this.selectedOption = val;

        const changeEvent = new CustomEvent('change', {
            detail: {
                value: val
            }
        });

        this.dispatchEvent(changeEvent);
    }
}