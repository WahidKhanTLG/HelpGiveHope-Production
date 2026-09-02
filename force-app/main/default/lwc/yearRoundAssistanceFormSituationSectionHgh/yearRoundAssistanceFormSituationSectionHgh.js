import { LightningElement, api } from "lwc";

import MaskConfigs from "./mask-configs";

export default class YearRoundAssistanceFormSituationSectionHgh extends LightningElement {
  @api assistanceType;
  _title;
  monthsMaskOption = MaskConfigs.MonthsOfEmploymentOrUnemployment;

  @api set title(value) {
    this._title = (value || "").toString();
  }

  get title() {
    return this._title || "Household History";
  }

  get showSituationField() {
    return (
      this.assistanceType === "Year Round Assitance" ||
      this.assistanceType === "User/Repair Car Assitance"
    );
  }

  @api get payload() {
    const inputSelector = "c-year-round-assistance-form-input-hgh";
    const checkboxSelector = "c-checkbox-toggle-input";
    const inputs = Array.from(
      this.template.querySelectorAll(`${inputSelector},${checkboxSelector}`)
    );

    const fieldsMap = inputs.reduce(
      (
        data,
        {
          name,
          label,
          type,
          value,
          maskedValue,
          required,
          additionalInfo,
          nodeName
        }
      ) => ({
        ...data,
        [name]: {
          name,
          label,
          type,
          value,
          maskedValue,
          required,
          additionalInfo,
          nodeName
        }
      }),
      {}
    );

    const fields = inputs.map(
      ({
        name,
        label,
        type,
        value,
        maskedValue,
        required,
        additionalInfo,
        nodeName
      }) => ({
        name,
        label,
        type,
        value,
        maskedValue,
        required,
        additionalInfo,
        nodeName
      })
    );

    return {
      title: this.title,
      fields,
      fieldsMap
    };
  }

  @api validate() {
    const inputSelector = "c-year-round-assistance-form-input-hgh";
    const checkboxSelector = "c-checkbox-toggle-input";
    const fields = Array.from(
      this.template.querySelectorAll(`${inputSelector},${checkboxSelector}`)
    );

    // Use the getValueForSave API for checkboxToggleInput if available
    fields
      .filter((field) => !field.disabled)
      .forEach((field) => {
        // Check if it's a checkbox toggle input with the new API
        if (
          field.tagName.toLowerCase() === "c-checkbox-toggle-input" &&
          typeof field.getValueForSave === "function"
        ) {
          field.getValueForSave();
          return;
        }

        // For other input types
        const fieldValue = field.value?.toString()?.trim() || "";
        field.setCustomValidity("");
        if (!fieldValue && field.required) {
          field.setCustomValidity("This field is required.");
        } 
        // else if (
        //   field.name === 'ResidencyLengthMonths' &&
        //   fieldValue === '0'
        // ) {
        //   field.setCustomValidity('Minimum value must be 1.');
        // }
      });

    return fields.filter((field) => !field.disabled && !field.reportValidity());
  }
}