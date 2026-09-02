import { LightningElement, api } from 'lwc';

export default class CheckboxToggleInput extends LightningElement {
    @api name;
    @api label;
    @api enableLabel = 'Yes';
    @api disableLabel = 'No';
    @api required;

    _disabled = false;
    _checked = false;

    initialValue = '';
    errorMessage = '';
    showError = false;

    renderedCallback() {
        if(!this.inputEl) return;

        this.inputEl.disabled = this.disabled;
    }

    normalizeBoolean(value) {
        return value === true || /^(true|yes|y|1)$/i.test(String(value || ''));
    }

    get id() {
        return this.name.replaceAll(/[^a-zA-Z0-9]+/g, '-')
    }

    get inputEl() {
        return this.template.querySelector(`input[name=${this.name}]`);
    }

    get styling() {
        return this.showError ? 'slds-form-element slds-has-error' : 'slds-form-element';
    }

    @api get disabled() {
        return this._disabled;
    }

    set disabled(value) {
        this._disabled = this.normalizeBoolean(value);
    }

    @api get checked() {
        return this._checked;
    }

    set checked(value) {
        this._checked = this.normalizeBoolean(value);
    }

    @api get value() {
        return this.checked;
    } 

    set value(newValue) {
        this._checked = this.normalizeBoolean(newValue);
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
        const checked = event.target.checked;
        const value = checked;
        
        this._checked = checked;
        
        const changeEvent = new CustomEvent('change', {
            detail: { checked, value }
        });

        this.dispatchEvent(changeEvent);
    }

    toggleClickHandler(ev) {
        this.inputEl.checked = !this.checked;
        this.inputEl.dispatchEvent(new Event('change'));
    }
}