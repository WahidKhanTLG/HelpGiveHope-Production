import { LightningElement, api } from 'lwc';

export default class YearRoundAssistanceFormDropdownHgh extends LightningElement {
    @api name;
    @api label;
    @api placeholder;
    @api required;
    _options;
    _explicitValue = false;
    selectedOption = null;
    errorMessage = '';
    showError = false;
    _readOnly = false;

    renderedCallback() {
        if (this.inputEl && this.inputEl.value !== this.value) {
            this.inputEl.value = this.value;
        }
        if (this.inputEl) this.inputEl.disabled = this.readOnly;
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


    @api get readOnly() {
        return this._readOnly === true;
    }

    set readOnly(value) {
        this._readOnly = value === true || /^(true|yes|y)$/i.test(String(value));
        if (this.inputEl) this.inputEl.disabled = this._readOnly;
    }
    @api set options(newValue) {
        this._options = (newValue || []).map(({ label, value, selected }) => ({
            label,
            value,
            selected
        }));

        if (!this._explicitValue) {
            this.selectedOption = this._options.find(option => option.selected)?.value || null;
        }
        this.normalizeSelectedOption();
    }

    normalizeSelectedOption() {
        if (this.selectedOption === null || this.selectedOption === undefined || this.selectedOption === '') return;
        const lookup = String(this.selectedOption).trim().toLowerCase();
        const match = (this._options || []).find(option =>
            String(option.value ?? '').trim().toLowerCase() === lookup ||
            String(option.label ?? '').trim().toLowerCase() === lookup
        );
        if (match) this.selectedOption = match.value;
    }

    get options() {
        const options = this._options || [];
        if (this.selectedOption && !options.some(option => option.value === this.selectedOption)) {
            return [...options, { label: `${this.selectedOption} (saved value - review)`, value: this.selectedOption }];
        }
        return options;
    }

    get placeholderText() {
        return this.placeholder || 'Select an Option...';
    }

    get styling() {
        return this.showError ? 'slds-form-element slds-has-error' : 'slds-form-element';
    }

    @api get value() {
        return this.selectedOption || '';
    } 

    set value(newValue) {
        this._explicitValue = true;
        this.selectedOption = newValue || '';
        this.normalizeSelectedOption();

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
        this._explicitValue = true;
        this.selectedOption = val;

        const changeEvent = new CustomEvent('change', {
            detail: {
                value: val
            }
        });

        this.dispatchEvent(changeEvent);
    }
}