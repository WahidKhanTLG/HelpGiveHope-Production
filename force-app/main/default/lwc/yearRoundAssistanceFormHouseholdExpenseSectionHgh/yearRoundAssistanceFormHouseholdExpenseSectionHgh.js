import { LightningElement, api } from 'lwc';

import MaskConfigs from './mask-configs';

export default class YearRoundAssistanceFormHouseholdExpenseSectionHgh extends LightningElement {
    currencyMaskOption = MaskConfigs.Currency;
    disabledCurrencyMaskOption = MaskConfigs.DisabledCurrency;

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
            fieldsMap,
            expenseSummary: this.expenseSummary
        };
    }

    @api get expenseSummary() {
        let rent = Number(this.refs.rent.value) || 0;
        let utilities = Number(this.refs.utilities.value) || 0;
        let internet = Number(this.refs.internet.value) || 0;
        let groceries = Number(this.refs.groceries.value) || 0;
        let householdNeeds = Number(this.refs.householdNeeds.value) || 0;
        let carPayment = Number(this.refs.carPayment.value) || 0;
        let creditCards = Number(this.refs.creditCards.value) || 0;
        let other = Number(this.refs.other.value) || 0;
        let totalHouseholdExpense = Number(this.refs.totalHouseholdExpense.value) || 0;

        return {
            rent,
            utilities,
            internet,
            groceries,
            householdNeeds,
            carPayment,
            creditCards,
            other,
            totalHouseholdExpense
        };
    }

    calculateHouseholdExpenses(event) {
        let rent = Number(this.refs.rent.value) || 0;
        let utilities = Number(this.refs.utilities.value) || 0;
        let internet = Number(this.refs.internet.value) || 0;
        let groceries = Number(this.refs.groceries.value) || 0;
        let householdNeeds = Number(this.refs.householdNeeds.value) || 0;
        let carPayment = Number(this.refs.carPayment.value) || 0;
        let creditCards = Number(this.refs.creditCards.value) || 0;
        let other = Number(this.refs.other.value) || 0;
        let totalHouseholdExpense = rent + utilities + internet + groceries + householdNeeds + carPayment + creditCards + other;
        
        this.refs.totalHouseholdExpense.value = totalHouseholdExpense > 0 ? totalHouseholdExpense.toFixed(2) : '';

        const expenseChangeEvent = new CustomEvent('expensechange', {
            detail: {
                expenseSummary: this.expenseSummary
            }
        });

        this.dispatchEvent(expenseChangeEvent);
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
            }
        });

        return fields.filter(field => !field.disabled && !field.reportValidity());
    }
}