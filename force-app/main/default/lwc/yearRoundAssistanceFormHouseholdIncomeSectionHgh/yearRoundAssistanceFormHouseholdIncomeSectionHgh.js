import { LightningElement, api } from 'lwc';

import MaskConfigs from './mask-configs';

export default class YearRoundAssistanceFormHouseholdIncomeSectionHgh extends LightningElement {
    disabledNumberMaskOption = MaskConfigs.DisabledNumber;
    disabledCurrencyMaskOption = MaskConfigs.DisabledCurrency;


    _applicant = null;
    _adults = [];
    _children = [];

    @api set applicant(val) {
        this._applicant = val;
    }

    get applicant() {
        return this._applicant;
    }

    @api set adults(val) {
        this._adults = (val || []).filter(adult => !adult.isApplicant);
    }

    get adults() {
        return this._adults;
    }

    @api set children(val) {
        this._children = val || [];
    }

    get children() {
        return this._children;
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
            fields,
            fieldsMap
        };
    }

    @api get numberInHouseHold() {
        return 1 + this.adults.length + this.children.length;
    }

    @api get wages() {
        return this.calculateIncomeByKey('wages');
    }

    @api get disability() {
        return this.calculateIncomeByKey('disability');
    }
    
    @api get tanif() {
        return this.calculateIncomeByKey('tanif');
    }

    @api get ss() {
        return this.calculateIncomeByKey('ss');
    }

    @api get foodStamps() {
        return this.calculateIncomeByKey('foodStamps');
    }

    @api get unemployment() {
        return this.calculateIncomeByKey('unemployment');
    }

    @api get childSupport() {
        return this.calculateIncomeByKey('childSupport');
    }

    @api get other() {
        return this.calculateIncomeByKey('other');
    }

    @api get veterans() {
        return this.calculateIncomeByKey('veterans');
    }
    
    @api get totalIncome() {
        return this.calculateIncomeByKey('totalIncome');
    }
 
    calculateIncomeByKey(key) {
        const allAdults = [this.applicant, ...this.adults].filter(Boolean);

        const total = allAdults.reduce((result, adult) => result + (adult?.incomeSummary?.[key] || 0), 0)

        return total > 0 ? total.toFixed(2) : '';
    }
}