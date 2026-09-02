import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';

import vanillaMask from '@salesforce/resourceUrl/vanillamask';

export default class YearRoundAssistanceFormMaskInputHgh extends LightningElement {
    @api name;
    @api label;
    @api placeholder;
    @api required;
    @api maskOptions;

    _disabled = false;
    _removeLeadingZeros = false;

    errorMessage = '';
    showError = false;

    initialized = false;
    IMask = null;
    mask = null;


    async connectedCallback() {
        await loadScript(this, vanillaMask);

        this.IMask = IMask;

        this.init();
    }

    renderedCallback() {
        this.init();

        if(!this.inputEl || this.disabled === undefined) return;

        this.inputEl.disabled = this.disabled;
    }

    init() {
        if(this.initialized || !this.IMask) return;

        const input = this.template.querySelector(`input[name="${this.name}"]`);
        if(!input) return;

        this.initialized = true;

        /*
            SSN
            {
                mask: 'XXX-XX-0000',
                definitions: {
                    X: {
                        mask: '0',
                        displayChar: 'X',
                        placeholderChar: '#'
                    }
                },
                lazy: false // display placeholder
            }
        
        */

        /*
            Number with Range
            {
                mask: Number,  // enable number mask

                // other options are optional with defaults below
                scale: 0,  // digits after point, 0 for integers
                thousandsSeparator: ',',  // any single char
                padFractionalZeros: false,  // if true, then pads zeros at end to the length of scale
                normalizeZeros: false,  // appends or removes zeros at ends
                radix: ',',  // fractional delimiter
                mapToRadix: ['.'],  // symbols to process as radix

                // additional number interval options (e.g.)
                min: 1,
                max: 5000,
                autofix: false,
                // prepareChar: (value, maskset, pos) => value;
                // prepare: (value, maskset, pos) => value;
                validate: (value, maskset, pos) => {
                    return /^[1-9]/.test(value); // restrict leading zeros
                },
            }
        */

        /*
            Currency
            {
                mask: '$currency', 
                blocks: {
                    currency: {
                        mask: Number,
                        // other options are optional with defaults below
                        scale: 2,  // digits after point, 0 for integers
                        thousandsSeparator: ',',  // any single char
                        padFractionalZeros: false,  // if true, then pads zeros at end to the length of scale
                        normalizeZeros: false,  // appends or removes zeros at ends
                        radix: '.',  // fractional delimiter
                        mapToRadix: ['.'],  // symbols to process as radix

                        // additional number interval options (e.g.)
                        min: 1,
                        max: 2000,
                        autofix: false,
                        // prepareChar: (value, maskset, pos) => value;
                        // prepare: (value, maskset, pos) => value;
                        validate: (value, maskset, pos) => /^[1-9]/.test(value) // restrict leading zeros,
                    }
                }
            }

        */

        this.mask = this.IMask(input, this.maskOptions || {
            mask: /^[\s\S]*$/
        }).on('accept', () => {
            // console.log(this.mask?.value, this.mask?.unmaskedValue, this.mask?.typedValue);

            if(this.removeLeadingZeros) {
                const decimalPoint = /\.$/.test(this.maskedValue) ? '.' : '';
                const hasLeadingZeros = /^\${0,1}0[,0-9]/.test(this.maskedValue);

                if(hasLeadingZeros) {
                    this.mask.value = `${this.value}${decimalPoint}`;
                    return;
                }
            }

            const acceptEvent = new CustomEvent('accept', {
                detail: {
                    value: this.value,
                    mask: this.mask
                }
            });
    
            this.dispatchEvent(acceptEvent);
        });
    }

    get id() {
        return this.name.replaceAll(/[^a-zA-Z0-9]+/g, '-')
    }

    get inputEl() {
        return this.template.querySelector(`input[name=${this.name}]`);
    }

    @api get disabled() {
        return this._disabled === true;
    }

    set disabled(value) {
        this._disabled = /^(true|yes|y)$/i.test(value);
        
        if(!this.inputEl) return;
        this.inputEl.disabled = this._disabled;
        
        if(this._disabled) {
            this.value = '';
            this.setCustomValidity('');
            this.reportValidity();
        }
    }

    @api get removeLeadingZeros() {
        return this._removeLeadingZeros === true;
    }

    set removeLeadingZeros(value) {
        this._removeLeadingZeros = /^(true|yes|y)$/i.test(value);
    }

    // @api get displayedValue() {
    //     return this.mask?.unmaskedValue || '';
    // }

    @api get maskedValue() {
        return this.mask?.value || '';
    }

    @api get value() {
        return this.mask?.typedValue.toString() || '';
    }

    set value(newValue) {
        if(this.mask) {
            this.mask.value = (newValue || '').toString();
        } else {
            const inputEl = this.inputEl;
            if(inputEl) inputEl.value = (newValue || '').toString();
        }
    }

    @api setCustomValidity(errorMessage) {
        this.errorMessage = (errorMessage || '').trim();
    }

    @api reportValidity() {
        this.showError = this.errorMessage && true;
        this.showError && this.scrollIntoView();
        return !this.showError;
    }
    
    @api scrollIntoView() {
        const containerEl = this.template.querySelector(`div[data-id="container"]`);
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

    blurHandler(event) {
        const blurEvent = new CustomEvent('blur', {
            detail: {
                value: this.value,
                mask: this.mask
            }
        });

        this.dispatchEvent(blurEvent);
    }

    changeHandler(event) {
        const changeEvent = new CustomEvent('change', {
            detail: {
                value: this.value,
                mask: this.mask
            }
        });

        this.dispatchEvent(changeEvent);
    }
}