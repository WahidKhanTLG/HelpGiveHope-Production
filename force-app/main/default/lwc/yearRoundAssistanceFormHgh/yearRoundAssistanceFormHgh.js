import { LightningElement, api, wire } from "lwc";

import getPicklistValues from "@salesforce/apex/YearRoundAssistanceFormController.getPicklistValues";
import getPovertyGuidelines from "@salesforce/apex/YearRoundAssistanceFormController.getPovertyGuidelines";
import save from "@salesforce/apex/YearRoundAssistanceFormController.save";
import getFormStatus from "@salesforce/apex/FormVisibilityController.getFormStatus";

import LOGO from "@salesforce/resourceUrl/LogoFull";
import Origin from "@salesforce/schema/Case.Origin";

const PAGE1 = "PAGE1";
const PAGE2 = "PAGE2";
const PAGE3 = "PAGE3";
const DEFAULT_FORM_TITLE = "Assistance Application";
const ASSISTANCE_TYPE_CONFIG = Object.freeze({
  "Year Round Assitance": {
    title: "General Assistance Application",
    caseType: "Year Round Assistance",
    accountSuffix: "General Assistance",
    visibilityFormName: "GeneralAssistance"
  },
  "User/Repair Car Assitance": {
    title: "Used Car / Car Repair Application",
    caseType: "Used Car Assistance",
    accountSuffix: "Used Car/Car Repair Program",
    visibilityFormName: "UsedCar"
  },
  "Christmas Assitance": {
    title: "Christmas Assistance Application",
    caseType: "Christmas Assistance",
    accountSuffix: "Christmas Assistance",
    visibilityFormName: "Christmas"
  }
});
const ASSISTANCE_BLOCK_FIELD_MAP = Object.freeze({
  TLG_Utility_Assistance__c: "UtilityAssistance",
  TLG_Rent_Assistance__c: "RentAssistance",
  TLG_Educational_Assistance__c: "EducationalAssistance",
  TLG_Other_Assistance__c: "OtherAssistance",
  TLG_Used_Car_Assistance__c: "UserCarAssistance",
  TLG_Repair_Car_Assistance__c: "RepairCarAssistance"
});

function getSiteNameFromLocation() {
  const pathname = globalThis.location?.pathname || "";
  const [siteBasePath] = pathname.split("/s/");
  const normalizedPath = siteBasePath || pathname;

  return normalizedPath.replace(/^\/+/u, "");
}

function normalizeFormName(value) {
  return (value || "").toString().trim();
}

function getCorrectedAssistanceTypeLabel(value) {
  return normalizeFormName(value).replaceAll("Assitance", "Assistance");
}

export default class YearRoundAssistanceFormHgh extends LightningElement {
  @api assistanceType;
  logoUrl = LOGO;
  povertyGuidelines = [];
  _currentPage = PAGE1;
  showPage1 = true;
  showPage2 = false;
  showPage3 = false;
  isProcessing = false;
  isLoadingPickListOptions = true;
  isLoadingPovertyGuidelines = true;
  isCheckingFormStatus = true;

  children = [];
  adults = [];
  applicantPayload = null;
  adultsPayload = null;
  childrenPayload = null;
  duplicateEntryError = "";

  payloads = {};

  // Form visibility properties
  formStatus = {
    isActive: false,
    message: "",
    formId: ""
  };

  setPage(page = PAGE1) {
    this._currentPage = page;
    this.showPage1 = this._currentPage === PAGE1;
    this.showPage2 = this._currentPage === PAGE2;
    this.showPage3 = this._currentPage === PAGE3;
  }

  get siteName() {
    return getSiteNameFromLocation();
  }

  get formTitle() {
    return this.assistanceConfig.title;
  }

  get showHeader() {
    return !this.showPage3;
  }

  get currentStep() {
    if (this.showPage1) return 1;
    if (this.showPage2) return 2;
    return 3;
  }

  get step1Class() {
    return this.currentStep >= 1 ? "hgh-step hgh-step--active" : "hgh-step";
  }

  get step2Class() {
    return this.currentStep >= 2 ? "hgh-step hgh-step--active" : "hgh-step";
  }

  get step3Class() {
    return this.currentStep >= 3 ? "hgh-step hgh-step--active" : "hgh-step";
  }

  get progressStyle() {
    return `width: ${this.progressPercent}%`;
  }

  get progressPercent() {
    if (this.showPage1) return 16;
    if (this.showPage2) return 50;
    return 100;
  }

  get assistanceConfig() {
    return (
      ASSISTANCE_TYPE_CONFIG[this.assistanceType] ?? {
        title: DEFAULT_FORM_TITLE,
        caseType: null,
        accountSuffix: DEFAULT_FORM_TITLE,
        visibilityFormName: DEFAULT_FORM_TITLE
      }
    );
  }

  get formVisibilityLookupNames() {
    const candidates = [
      this.assistanceConfig.visibilityFormName,
      this.formTitle,
      this.assistanceType,
      getCorrectedAssistanceTypeLabel(this.assistanceType),
      this.siteName
    ]
      .map(normalizeFormName)
      .filter(Boolean);

    return [...new Set(candidates)];
  }

  get isChristmasFlow() {
    const assistanceMarkers = [
      this.assistanceType,
      getCorrectedAssistanceTypeLabel(this.assistanceType),
      this.assistanceConfig.caseType,
      this.assistanceConfig.visibilityFormName,
      this.formTitle,
      this.siteName
    ]
      .map(normalizeFormName)
      .filter(Boolean);

    return assistanceMarkers.some((marker) => /christmas/i.test(marker));
  }

  get isUsedCarFlow() {
    const assistanceMarkers = [
      this.assistanceType,
      getCorrectedAssistanceTypeLabel(this.assistanceType),
      this.assistanceConfig.caseType,
      this.assistanceConfig.visibilityFormName,
      this.formTitle,
      this.siteName
    ]
      .map(normalizeFormName)
      .filter(Boolean);

    return assistanceMarkers.some(
      (marker) => /used car|repair car/i.test(marker)
    );
  }

  getDuplicateRelationshipValue(section) {
    const relationship = this.getDuplicateFieldValue(section, "RelationShip");
    const customRelationship = this.getDuplicateFieldValue(
      section,
      "RelationShipCustom"
    );

    if (this.normalizeDuplicateValue(relationship) === "other") {
      return customRelationship || relationship;
    }

    return relationship;
  }

  get page1ButtonLabel() {
    return this.isUsedCarFlow || this.isChristmasFlow
      ? "Submit Application →"
      : "Proceed to Next Step →";
  }

  shouldCollectAssistanceDetails(eligibility) {
    if (this.isUsedCarFlow || this.isChristmasFlow) {
      return false;
    }

    return eligibility !== false;
  }

  get isTwoStepFlow() {
    return this.isUsedCarFlow || this.isChristmasFlow;
  }  

  connectedCallback() {
    this.loadFormStatus();
  }

  loadFormStatus() {
    this.isCheckingFormStatus = true;

    this.tryLoadFormStatus()
      .then((result) => {
        if (result) {
          this.formStatus = {
            isActive: result.isActive === true,
            message: result.message || "This form is currently unavailable.",
            formId: result.formId || ""
          };
        } else {
          this.formStatus = {
            isActive: false,
            message: "Could not determine form status. Please try again later.",
            formId: ""
          };
        }
      })
      .catch((error) => {
        this.formStatus = {
          isActive: false,
          message:
            error.body?.message ||
            "Error loading form status. Please try again later.",
          formId: ""
        };
      })
      .finally(() => {
        this.isCheckingFormStatus = false;
      });
  }

  async tryLoadFormStatus() {
    const results = await Promise.all(
      this.formVisibilityLookupNames.map((formName) =>
        getFormStatus({ formName })
      )
    );

    return results.find((result) => result?.formId) || results.at(-1) || null;
  }

  @wire(getPicklistValues) /* { 'userId': '$loginId' } */
  getPicklistValuesHandler() {
    this.isLoadingPickListOptions = false;
  }

  @wire(getPovertyGuidelines) /* { 'userId': '$loginId' } */
  getPovertyGuidelinesHandler({ data, error }) {
    if (data) {
      this.povertyGuidelines = data
        .map((povertyGuideline) => ({
          ...povertyGuideline,
          TLG_Year__c: +povertyGuideline.TLG_Year__c || 1901,
          Monthly_Income__x: (povertyGuideline.TLG_Income__c / 12) * 4
        }))
        .sort((povertyGuidelineA, povertyGuidelineB) => {
          if (povertyGuidelineB.TLG_Year__c > povertyGuidelineA.TLG_Year__c)
            return 1;
          if (povertyGuidelineB.TLG_Year__c < povertyGuidelineA.TLG_Year__c)
            return -1;
          if (
            povertyGuidelineB.TLG_Household_Size__c >
            povertyGuidelineA.TLG_Household_Size__c
          )
            return 1;
          if (
            povertyGuidelineB.TLG_Household_Size__c <
            povertyGuidelineA.TLG_Household_Size__c
          )
            return -1;
          return 0;
        });
      this.isLoadingPovertyGuidelines = false;
    } else if (error) {
      this.isLoadingPovertyGuidelines = false;
    }
  }

  get showLoader() {
    return (
      this.isProcessing ||
      this.isLoadingPickListOptions ||
      this.isLoadingPovertyGuidelines ||
      this.isCheckingFormStatus
    );
  }

  get isFormActive() {
    return this.formStatus.isActive === true;
  }

  get applicantEl() {
    return this.template.querySelector(
      'c-year-round-assistance-form-applicant-section-hgh[data-type="applicant"]'
    );
  }

  get childrenEl() {
    return Array.from(
      this.template.querySelectorAll(
        'c-year-round-assistance-form-child-section-hgh[data-type="child"]'
      )
    );
  }

  get adultsEl() {
    return Array.from(
      this.template.querySelectorAll(
        'c-year-round-assistance-form-applicant-section-hgh[data-type="adult"]'
      )
    );
  }

  get householdExpenseEl() {
    return this.template.querySelector(
      "c-year-round-assistance-form-household-expense-section-hgh"
    );
  }

  get householdIncomeEl() {
    return this.template.querySelector(
      "c-year-round-assistance-form-household-income-section-hgh"
    );
  }

  get householdSituationEl() {
    return this.template.querySelector(
      "c-year-round-assistance-form-situation-section-hgh"
    );
  }

  get assistanceEl() {
    return this.template.querySelector(
      "c-year-round-assistance-form-assistance-section-hgh"
    );
  }

  renderedCallback() {
    if (
      this.childrenPayload?.length === this.childrenEl.length &&
      this.adultsPayload?.length === this.adultsEl.length
    )
      return;

    this.updateSummary();
  }

  updateSummary() {
    const applicant = this.applicantEl;
    const childs = this.childrenEl;
    const adults = this.adultsEl;

    this.applicantPayload = applicant?.payload || null;
    this.adultsPayload = adults.map((adult) => adult.payload);
    this.childrenPayload = childs.map((child) => child.payload);
  }

  generateUniqueId(prefix = "uid") {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).substring(2)}`.toUpperCase();
  }

  addChildHandler() {
    const key = this.generateUniqueId("child");
    const title = `Child ${this.children.length + 2}`;

    this.children = [...this.children, { key, title }];
  }

  removeChildHandler(event) {
    if (!event?.target?.dataset?.key) return;

    const children = this.children.filter(
      (child) => child.key !== event?.target?.dataset?.key
    );
    this.children = children.map(({ key }, index) => ({
      key,
      title: `Child ${index + 2}`
    }));
  }

  addAdultHandler() {
    const key = this.generateUniqueId("adult");
    const title = `Adult ${this.adults.length + 1}`;

    this.adults = [...this.adults, { key, title }];
  }

  removeAdultHandler(event) {
    if (!event?.target?.dataset?.key) return;

    const adults = this.adults.filter(
      (adult) => adult.key !== event?.target?.dataset?.key
    );
    this.adults = adults.map(({ key }, index) => ({
      key,
      title: `Adult ${index + 1}`
    }));
  }

  refreshPage() {
    globalThis.location.reload();
  }

  getRawFieldValue(section, fieldName) {
    return section?.fieldsMap?.[fieldName]?.value;
  }

  getTrimmedFieldValue(section, fieldName) {
    const value = this.getRawFieldValue(section, fieldName);

    if (value === null || value === undefined) {
      return null;
    }

    const normalizedValue = String(value).trim();
    return normalizedValue || null;
  }

  getNumberFieldValue(section, fieldName) {
    const value = this.getRawFieldValue(section, fieldName);

    if (value === null || value === undefined || value === "") {
      return null;
    }

    const normalizedValue = Number(value);
    return Number.isFinite(normalizedValue) ? normalizedValue : null;
  }

  getAgeFieldValue(section) {
    const value = this.getRawFieldValue(section, "Age");

    if (value === null || value === undefined || value === "") {
      return null;
    }

    const normalizedValue = Number(value);
    return Number.isFinite(normalizedValue) ? normalizedValue : null;
  }

  normalizeDuplicateValue(value) {
    return (value || "")
      .toString()
      .trim()
      .replace(/\s+/g, " ")
      .toLowerCase();
  }

  getDuplicateFieldValue(section, fieldName) {
    return section?.fieldsMap?.[fieldName]?.value || "";
  }

  getDuplicateEntryKey(section) {
    const firstName = this.normalizeDuplicateValue(
      this.getDuplicateFieldValue(section, "FirstName")
    );

    const lastName = this.normalizeDuplicateValue(
      this.getDuplicateFieldValue(section, "LastName")
    );

    const dob = this.normalizeDuplicateValue(
      this.getDuplicateFieldValue(section, "DateOfBirth")
    );

    const relationship = this.normalizeDuplicateValue(
      this.getDuplicateRelationshipValue(section)
    );

    return `${firstName}|${lastName}|${dob}|${relationship}`;
  }

  findDuplicateIndexes(sections = []) {
    const keyMap = new Map();

    sections.forEach((section, index) => {
        const firstName = this.normalizeDuplicateValue(
            this.getDuplicateFieldValue(section, "FirstName")
        );
        const lastName = this.normalizeDuplicateValue(
            this.getDuplicateFieldValue(section, "LastName")
        );
        const dob = this.normalizeDuplicateValue(
            this.getDuplicateFieldValue(section, "DateOfBirth")
        );
        const relationship = this.normalizeDuplicateValue(
            this.getDuplicateRelationshipValue(section)
        );

        // ✅ Teeno fields mein se koi bhi empty ho toh skip karo
        if (!firstName || !lastName || !dob) {
            return;
        }

        const key = this.getDuplicateEntryKey(section);

        if (!keyMap.has(key)) {
            keyMap.set(key, []);
        }
        keyMap.get(key).push(index);
    });

    const duplicateIndexes = new Set();

    keyMap.forEach((indexes) => {
      if (indexes.length > 1) {
        indexes.forEach((index) => duplicateIndexes.add(index));
      }
    });

    return duplicateIndexes;
  }

  hasDuplicateEntries(sections = []) {
    const seen = new Set();

    for (const section of sections) {
      const firstName = this.normalizeDuplicateValue(
        this.getDuplicateFieldValue(section, "FirstName")
      );

      const lastName = this.normalizeDuplicateValue(
        this.getDuplicateFieldValue(section, "LastName")
      );

      const relationship = this.normalizeDuplicateValue(
        this.getDuplicateFieldValue(section, "RelationShip")
      );

      /**
       * Blank/incomplete rows should not be checked here.
       * Required field validation already handles missing values before this method runs.
       */
      if (!firstName || !lastName || !relationship) {
        continue;
      }

      const key = this.getDuplicateEntryKey(section);

      if (seen.has(key)) {
        return true;
      }

      seen.add(key);
    }

    return false;
  }

  validateDuplicateHouseholdEntries() {
    this.duplicateEntryError = "";

    this.childrenEl.forEach((child) => {
      if (child?.clearDuplicateValidation) {
        child.clearDuplicateValidation();
      }
    });

    this.adultsEl.forEach((adult) => {
      if (adult?.clearDuplicateValidation) {
        adult.clearDuplicateValidation();
      }
    });

    const duplicateChildIndexes = this.findDuplicateIndexes(this.payloads.children);
    const duplicateAdultIndexes = this.findDuplicateIndexes(this.payloads.adults);

    this.childrenEl.forEach((child, index) => {
      if (duplicateChildIndexes.has(index) && child?.setDuplicateValidation) {
        child.setDuplicateValidation("Duplicate child entry detected.");
      }
    });

    this.adultsEl.forEach((adult, index) => {
      if (duplicateAdultIndexes.has(index) && adult?.setDuplicateValidation) {
        adult.setDuplicateValidation("Duplicate adult entry detected.");
      }
    });

    const hasDuplicates =
      duplicateChildIndexes.size > 0 || duplicateAdultIndexes.size > 0;

    if (hasDuplicates) {
      this.duplicateEntryError =
        "Duplicate entries detected. Please review the highlighted Sections before submitting.";

      const firstDuplicateChild = this.childrenEl.find((_, index) =>
        duplicateChildIndexes.has(index)
      );

      const firstDuplicateAdult = this.adultsEl.find((_, index) =>
        duplicateAdultIndexes.has(index)
      );

      const firstDuplicateSection = firstDuplicateChild || firstDuplicateAdult;

      firstDuplicateSection?.scrollIntoView({
        behavior: "smooth",
        block: "center"
      });

      return false;
    }

    return true;
  }

  getPrimaryAdultPayload(adults) {
    return Array.isArray(adults) && adults.length > 0 ? adults[0] : null;
  }

  buildApplicantObject(applicant) {
    return {
      sobjectType: "Contact",
      FirstName: applicant.fieldsMap.FirstName?.value || null,
      LastName: applicant.fieldsMap.LastName?.value || null,
      MailingStreet: applicant.fieldsMap.Street?.value || null,
      MailingCity: applicant.fieldsMap.City?.value || null,
      MailingState: applicant.fieldsMap.State?.value || null,
      MailingPostalCode: applicant.fieldsMap.ZipCode?.value || null,
      Birthdate: applicant.fieldsMap.DateOfBirth?.value || null,
      TLG_Age__c: this.getAgeFieldValue(applicant),
      GenderIdentity: applicant.fieldsMap.Gender?.value || null,
      TLG_Social_Security_Number__c: applicant.fieldsMap.SSN?.value || null,
      Phone: applicant.fieldsMap.Phone?.value || null,
      Email: applicant.fieldsMap.EmailAddress?.value || null,
      TLG_Employed_or_unemployed__c:
        applicant.fieldsMap.EmploymentStatus?.value || null,
      TLG_Employer_Name__c: applicant.fieldsMap.EmployerName?.value || null,  
      Employment_Unemployment_duration_months__c:
        applicant.fieldsMap.MonthsOfEmploymentOrUnemployment?.value || null,
      TLG_Hours_worked_per_week__c:
        applicant.fieldsMap.HoursWorkedPerWeek?.value || null,
      TLG_Rate_of_Pay__c: applicant.fieldsMap.PayPerHour?.value || null,
      TLG_Wages_per_month__c: applicant.fieldsMap.Wages?.value || null,
      TLG_SSI_Disability__c: applicant.fieldsMap.Disability?.value || null,
      TLG_TANIF__c: applicant.fieldsMap.TANIF?.value || null,
      TLG_SS__c: applicant.fieldsMap.SS?.value || null,
      TLG_Food_Stamps__c: applicant.fieldsMap.FoodStamps?.value || null,
      TLG_Unemployment__c: applicant.fieldsMap.Unemployment?.value || null,
      TLG_Child_Support__c: applicant.fieldsMap.ChildSupport?.value || null,
      TLG_Other__c: applicant.fieldsMap.Other?.value || null,
      TLG_Veterans__c: applicant.fieldsMap.Veterans?.value || null,
      Number_of_Jobs_in_Past_36_Months__c: applicant.fieldsMap.JobsPast36Months?.value || null,
      TLG_Previous_Employer__c: applicant.fieldsMap.PreviousEmployer?.value || null,
      TLG_Total_Time_Employed_Months__c: applicant.fieldsMap.TotalTimeEmployed?.value || null,
      how_long_were_you_employed_there__c: applicant.fieldsMap.HowLongEmployedThere?.value || null,
      Pay_Per_Hour__c: applicant.fieldsMap.PayPerHour?.value || null
    };
  }

  getSchoolAttendingValue(child) {
    const schoolAttendingValue = child.fieldsMap.SchoolAttending?.value;

    if (
      !schoolAttendingValue ||
      /^(undefined|null|no)$/i.test(schoolAttendingValue)
    ) {
      return "N/A";
    }

    return child.fieldsMap.SchoolAttending.additionalInfo;
  }

  buildChildObjectList(children) {
    return children.map((child) => ({
      child: {
        sobjectType: "Contact",
        FirstName: child.fieldsMap.FirstName?.value || null,
        LastName: child.fieldsMap.LastName?.value || null,
        Birthdate: child.fieldsMap.DateOfBirth?.value || null,
        GenderIdentity: child.fieldsMap.Gender?.value || null,
        TLG_Age__c: this.getAgeFieldValue(child),
        TLG_Are_you_their_legal_guardian__c:
          child.fieldsMap.LegalGuardian?.value || null,
        School_Attending__c: this.getSchoolAttendingValue(child)
      },
      relationshipWithApplicant: child.fieldsMap.RelationShip?.value || null
    }));
  }

  buildAdultObjectList(adults) {
    return adults.map((adult) => ({
      adult: {
        sobjectType: "Contact",
        FirstName: adult.fieldsMap.FirstName?.value || null,
        LastName: adult.fieldsMap.LastName?.value || null,
        Birthdate: adult.fieldsMap.DateOfBirth?.value || null,
        TLG_Age__c: this.getAgeFieldValue(adult),
        GenderIdentity: adult.fieldsMap.Gender?.value || null,
        TLG_Social_Security_Number__c: adult.fieldsMap.SSN?.value || null,
        Phone: adult.fieldsMap.Phone?.value || null,
        TLG_Employed_or_unemployed__c:
          adult.fieldsMap.EmploymentStatus?.value || null,
        TLG_Employer_Name__c: adult.fieldsMap.EmployerName?.value || null,
        Employment_Unemployment_duration_months__c:
          adult.fieldsMap.MonthsOfEmploymentOrUnemployment?.value || null,
        TLG_Hours_worked_per_week__c:
          adult.fieldsMap.HoursWorkedPerWeek?.value || null,
        TLG_Rate_of_Pay__c: adult.fieldsMap.PayPerHour?.value || null,
        TLG_Wages_per_month__c: adult.fieldsMap.Wages?.value || null,
        TLG_SSI_Disability__c: adult.fieldsMap.Disability?.value || null,
        TLG_TANIF__c: adult.fieldsMap.TANIF?.value || null,
        TLG_SS__c: adult.fieldsMap.SS?.value || null,
        TLG_Food_Stamps__c: adult.fieldsMap.FoodStamps?.value || null,
        TLG_Unemployment__c: adult.fieldsMap.Unemployment?.value || null,
        TLG_Child_Support__c: adult.fieldsMap.ChildSupport?.value || null,
        TLG_Other__c: adult.fieldsMap.Other?.value || null,
        TLG_Veterans__c: adult.fieldsMap.Veterans?.value || null,
        Number_of_Jobs_in_Past_36_Months__c: adult.fieldsMap.JobsPast36Months?.value || null,
        TLG_Previous_Employer__c: adult.fieldsMap.PreviousEmployer?.value || null,
        TLG_Total_Time_Employed_Months__c: adult.fieldsMap.TotalTimeEmployed?.value || null,
        how_long_were_you_employed_there__c: adult.fieldsMap.HowLongEmployedThere?.value || null,
        Pay_Per_Hour__c: adult.fieldsMap.PayPerHour?.value || null
      },
      relationshipWithApplicant: adult.fieldsMap.RelationShip?.value || null,
      customRelationshipWithApplicant:
        adult.fieldsMap.RelationShipCustom?.value || null
    }));
  }

  buildAccountName(applicantObject, childObjectList, adultObjectList) {
    const householdMembers = [
      applicantObject,
      ...childObjectList.map(({ child }) => child),
      ...adultObjectList.map(({ adult }) => adult)
    ];
    const householdNames = householdMembers
      .map((member) => member.LastName?.trim())
      .filter(Boolean);

    const accountName = householdNames.reduce((result, lastName, index) => {
      if (index === 0) {
        return lastName;
      }

      const separator = index === householdNames.length - 1 ? " and " : ", ";
      return `${result}${separator}${lastName}`;
    }, "");

    return accountName
      ? `${accountName} ${this.assistanceConfig.accountSuffix}`
      : this.assistanceConfig.accountSuffix;
  }

  buildHouseholdExpenseObject(applicant, accountName, householdExpense, householdIncome) {
    const hasPreviousAddress =
      applicant.fieldsMap.PreviousStreet?.value ||
      applicant.fieldsMap.PreviousCity?.value ||
      applicant.fieldsMap.PreviousState?.value ||
      applicant.fieldsMap.PreviousZipCode?.value;

    return {
      sobjectType: "Account",
      Name: accountName,
      Application_Status__c: "New",
      BillingStreet: applicant.fieldsMap.Street?.value || null,
      BillingCity: applicant.fieldsMap.City?.value || null,
      BillingState: applicant.fieldsMap.State?.value || null,
      BillingPostalCode: applicant.fieldsMap.ZipCode?.value || null,
      BillingCountry: "US",

      ShippingStreet: applicant.fieldsMap.PreviousStreet?.value || null,
      ShippingCity: applicant.fieldsMap.PreviousCity?.value || null,
      ShippingState: applicant.fieldsMap.PreviousState?.value || null,
      ShippingPostalCode: applicant.fieldsMap.PreviousZipCode?.value || null,
      ShippingCountry: hasPreviousAddress ? "US" : null,
      
      How_long_have_you_lived_at_this_address__c:
        applicant?.fieldsMap?.monthsAtCurrentAddress?.value || null,
      How_long_did_you_live_there__c:
        applicant?.fieldsMap?.PreviousAddressDuration?.value || null,
      Interested_in_Santa_Gifts__c:
      applicant?.fieldsMap?.ChristmasConsent?.value || false,

      TLG_Total_Household_Expense__c: householdExpense.fieldsMap.TotalHouseholdExpense?.value || null,

      TLG_Total_Disability__c: householdIncome.fieldsMap.TotalDisability?.value || null,
      TLG_Total_Social_Security__c: householdIncome.fieldsMap.TotalSS?.value || null,
      TLG_Total_Unemployment__c: householdIncome.fieldsMap.TotalUnemployment?.value || null,
      TLG_Household_Income__c: householdIncome.fieldsMap.TotalIncome?.value || null,
      TLG_Total_TANIF__c: householdIncome.fieldsMap.TotalTanif?.value || null,
      TLG_Total_Wages__c: householdIncome.fieldsMap.TotalWages?.value || null,
      TLG_Total_Food_Stamps__c: householdIncome.fieldsMap.TotalFoodStamps?.value || null,
      TLG_Total_Veterans__c: householdIncome.fieldsMap.TotalVeterans?.value || null,
      TLG_Total_Child_Support__c: householdIncome.fieldsMap.TotalChildSupport?.value || null,
      TLG_Total_Other__c: householdIncome.fieldsMap.TotalOther?.value || null

    };
  }

  buildBaseCaseObject({
    accountName,
    householdExpense,
    householdIncome,
    applicant,
    adults,
    children,
    eligibility
  }) {
    const primaryAdult = this.getPrimaryAdultPayload(adults);
    const hasPreviousAddress = applicant.fieldsMap.PreviousStreet?.value ||
      applicant.fieldsMap.PreviousCity?.value ||
      applicant.fieldsMap.PreviousState?.value ||
      applicant.fieldsMap.PreviousZipCode?.value;

    return {
      sobjectType: "Case",
      RecordType: { DeveloperName: "Assistance_Application" },
      Subject: accountName,
      Status: "New",
      Assistance_Type__c: this.assistanceConfig.caseType,
      Application_Year__c: String(new Date().getFullYear()),
      How_long_have_you_lived_at_this_address__c:
        applicant?.fieldsMap?.monthsAtCurrentAddress?.value || null,
      How_long_did_you_live_there__c:
        applicant?.fieldsMap?.PreviousAddressDuration?.value || null,
      Applicant_Employment_Status__c:
        applicant.fieldsMap.EmploymentStatus?.value || null,
      Employment_Length_Months__c:
        applicant.fieldsMap.MonthsOfEmploymentOrUnemployment?.value || null,
      Total_Time_Employed_Months__c:
        applicant.fieldsMap.TotalTimeEmployed?.value || null,
      Jobs_In_Past_36_Months__c:
        applicant.fieldsMap.JobsPast36Months?.value || null,
      Applicant_Employer_Name__c:
        this.getTrimmedFieldValue(applicant, "EmployerName"),
      Applicant_Previous_Employer__c:
        this.getTrimmedFieldValue(applicant, "PreviousEmployer"),
      Applicant_Employment_Duration__c:
        this.getTrimmedFieldValue(applicant, "HowLongEmployedThere"),
      Adult_Employer_Name__c:
        this.getTrimmedFieldValue(primaryAdult, "EmployerName"),
      Adult_Previous_Employer__c:
        this.getTrimmedFieldValue(primaryAdult, "PreviousEmployer"),
      Adult_Jobs_In_Past_36_Months__c:
        this.getNumberFieldValue(primaryAdult, "JobsPast36Months"),
      Adult_Total_Time_Employed_Months__c:
        this.getNumberFieldValue(primaryAdult, "TotalTimeEmployed"),
      Adult_Employment_Duration__c:
        this.getTrimmedFieldValue(primaryAdult, "HowLongEmployedThere"),
      TLG_Rent__c: householdExpense.fieldsMap.Rent?.value || null,
      TLG_Utilities__c: householdExpense.fieldsMap.Utilities?.value || null,
      TLG_InternetCable__c: householdExpense.fieldsMap.Internet?.value || null,
      TLG_Groceries__c: householdExpense.fieldsMap.Groceries?.value || null,
      TLG_Household_Needs__c:
        householdExpense.fieldsMap.HouseholdNeeds?.value || null,
      TLG_Car_Payment__c:
        householdExpense.fieldsMap.CarPayment?.value || null,
      TLG_Credit_Cards__c:
        householdExpense.fieldsMap.CreditCards?.value || null,
      TLG_Other_Expense__c: householdExpense.fieldsMap.Other?.value || null,
      Total_Household_Expense__c:
        householdExpense.fieldsMap.TotalHouseholdExpense?.value || null,
      TLG_Number_of_Individuals_in_household__c:
        householdIncome.fieldsMap.TotalHouseholds?.value || null,
      TLG_Number_of_Adults__c: (adults?.length || 0) + 1,
      TLG_Number_of_Children__c: children?.length || 0,
      TLG_Wages__c: householdIncome.fieldsMap.TotalWages?.value || null,
      TLG_SSIDisability__c:
        householdIncome.fieldsMap.TotalDisability?.value || null,
      TLG_TANIF__c: householdIncome.fieldsMap.TotalTanif?.value || null,
      TLG_SS__c: householdIncome.fieldsMap.TotalSS?.value || null,
      TLG_Food_Stamps__c:
        householdIncome.fieldsMap.TotalFoodStamps?.value || null,
      TLG_Unemployment__c:
        householdIncome.fieldsMap.TotalUnemployment?.value || null,
      TLG_Child_Support__c:
        householdIncome.fieldsMap.TotalChildSupport?.value || null,
      TLG_Other_Income__c: householdIncome.fieldsMap.TotalOther?.value || null,
      TLG_Veterans__c: householdIncome.fieldsMap.TotalVeterans?.value || null,
      TLG_Total_Household_Income__c:
        householdIncome.fieldsMap.TotalIncome?.value || null,
      TLG_Christmas_Assistance__c:
        this.assistanceType === "Christmas Assitance" && eligibility === true,
      Interested_in_Santa_Gifts__c:
        applicant?.fieldsMap?.ChristmasConsent?.value || false,
       Origin: "Web",

      // Address (Cuurent And Previous)
      Current_Address__Street__s: applicant.fieldsMap.Street?.value || null,
      Current_Address__City__s: applicant.fieldsMap.City?.value || null,
      Current_Address__StateCode__s: applicant.fieldsMap.State?.value || null,
      Current_Address__PostalCode__s: applicant.fieldsMap.ZipCode?.value || null,
      Current_Address__CountryCode__s: "US",


      Previous_Address__Street__s:
        applicant.fieldsMap.PreviousStreet?.value || null,
      Previous_Address__City__s: applicant.fieldsMap.PreviousCity?.value || null,
      Previous_Address__StateCode__s:
        applicant.fieldsMap.PreviousState?.value || null,
      Previous_Address__PostalCode__s:
        applicant.fieldsMap.PreviousZipCode?.value || null,
      Previous_Address__CountryCode__s: hasPreviousAddress ? "US" : null

    };
  }

    applyAssistanceToCase(caseObject, assistance) {
        caseObject.TLG_Do_you_have_a_shutoff_notice__c =
            assistance.fieldsMap.ShutoffNotice?.value || null;
        caseObject.TLG_Have_you_reached_out_to_OACAC__c =
            assistance.fieldsMap.ReachedOutOACAC?.value || null;
        caseObject.TLG_Has_OACAC_made_a_determination__c =
            assistance.fieldsMap.DeterminationMadeByOACAC?.value || null;
        caseObject.TLG_Type_of_Assistance_Other__c =
            assistance.fieldsMap.Description?.value || null;

        Object.entries(ASSISTANCE_BLOCK_FIELD_MAP).forEach(
            ([fieldName, blockName]) => {
            caseObject[fieldName] = Boolean(assistance.blocksMap?.[blockName]);
            }
        );
    }

    buildCurrentLandlordObject(assistance) {
        const isRentAssistance = Boolean(assistance.blocksMap?.RentAssistance);

        if (!isRentAssistance) {
            return null;
        }

        return {
            sobjectType: "TLG_LandLord__c",
            Name: `${assistance.fieldsMap.FirstName?.value || ""} ${assistance.fieldsMap.LastName?.value || ""}`.trim(),
            TLG_Street__c: assistance.fieldsMap.Street?.value || null,
            TLG_City__c: assistance.fieldsMap.City?.value || null,
            TLG_State__c: assistance.fieldsMap.State?.value || null,
            TLG_Zip__c: assistance.fieldsMap.ZipCode?.value || null,
            LandLord_Phone__c: assistance.fieldsMap.Phone?.value || null,
            TLG_Old_Address__c: false
        };
    }

  applyHouseholdSituationToCase(caseObject, householdSituation) {
    caseObject.Reason_for_Current_Situation__c =
      (
        householdSituation?.fieldsMap?.Reason_for_Current_Situation__c?.value ||
        ""
      ).trim() || null;
    // caseObject.Residency_Length_Months__c =
    //   householdSituation?.fieldsMap?.ResidencyLengthMonths?.value || null;
    caseObject.Assisted_in_Past_12_Months__c =
      householdSituation?.fieldsMap?.Assisted_in_Past_12_Months__c?.value ||
      false;
  }

  getEligibilityForAssistance(totalIncome) {
    const householdSize = 1 + this.childrenEl.length + this.adultsEl.length;
    const currentYear = new Date().getFullYear();

    if (!this.povertyGuidelines || this.povertyGuidelines.length === 0)
      return null;

    let povertyGuideline = this.povertyGuidelines.find(
      ({ TLG_Household_Size__c, TLG_Year__c }) =>
        householdSize >= TLG_Household_Size__c && currentYear === TLG_Year__c
    );

    if (!povertyGuideline) {
      povertyGuideline = this.povertyGuidelines.find(
        ({ TLG_Household_Size__c, TLG_Year__c }) =>
          householdSize >= TLG_Household_Size__c &&
          currentYear - 1 === TLG_Year__c
      );
    }

    if (!povertyGuideline) povertyGuideline = this.povertyGuidelines[0];

    return totalIncome <= povertyGuideline.Monthly_Income__x;
  }

  // async proceedFromPage1() {
  //   if (!this.applicantEl || this.isProcessing) return;

  //   this.isProcessing = true;
  //   this.duplicateEntryError = "";
  //   try {
  //     const sections = [
  //       this.applicantEl,
  //       ...this.childrenEl,
  //       ...this.adultsEl,
  //       this.householdExpenseEl
  //     ];
  //     if (this.householdSituationEl) sections.push(this.householdSituationEl);

  //     const errorFields = sections.reduce(
  //       (result, section) => [...result, ...section.validate()],
  //       []
  //     );
  //     if (errorFields.length > 0) {
  //       errorFields[0].scrollIntoView();
  //       return;
  //     }

  //     this.payloads = {
  //       applicant: this.applicantEl.payload,
  //       children: this.childrenEl.map((child) => child.payload),
  //       adults: this.adultsEl.map((adult) => adult.payload),
  //       householdExpense: this.householdExpenseEl.payload,
  //       householdIncome: this.householdIncomeEl.payload,
  //       householdSituation: this.householdSituationEl.payload
  //     };

  //     if (!this.validateDuplicateHouseholdEntries()) {
  //       return;
  //     }

  //     const eligibility = this.getEligibilityForAssistance(
  //       this.payloads.householdIncome.fieldsMap.TotalIncome.value
  //     );

  //     const shouldShowAssistancePage =
  //       this.shouldCollectAssistanceDetails(eligibility);

  //     if (shouldShowAssistancePage) {
  //       this.setPage(PAGE2);
  //       return;
  //     }

  //     await this.submit();
  //   } catch (ex) {
  //     console.error("Failed to proceed from page 1", ex);
  //   } finally {
  //     this.isProcessing = false;
  //   }
  // }

  async proceedFromPage1() {
    if (!this.applicantEl || this.isProcessing) return;

    this.isProcessing = true;
    this.duplicateEntryError = "";
    try {
      const sections = [
        this.applicantEl,
        ...this.childrenEl,
        ...this.adultsEl,
        this.householdExpenseEl
      ];
      if (this.householdSituationEl) sections.push(this.householdSituationEl);

      const errorFields = sections.reduce(
        (result, section) => [...result, ...section.validate()],
        []
      );
      if (errorFields.length > 0) {
        errorFields[0].scrollIntoView();
        return;
      }

      // ✅ PEHLE payloads set karo
      this.payloads = {
        applicant: this.applicantEl.payload,
        children: this.childrenEl.map((child) => child.payload),
        adults: this.adultsEl.map((adult) => adult.payload),
        householdExpense: this.householdExpenseEl.payload,
        householdIncome: this.householdIncomeEl.payload,
        householdSituation: this.householdSituationEl?.payload
      };

      // ✅ PHIR duplicate check karo (ab this.payloads.children populated hai)
      if (!this.validateDuplicateHouseholdEntries()) {
        return;
      }

      const eligibility = this.getEligibilityForAssistance(
        this.payloads.householdIncome.fieldsMap.TotalIncome.value
      );

      const shouldShowAssistancePage =
        this.shouldCollectAssistanceDetails(eligibility);

      if (shouldShowAssistancePage) {
        this.setPage(PAGE2);
        return;
      }

      await this.submit();
    } catch (ex) {
      console.error("Failed to proceed from page 1", ex);
    } finally {
      this.isProcessing = false;
    }
  }

  async proceedFromPage2() {
    if (!this.assistanceEl || this.isProcessing) return;

    this.isProcessing = true;

    try {
      const errorFields = this.assistanceEl.validate();

      if (errorFields.length > 0) {
        errorFields[0].scrollIntoView();
        return;
      }

      this.payloads = {
        ...this.payloads,
        assistance: this.assistanceEl.payload
      };

      if (this.payloads.assistance.blocks.length === 0) {
        return;
      }

      await this.submit();
    } catch (ex) {
      console.error("Failed to proceed from page 2", ex);
    } finally {
      this.isProcessing = false;
    }
  }

  async submit() {
    const {
      applicant,
      children,
      adults,
      householdExpense,
      householdIncome,
      assistance,
      householdSituation
    } = this.payloads;
    const eligibility = this.getEligibilityForAssistance(
      householdIncome.fieldsMap.TotalIncome.value
    );

    if (this.shouldCollectAssistanceDetails(eligibility) && !assistance) {
      this.setPage(PAGE2);
      return;
    }

    const applicantObject = this.buildApplicantObject(applicant);
    const childObjectList = this.buildChildObjectList(children);
    const adultObjectList = this.buildAdultObjectList(adults);
    const accountName = this.buildAccountName(
      applicantObject,
      childObjectList,
      adultObjectList
    );
    const householdExpenseObject = this.buildHouseholdExpenseObject(
      applicant,
      accountName,
      householdExpense,
      householdIncome
    );
    const caseObject = this.buildBaseCaseObject({
      accountName,
      householdExpense,
      householdIncome,
      applicant,
      adults,
      children,
      eligibility
    });
    
    if (assistance) {
    this.applyAssistanceToCase(caseObject, assistance);
    }

    const landlordObject = assistance
    ? this.buildCurrentLandlordObject(assistance)
    : null;


    if (householdSituation) {
      this.applyHouseholdSituationToCase(caseObject, householdSituation);
    }

    const account = {
      ...householdExpenseObject,
      Gender__c: applicant.fieldsMap.Gender?.value || null
    };

    const payload = {
      account: account,
      assistanceCase: caseObject,
      applicant: applicantObject,
      children: childObjectList,
      adults: adultObjectList,
      landlord: landlordObject,
    };

    const result = await save({ payloadJson: JSON.stringify(payload) });

    if (result === "OK") {
      this.setPage(PAGE3);
    }
  }
}