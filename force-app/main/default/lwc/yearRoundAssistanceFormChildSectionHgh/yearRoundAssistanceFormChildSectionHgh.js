import { prefillValues, ageOnDate } from "c/hghHouseholdReuseUtils";
import { LightningElement, api, wire } from 'lwc';

import getPicklistValues from '@salesforce/apex/YearRoundAssistanceFormController.getPicklistValues';

import DropdownOptions from './dropdown-options';
import RadioGroupOptions from './radio-group-options';
import MaskConfigs from './mask-configs';

export default class YearRoundAssistanceFormChildSectionHgh extends LightningElement {
  _initialData = null;
  _prefillPending = false;
  @api set initialData(value) {
    if (value === this._initialData) return;
    this._initialData = value || null;
    this._prefillPending = Boolean(value);
  }
  get initialData() { return this._initialData; }
  get storedSsn() { return this._initialData?.hasSsn === true; }
  get storedSsnDisplay() { return this._initialData?.ssnDisplay || "Stored (read only)"; }
  get ssnReadOnly() { return this.storedSsn || this._initialData?.ssnReadOnly === true; }
  get existingRecordId() { return this._initialData?.recordId || null; }
  _readOnly = false;

  @api get readOnly() {
    return this._readOnly === true;
  }

  set readOnly(value) {
    this._readOnly = value === true || /^(true|yes|y)$/i.test(String(value));
    this.applyReadOnlyState();
  }

  renderedCallback() {
    if (this._prefillPending) {
      this._prefillPending = false;
      this.applyInitialData();
    }
    this.applyReadOnlyState();
  }

  applyReadOnlyState() {
    const selector = [
      "c-year-round-assistance-form-input-hgh",
      "c-year-round-assistance-form-dropdown-hgh",
      "c-year-round-assistance-form-mask-input-hgh",
      "c-year-round-assistance-form-radio-group-hgh"
    ].join(",");

    Array.from(this.template.querySelectorAll(selector)).forEach((field) => {
      if (field.name === "SSN" && this.ssnReadOnly) {
        field.readOnly = true;
        return;
      }
      field.readOnly = this._readOnly;
    });
  }

  applyInitialData() {
    const values = prefillValues(this._initialData);
    const selector = [
      "c-year-round-assistance-form-input-hgh",
      "c-year-round-assistance-form-dropdown-hgh",
      "c-year-round-assistance-form-mask-input-hgh"
    ].join(",");

    const fields = Array.from(this.template.querySelectorAll(selector));

    fields.forEach((field) => {
      if (!field?.name || !Object.prototype.hasOwnProperty.call(values, field.name)) {
        return;
      }

      if (field.name === "SSN" && this.storedSsn) {
        return;
      }

      field.value = values[field.name] ?? "";
    });

    // Age is derived from the loaded DOB. It is not loaded from historical data.
    if (this.refs?.age) {
      this.refs.age.value = ageOnDate(values.DateOfBirth);
    }

    this.dispatchEvent(new CustomEvent("prefillready"));
  }

    _title;

    genderOptions = DropdownOptions.GenderOptions;
    relationShipOptions = DropdownOptions.RelationShipOptions;

    schoolAttendingOptions = RadioGroupOptions.SchoolAttendingOptions;
    legalGuardianOptions = []; // RadioGroupOptions.LegalGuardianOptions;
    ssnMaskOption = MaskConfigs.SSN;
    duplicateMessage = "";
    

    @wire(getPicklistValues) /* { 'userId': '$loginId' } */
    getPicklistValuesHandler({data, error}) {
        if(data) {
            this.genderOptions = this.mapToDropdownOptions(data.GenderIdentity);
            this.relationShipOptions = this.mapToDropdownOptions(data.npe4__Type__c);
            
            this.legalGuardianOptions = this.mapToRadioGroupOptions(data.TLG_Are_you_their_legal_guardian__c);
            // Gender/options arrive asynchronously. Re-run prefill after the
            // options exist so a stored value is selected reliably.
            if (this._initialData) this._prefillPending = true;
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
      recordId: this.existingRecordId,
      storedSsn: this.storedSsn,
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
    if (this.refs?.age) this.refs.age.value = ageOnDate(event.detail?.value || "");
  }

  handleSsnBlur() {
    const field = this.template.querySelector(
      'c-year-round-assistance-form-mask-input-hgh[name="SSN"]'
    );
    if (!field || field.readOnly) return;

    const digits = String(field.value || "").replace(/\D/g, "");
    field.setCustomValidity(
      digits.length === 0 || digits.length === 9
        ? ""
        : "SSN must contain exactly 9 digits."
    );
    field.reportValidity();
  }

    @api validate() {
    if (this.readOnly) return [];
        const inputSelector = 'c-year-round-assistance-form-input-hgh';
        const maskInputSelector = 'c-year-round-assistance-form-mask-input-hgh';
        const dropdownSelector = 'c-year-round-assistance-form-dropdown-hgh';
        const radioGroupSelector = 'c-year-round-assistance-form-radio-group-hgh';
        const fields = Array.from(this.template.querySelectorAll(`${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`));
        
        fields.filter(field => !field.disabled && !field.readOnly).forEach((field) => {
            let fieldValue = field.value?.trim() || '';
            field.setCustomValidity('');
            if(!fieldValue) {
                field.setCustomValidity(/^(true|yes|y)$/i.test(String(field.required)) ? 'This field is required.' : '');
            } else if (field.name === 'SSN' && !/^\d{9}$/.test(fieldValue.replaceAll('-', ''))) {
                field.setCustomValidity('SSN must contain 9 digits.');
            } else if (field.dataset.type === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fieldValue)) {
                field.setCustomValidity('Must be a valid email address.');
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

        return fields.filter(field => !field.disabled && !field.readOnly && !field.reportValidity());
    }
}