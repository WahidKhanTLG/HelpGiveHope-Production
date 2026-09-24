import { prefillValues, ageOnDate } from "c/hghHouseholdReuseUtils";
import { LightningElement, api, wire } from "lwc";

import getPicklistValues from "@salesforce/apex/YearRoundAssistanceFormController.getPicklistValues";

import MaskConfigs from "./mask-configs";
import DropdownOptions from "./dropdown-options";

import getPreviousStates from "@salesforce/apex/PreviousAddressMetadataController.getPreviousStates";
import getPreviousCities from "@salesforce/apex/PreviousAddressMetadataController.getPreviousCities";
import getPreviousZipCodes from "@salesforce/apex/PreviousAddressMetadataController.getPreviousZipCodes";

export default class YearRoundAssistanceFormApplicantSectionHgh extends LightningElement {
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

      // Existing SSNs are already rendered as masked/read-only values.
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
  _isApplicant = true;

  isCustomRelationship = false;
  isEmployed = false;
  showPreviousAddressFields = false;
  showPreviousEmploymentFields = false;
  genderOptions = DropdownOptions.GenderOptions;

  zipCodeOptions = DropdownOptions.ZipCodeOptions;
  cityOptions = DropdownOptions.CityOptions;
  stateOptions = DropdownOptions.StateOptions;

  previousStateOptions = DropdownOptions.NoneOption;
  previousCityOptions = DropdownOptions.NoneOption;
  previousZipCodeOptions = DropdownOptions.NoneOption;

  isPreviousCityLoading = false;
  isPreviousZipLoading = false;

  selectedPreviousState = "";
  selectedPreviousCity = "";

  employmentStatusOptions = []; // DropdownOptions.EmploymentStatusOptions;
  relationShipOptions = []; // DropdownOptions.RelationShipOptions;

  ssnMaskOption = MaskConfigs.SSN;
  phoneMaskOption = MaskConfigs.Phone;
  monthsOfEmploymentOrUnemploymentMaskOption =
  MaskConfigs.MonthsOfEmploymentOrUnemployment;
  hoursWorkedPerWeekMaskOption = MaskConfigs.HoursWorkedPerWeek;
  payPerHourMaskOption = MaskConfigs.PayPerHour;
  numberMax2000MaskOption = MaskConfigs.NumberMax2000;
  numberMax5000MaskOption = MaskConfigs.NumberMax5000;
  disabledCurrencyMaskOption = MaskConfigs.DisabledCurrency;


  @wire(getPicklistValues) /* { 'userId': '$loginId' } */
  getPicklistValuesHandler({ data, error }) {
    if (data) {
      this.employmentStatusOptions = this.mapToDropdownOptions(
        data.TLG_Employed_or_unemployed__c
      );
      this.relationShipOptions = this.mapToDropdownOptions(data.Adult_Type__c); // this.mapToDropdownOptions(data.npe4__Type__c);
      // Only override default gender options if Apex returns values
      const mappedGender = this.mapToDropdownOptions(data.GenderIdentity);
      if (Array.isArray(mappedGender) && mappedGender.length > 0) {
        this.genderOptions = mappedGender;
      }
      // Picklist options are loaded asynchronously. Re-apply saved values
      // after the options exist so Gender is selected for existing records.
      if (this._initialData) this._prefillPending = true;
    } else if (error) {
      console.log(error);
    }
  }

  connectedCallback() {
    this.loadPreviousStates();
  }

  async loadPreviousStates() {
  try {
    const results = await getPreviousStates();
    console.log('States from Apex:', JSON.stringify(results));
    this.previousStateOptions = results?.length
      ? results
      : DropdownOptions.NoneOption;
  } catch (error) {
    console.error("Error loading previous states", JSON.stringify(error));
    this.previousStateOptions = DropdownOptions.NoneOption;
  }
}

  mapToDropdownOptions(picklistOptions) {
    return (picklistOptions || []).map(({ value, label }) => ({
      label,
      value,
      selected: false
    }));
  }

  @api assistanceType;
  christmasConsent = false;

  get isChristmasFlow() {
      return (this.assistanceType || '').toLowerCase().includes('christmas');
  }

  @api set title(value) {
    this._title = (value || "").toString();
  }

  get title() {
    return this._title || "Applicant";
  }

  @api set isApplicant(value) {
    let val = (value === false ? value : value || "").toString();
    this._isApplicant = val === "" || /^(true|yes|y)$/i.test(val);
  }

  get isApplicant() {
    return this._isApplicant !== false;
  }

  get isAdult() {
    return this._isApplicant !== true;
  }

  duplicateMessage = "";

  get isDuplicate() {
      return !!this.duplicateMessage;
  }

  get cardClass() {
      return this.isDuplicate ? "hgh-section-card hgh-section-card--duplicate" : "hgh-section-card";
  }

  @api clearDuplicateValidation() {
      this.duplicateMessage = "";
  }

  @api setDuplicateValidation(message = "Duplicate entry detected.") {
      this.duplicateMessage = message;
  }

  @api get payload() {
    const inputSelector = "c-year-round-assistance-form-input-hgh";
    const maskInputSelector = "c-year-round-assistance-form-mask-input-hgh";
    const dropdownSelector = "c-year-round-assistance-form-dropdown-hgh";
    const radioGroupSelector = "c-year-round-assistance-form-radio-group-hgh";
    const inputs = Array.from(
      this.template.querySelectorAll(
        `${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`
      )
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

    if (this.isChristmasFlow && this.isApplicant) {
      fieldsMap.ChristmasConsent = {
        name: "ChristmasConsent",
        label: "Christmas Consent",
        type: "toggle",
        value: this.christmasConsent,
        maskedValue: this.christmasConsent,
        required: false,
        additionalInfo: null,
        nodeName: "LIGHTNING-INPUT"
      };

      fields.push({
        name: "ChristmasConsent",
        label: "Christmas Consent",
        type: "toggle",
        value: this.christmasConsent,
        maskedValue: this.christmasConsent,
        required: false,
        additionalInfo: null,
        nodeName: "LIGHTNING-INPUT"
      });
    }   

    return {
      title: this.title,
      recordId: this.existingRecordId,
      storedSsn: this.storedSsn,
      isApplicant: this.isApplicant,
      fields,
      fieldsMap,
      computedFields: this.computedFields,
      incomeSummary: this.incomeSummary
    };
  }

  @api get computedFields() {
    return {
      age: Number(this.refs?.age?.value) || 0,
      wages: Number(this.refs?.wages?.value) || 0,
      totalIncome: Number(this.refs?.totalIncome?.value) || 0
    };
  }

  @api get incomeSummary() {
    let hoursWorkedPerWeek = Number(this.refs?.hoursWorkedPerWeek?.value) || 0;
    let payPerHour = Number(this.refs?.payPerHour?.value) || 0;

    let wages = Number(this.refs?.wages?.value) || 0;
    let disability = Number(this.refs?.disability?.value) || 0;
    let tanif = Number(this.refs?.tanif?.value) || 0;
    let ss = Number(this.refs?.ss?.value) || 0;
    let foodStamps = Number(this.refs?.foodStamps?.value) || 0;
    let unemployment = Number(this.refs?.unemployment?.value) || 0;
    let childSupport = Number(this.refs?.childSupport?.value) || 0;
    let other = Number(this.refs?.other?.value) || 0;
    let veterans = Number(this.refs?.veterans?.value) || 0;

    let totalIncome = Number(this.refs?.totalIncome?.value) || 0;

    return {
      hoursWorkedPerWeek,
      payPerHour,
      wages,
      disability,
      tanif,
      ss,
      foodStamps,
      unemployment,
      childSupport,
      other,
      veterans,
      totalIncome
    };
  }

  get minimumDateHtmlAttribute() {
    const dt = new Date(1900, 0, 1);
    return this.convertDateToString(dt);
  }

  get maximumDateHtmlAttribute() {
    const today = new Date();
    const dt = new Date(
      today.getFullYear() - 18,
      today.getMonth(),
      today.getDate()
    );
    return this.convertDateToString(dt);
  }

  // get todayHtmlAttribute() {
  //     const today = new Date();
  //     return this.convertDateToString(today);
  // }

  convertDateToString(dt) {
    const year = dt.getFullYear();
    const month = (dt.getMonth() + 1).toString().padStart(2, "0");
    const date = dt.getDate().toString().padStart(2, "0");

    return `${year}-${month}-${date}`;
  }

  convertDateToReadableString(dt) {
    dt = new Date(dt);

    if (isNaN(dt)) dt = new Date();

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    const year = dt.getFullYear();
    const month = months[dt.getMonth()];
    const date = dt.getDate().toString().padStart(2, "0");

    return `${month} ${date}, ${year}`;
  }

  relationShipChangeHandler(event) {
    const selectedValue = event.detail.value || "";

    this.isCustomRelationship = selectedValue === "Other";
  }

  employmentStatusChangeHandler(event) {
    const selectedValue = event.detail.value || "";

    this.isEmployed = selectedValue === "Employed";

    const { hoursWorkedPerWeek, payPerHour, unemployment } = this.refs;

    if (!hoursWorkedPerWeek || !payPerHour || !unemployment) return;

    if (selectedValue === "Employed") {
      hoursWorkedPerWeek.disabled = false;
      payPerHour.disabled = false;
      unemployment.disabled = true;
    } else if (selectedValue === "Unemployed") {
      hoursWorkedPerWeek.disabled = true;
      payPerHour.disabled = true;
      unemployment.disabled = false;
    }
  }

  addressMonthsChangeHandler() {
    const months = Number(this.refs.monthsAtCurrentAddress?.value) || 0;
    this.showPreviousAddressFields = months > 0 && months < 36;

    if (!this.showPreviousAddressFields) {
    this.selectedPreviousState = "";
    this.selectedPreviousCity = "";
    this.previousCityOptions = DropdownOptions.NoneOption;
    this.previousZipCodeOptions = DropdownOptions.NoneOption;

    if (this.refs.previousState) {
      this.refs.previousState.value = "";
    }
    if (this.refs.previousCity) {
      this.refs.previousCity.value = "";
    }
    if (this.refs.previousZipCode) {
      this.refs.previousZipCode.value = "";
    }
  }
  }

  monthsChangeHandler() {
    const months =
      Number(this.refs.monthsOfEmploymentOrUnemployment?.value) || 0;
    this.showPreviousEmploymentFields = months > 0 && months < 36;
  }

  calculateAge(event) {
    if (this.refs?.age) this.refs.age.value = ageOnDate(event.detail?.value || "");
  }

  calculateMonthlyWages(event) {
    let hoursWorkedPerWeek = Number(this.refs.hoursWorkedPerWeek.value) || 0;
    let payPerHour = Number(this.refs.payPerHour.value) || 0;
    let income = "";

    if (hoursWorkedPerWeek > 0 && payPerHour > 0) {
      income = (hoursWorkedPerWeek * payPerHour * 4.23).toFixed(2);
    }

    this.refs.wages.value = income;

    this.calculateTotalIncome(event);
  }

  calculateTotalIncome() {
    let wages = Number(this.refs.wages.value) || 0;
    let disability = Number(this.refs.disability.value) || 0;
    let tanif = Number(this.refs.tanif.value) || 0;
    let ss = Number(this.refs.ss.value) || 0;
    let foodStamps = Number(this.refs.foodStamps.value) || 0;
    let unemployment = Number(this.refs.unemployment.value) || 0;
    let childSupport = Number(this.refs.childSupport.value) || 0;
    let other = Number(this.refs.other.value) || 0;
    let veterans = Number(this.refs.veterans.value) || 0;
    let totalIncome =
      wages +
      disability +
      tanif +
      ss +
      foodStamps +
      unemployment +
      childSupport +
      other +
      veterans;

    this.refs.totalIncome.value = totalIncome > 0 ? totalIncome.toFixed(2) : "";

    const incomeChangeEvent = new CustomEvent("incomechange", {
      detail: {
        incomeSummary: this.incomeSummary
      }
    });

    this.dispatchEvent(incomeChangeEvent);
  }

  validateSSN(ssn) {
    return /^\d{9}$/.test(String(ssn || "").replaceAll("-", ""));
  }

  validatePhone(phone) {
    return /\d{11}/.test(phone);
  }

  validateEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
  }

  handleChristmasConsentChange(event) {
    this.christmasConsent = event.target.checked;
  }

  getFormattedDropdownOptions(values = []) {
    return values.map((value) => ({
      label: value,
      value,
      selected: false
    }));
  }

  async handlePreviousStateChange(event) {
    const selectedState = event.detail?.value || event.target?.value || "";
    this.selectedPreviousState = selectedState;
    this.selectedPreviousCity = "";

    this.previousCityOptions = DropdownOptions.NoneOption;
    this.previousZipCodeOptions = DropdownOptions.NoneOption;

    if (this.refs.previousCity) {
      this.refs.previousCity.value = "";
    }
    if (this.refs.previousZipCode) {
      this.refs.previousZipCode.value = "";
    }

    if (!selectedState) {
      this.isPreviousCityLoading = false;
      return;
    }

    this.isPreviousCityLoading = true;

    await new Promise((resolve) => setTimeout(resolve, 100));

    try {
      const results = await getPreviousCities({ stateCode: selectedState });
      this.previousCityOptions = results?.length
        ? results
        : DropdownOptions.NoneOption;
    } catch (error) {
      console.error("Error loading previous cities", error);
      this.previousCityOptions = DropdownOptions.NoneOption;
    } finally {
      this.isPreviousCityLoading = false;
    }
  }
    
  async handlePreviousCityChange(event) {
    const selectedCity = event.detail?.value || event.target?.value || "";
    this.selectedPreviousCity = selectedCity;

    this.previousZipCodeOptions = DropdownOptions.NoneOption;

    if (this.refs.previousZipCode) {
      this.refs.previousZipCode.value = "";
    }

    if (!this.selectedPreviousState || !selectedCity) {
      this.isPreviousZipLoading = false;
      return;
    }

    this.isPreviousZipLoading = true;

    await new Promise((resolve) => setTimeout(resolve, 100));

    try {
      const results = await getPreviousZipCodes({
        stateCode: this.selectedPreviousState,
        cityName: selectedCity
      });

      this.previousZipCodeOptions = results?.length
        ? results
        : DropdownOptions.NoneOption;
    } catch (error) {
      console.error("Error loading previous zip codes", error);
      this.previousZipCodeOptions = DropdownOptions.NoneOption;
    } finally {
      this.isPreviousZipLoading = false;
    }
  }
  @api validate() {
    if (this.readOnly) return [];
    const inputSelector = "c-year-round-assistance-form-input-hgh";
    const maskInputSelector = "c-year-round-assistance-form-mask-input-hgh";
    const dropdownSelector = "c-year-round-assistance-form-dropdown-hgh";
    const radioGroupSelector = "c-year-round-assistance-form-radio-group-hgh";
    const fields = Array.from(
      this.template.querySelectorAll(
        `${inputSelector},${maskInputSelector},${dropdownSelector},${radioGroupSelector}`
      )
    );

    fields
      .filter((field) => !field.disabled && !field.readOnly)
      .forEach((field) => {
        let fieldValue = field.value?.trim() || "";
        field.setCustomValidity("");

        if (!fieldValue) {
          field.setCustomValidity(
            /^(true|yes|y)$/i.test(String(field.required)) ? "This field is required." : ""
          );
        } else if (
          fieldValue === "0" &&
          [
            "MonthsOfEmploymentOrUnemployment",
            "JobsPast36Months",
            "HoursWorkedPerWeek",
            "TotalTimeEmployed",
            "monthsAtCurrentAddress",
            "PreviousAddressDuration"
          ].indexOf(field.name) + 1
        ) {
          field.setCustomValidity("Minimum value must be 1.");
        } else if (field.dataset.type === "date") {
          if (isNaN(new Date(fieldValue))) {
            field.setCustomValidity("Must be a valid date.");
          } else if (
            fieldValue < this.minimumDateHtmlAttribute ||
            fieldValue > this.maximumDateHtmlAttribute
          ) {
            const minDate = this.convertDateToReadableString(
              this.minimumDateHtmlAttribute
            );
            const maxDate = this.convertDateToReadableString(
              this.maximumDateHtmlAttribute
            );

            field.setCustomValidity(
              `The date should be between ${minDate} and ${maxDate}.`
            );
          }
        } else if (field.name === "SSN" && !this.validateSSN(fieldValue)) {
          field.setCustomValidity("SSN must contain 9 digits.");
        } else if (field.name === "Phone" && !this.validatePhone(fieldValue)) {
          field.setCustomValidity("Phone must contain 11 digits.");
        } else if (field.name === "HowLongEmployedThere") {
          const numValue = Number(fieldValue);
          if (!Number.isFinite(numValue)) {
            field.setCustomValidity("Value must be a number.");
          }
        }  else if (
          field.dataset.type === "email" &&
          !this.validateEmail(fieldValue)
        ) {
          field.setCustomValidity("Must be a valid email address.");
        } else if (
          field.nodeName === radioGroupSelector.toUpperCase() &&
          field.hasAdditionalInfo
        ) {
          let additionalInfo = field.additionalInfo?.trim() || "";
          if (!additionalInfo) {
            field.setCustomValidity("This field is required.");
          }
        }
      });

    return fields.filter((field) => !field.disabled && !field.readOnly && !field.reportValidity());
  }

  
}