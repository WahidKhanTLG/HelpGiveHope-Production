import { LightningElement, api, wire } from "lwc";
import lookupApplicant from "@salesforce/apex/HghHouseholdReuseController.lookupApplicant";
import { validateLookupSsn, normalizeSsn, renumberMembers, memberSsnKey } from "c/hghHouseholdReuseUtils";

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

  entryGateComplete = false;
  lookupSsn = "";
  lookupSsnVisible = false;
  lookupSsnValidationError = "";
  lookupError = "";
  submissionError = "";
  isLookingUp = false;
  reuseAccountId = null;
  reuseRecordVersions = null;
  applicantInitialData = null;
  initialGenderOptions = [];
  initialApplicant = {
    firstName: "",
    lastName: "",
    birthDate: "",
    gender: "",
    phone: "",
    email: ""
  };
  entryErrors = {
    firstName: "",
    lastName: "",
    birthDate: "",
    gender: "",
    phone: "",
    email: ""
  };
  _focusGate = true;
  _focusForm = false;
  children = [];
  adults = [];
  applicantPayload = null;
  adultsPayload = null;
  childrenPayload = null;

  payloads = {};

  // Form visibility properties
  formStatus = {
    isActive: false,
    message: "",
    formId: ""
  };
  get showEntryGate() {
    return this.isFormActive && !this.entryGateComplete;
  }
  get showHouseholdMembersFoundBanner() {
       return Boolean(this.reuseAccountId);
  }
  get showApplicationPage1() {
    return this.entryGateComplete && this.showPage1;
  }

  get searchDisabled() {
    return this.isLookingUp;
  }

  get lookupSsnInputType() {
    return this.lookupSsnVisible ? "text" : "password";
  }

  get lookupSsnEyeIcon() {
    return this.lookupSsnVisible ? "utility:hide" : "utility:preview";
  }

  get lookupSsnToggleLabel() {
    return this.lookupSsnVisible ? "Hide SSN" : "Show SSN";
  }

  get lookupSsnAriaInvalid() {
    return this.lookupSsnValidationError ? "true" : "false";
  }

  get entryMaximumBirthDate() {
    const today = new Date();
    const max = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate());
    const year = max.getFullYear();
    const month = String(max.getMonth() + 1).padStart(2, "0");
    const day = String(max.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  // Used only by the lookup popup. Stored household SSNs remain masked/read-only.
  resetLookupSsnEntry() {
    this.lookupSsn = "";
    this.lookupSsnVisible = false;
    this.lookupSsnValidationError = "";
    this.lookupError = "";
    const field = this.template.querySelector('[data-lookup-ssn]');
    if (field) {
      field.value = "";
      field.setCustomValidity("");
    }
  }
  lookupDigits(value) {
    return String(value ?? "").replace(/[^0-9]/g, "");
  }
  formatLookupSsn(value) {
    const digits = this.lookupDigits(value);
    if (digits.length <= 3) return digits;
    if (digits.length <= 5) return `${digits.slice(0, 3)}-${digits.slice(3)}`;
    return `${digits.slice(0, 3)}-${digits.slice(3, 5)}-${digits.slice(5)}`;
  }
  lookupCaretPosition(formatted, digitsToLeft) {
    if (digitsToLeft <= 0) return 0;
    let seen = 0;
    for (let index = 0; index < formatted.length; index += 1) {
      if (/[0-9]/.test(formatted[index])) seen += 1;
      if (seen === digitsToLeft) return index + 1;
    }
    return formatted.length;
  }
  setLookupSelection(field, start, end = start) {
    // Both text/password support selection in common browsers; typing still works
    // when a particular mobile browser does not expose the caret API.
    try {
      field?.setSelectionRange(start, end);
    } catch {
      // Do not log sensitive field values.
    }
  }
  setLookupSsnError(message) {
    this.lookupSsnValidationError = message || "";
    this.template.querySelector('[data-lookup-ssn]')?.setCustomValidity(this.lookupSsnValidationError);
  }
  blurLookupSsn() {
    if (this.isLookingUp) return;
    this.setLookupSsnError(this.lookupSsnValidationError || validateLookupSsn(this.lookupSsn));
  }
  handleLookupSsnTogglePointerDown(event) {
    // Pointer users can reveal the value without losing their typing position.
    // Keyboard users keep normal Tab/Space/Enter behavior on the button.
    const field = this.template.querySelector('[data-lookup-ssn]');
    if (!this.isLookingUp && field && this.template.activeElement === field) event.preventDefault();
  }
  toggleLookupSsnVisibility() {
    if (this.isLookingUp) return;
    const field = this.template.querySelector('[data-lookup-ssn]');
    const start = field?.selectionStart;
    const end = field?.selectionEnd;
    this.lookupSsnVisible = !this.lookupSsnVisible;
    if (field) {
      // Keep the same native input and preserve the cursor when its type changes.
      field.type = this.lookupSsnInputType;
      if (typeof start === "number") {
        this.setLookupSelection(field, start, end ?? start);
        // Chromium can reset the caret during the next password/text repaint.
        // Restore after that repaint, but never overwrite a newer edit/search.
        const expectedType = this.lookupSsnInputType;
        const expectedValue = this.lookupSsn;
        if (typeof globalThis.requestAnimationFrame === "function") {
          globalThis.requestAnimationFrame(() => {
            const current = this.template.querySelector('[data-lookup-ssn]');
            if (!this.isLookingUp && current === field && current.type === expectedType &&
                this.lookupSsn === expectedValue) {
              this.setLookupSelection(current, start, end ?? start);
            }
          });
        }
      }
    }
  }
  handleLookupSsnKeydown(event) {
    if (event.key !== "Enter" || event.isComposing) return;
    event.preventDefault();
    event.stopPropagation();
    if (!this.isLookingUp) this.continueFromEntry();
  }
  handleEntryFieldChange(event) {
    const fieldName = event.target?.dataset?.entryField;
    if (!fieldName) return;

    this.initialApplicant = {
      ...this.initialApplicant,
      [fieldName]: event.target.value || ""
    };

    this.entryErrors = {
      ...this.entryErrors,
      [fieldName]: ""
    };
    this.lookupError = "";
  }

  phoneDigits(value) {
    return String(value ?? "").replace(/[^0-9]/g, "").slice(0, 10);
  }

  formatPhone(value) {
    const digits = this.phoneDigits(value);
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  }

  handleEntryPhoneInput(event) {
    const formatted = this.formatPhone(event.target.value);
    event.target.value = formatted;
    this.initialApplicant = {
      ...this.initialApplicant,
      phone: formatted
    };
    this.entryErrors = {
      ...this.entryErrors,
      phone: ""
    };
    this.lookupError = "";
  }

  validateEntryFields() {
    const ssnError = validateLookupSsn(this.lookupSsn);
    this.setLookupSsnError(ssnError);
    return !ssnError;
  }

  buildNewApplicantInitialData() {
    return {
      recordId: null,
      hasSsn: false,
      ssn: this.lookupSsn,
      ssnReadOnly: true
    };
  }

  buildExistingApplicantInitialData(savedApplicant) {
    return { ...savedApplicant };
  }

  openNewApplicantForm() {
    this.reuseAccountId = null;
    this.reuseRecordVersions = null;
    this.applicantInitialData = this.buildNewApplicantInitialData();
    this.adults = [];
    this.children = [
      {
        key: this.generateUniqueId("child"),
        title: "Child 1",
        initialData: null,
        isExisting: false,
        isActive: true,
        isInactive: false,
        statusReason: "",
        statusReasonError: ""
      }
    ];
    this.entryGateComplete = true;
    this._focusForm = true;
    this.setPage(PAGE1);
  }

  changeLookupSsn(event) {
    const field = event.target;
    const previous = this.lookupSsn;
    if (this.isLookingUp) {
      field.value = previous;
      return;
    }

    const raw = String(field.value ?? "");
    const caret = field.selectionStart ?? raw.length;
    let digits = this.lookupDigits(raw);
    let digitsToLeft = this.lookupDigits(raw.slice(0, caret)).length;
    this.lookupError = "";

    // A tenth digit typed into a complete SSN is ignored, not an error.
    // Do not apply this to paste/autofill: a longer pasted value must not be
    // silently shortened and used to search for a different person's record.
    if (
      event.inputType === "insertText" &&
      /^[0-9]$/.test(event.data || "") &&
      this.lookupDigits(previous).length === 9 &&
      digits.length === 10
    ) {
      field.value = previous;
      this.setLookupSelection(field, Math.min(Math.max(caret - 1, 0), previous.length));
      this.setLookupSsnError("");
      return;
    }

    if (!/^[0-9\s-]*$/.test(raw) || digits.length > 9) {
      field.value = previous;
      this.setLookupSelection(field, Math.min(caret, previous.length));
      this.setLookupSsnError(
        digits.length > 9
          ? "Please enter or paste an SSN with exactly 9 digits."
          : "Please use numbers only."
      );
      return;
    }

    // Backspace/Delete beside a formatting dash also removes the adjacent digit.
    const deletesBackward = event.inputType === "deleteContentBackward";
    const deletesForward = event.inputType === "deleteContentForward";
    if (
      (deletesBackward || deletesForward) &&
      raw.length < previous.length &&
      digits === this.lookupDigits(previous)
    ) {
      const removeAt = deletesBackward ? digitsToLeft - 1 : digitsToLeft;
      if (removeAt >= 0 && removeAt < digits.length) {
        digits = digits.slice(0, removeAt) + digits.slice(removeAt + 1);
        if (deletesBackward) digitsToLeft -= 1;
      }
    }

    const formatted = this.formatLookupSsn(digits);
    this.lookupSsn = formatted;
    field.value = formatted;
    this.setLookupSsnError("");
    this.setLookupSelection(field, this.lookupCaretPosition(formatted, digitsToLeft));
  }
  lookupMessageForStatus(status) {
    switch (status) {
      case "REVIEW_REQUIRED":
        return "We found more than one matching record. Please contact Help Give Hope so the correct household can be confirmed.";
      case "BLOCKED":
        return "We couldn't load the saved household information. Please contact Help Give Hope for assistance.";
      default:
        return "We couldn't complete the lookup. Please try again.";
    }
  }

  async continueFromEntry() {
    if (this.isLookingUp || !this.validateEntryFields()) return;

    this.isLookingUp = true;
    this.lookupSsnVisible = false;
    this.lookupError = "";

    try {
      const result = await lookupApplicant({
        ssn: normalizeSsn(this.lookupSsn),
        assistanceType: this.assistanceConfig.caseType
      });

      // No SSN match: continue as a new application and prefill the popup SSN.
      // SSN reuse is independent of Case Record Type.
      if (result?.status === "NOT_FOUND" || result?.status === "NO_PROGRAM_MATCH") {
        this.openNewApplicantForm();
        return;
      }

      if (result?.status !== "FOUND") {
        this.lookupError = this.lookupMessageForStatus(result?.status);
        return;
      }

      if (!result.accountId || !result.applicant?.recordId || !result.recordVersions) {
        this.lookupError = "We couldn't load all saved household details. Please try again.";
        return;
      }

      this.reuseAccountId = result.accountId;
      this.reuseRecordVersions = result.recordVersions;
      this.applicantInitialData = this.buildExistingApplicantInitialData(result.applicant);

      this.children = renumberMembers(
        (result.children || [])
          .filter((member) => (member?.memberStatus || "Active") !== "Inactive")
          .map((member) => ({
            key: `child-${member.recordId}`,
            initialData: member,
            isExisting: true,
            isActive: true,
            isInactive: false,
            statusReason: "",
            statusReasonError: ""
          })),
        "Child"
      );

      this.adults = renumberMembers(
        (result.adults || [])
          .filter((member) => (member?.memberStatus || "Active") !== "Inactive")
          .map((member) => ({
            key: `adult-${member.recordId}`,
            initialData: member,
            isExisting: true,
            isActive: true,
            isInactive: false,
            statusReason: "",
            statusReasonError: ""
          })),
        "Adult"
      );

      this.entryGateComplete = true;
      this._focusForm = true;
      this.setPage(PAGE1);
    } catch (error) {
      this.lookupError = this.lookupMessageForStatus("ERROR");
    } finally {
      this.isLookingUp = false;
    }
  }

  handleGateKeydown(event) {
    if (event.key !== "Tab") return;
    const dialog = this.template.querySelector("[data-entry-dialog]");
    const focusable = Array.from(
      dialog?.querySelectorAll("button:not([disabled]), input:not([disabled]), select:not([disabled])") || []
    );
    if (!focusable.length) {
      event.preventDefault();
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = this.template.activeElement;
    if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  }
  validateUniqueMembers() {
    const sections = [this.applicantEl, ...this.activeChildrenEl, ...this.activeAdultsEl].filter(Boolean);
    const seen = new Map();
    let duplicate = false;
    for (const section of sections) {
      section.clearDuplicateValidation?.();
      const key = memberSsnKey(section.payload);
      if (!key) continue;
      if (seen.has(key)) {
        duplicate = true;
        section.setDuplicateValidation?.("This SSN is already used by another household member.");
        seen.get(key).setDuplicateValidation?.("This SSN is already used by another household member.");
      } else seen.set(key, section);
    }
    if (duplicate) this.submissionError = "Each applicant, adult, and child must have a unique SSN.";
    return !duplicate;
  }
  existingIdentityFields(section) {
    return section?.recordId ? { Id: section.recordId } : {};
  }
  submittedSsnFields(section) {
    if (section?.storedSsn) return {};
    const value = section?.fieldsMap?.SSN?.value;
    // Number field: normalize while still a string, then send a JSON number.
    // Loaded values stay omitted; their masked display is never sent as an SSN.
    const normalized = value ? normalizeSsn(value) : "";
    return { TLG_Social_Security_Number__c: normalized ? Number(normalized) : null };
  }
  memberAddressFields(section) {
    return {
      Email: section.fieldsMap.EmailAddress?.value || null,
      MailingStreet: section.fieldsMap.Street?.value || null,
      MailingCity: section.fieldsMap.City?.value || null,
      MailingState: section.fieldsMap.State?.value || null,
      MailingPostalCode: section.fieldsMap.ZipCode?.value || null
    };
  }

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
    return this.entryGateComplete && !this.showPage3;
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

  @wire(getPicklistValues)
  getPicklistValuesHandler({ data, error }) {
    if (data) {
      this.initialGenderOptions = (data.GenderIdentity || []).map(({ value, label }) => ({
        value,
        label
      }));
    } else if (error) {
      this.initialGenderOptions = [];
    }
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
    return this.entryGateComplete && (
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

  get inactiveChildKeys() {
    return new Set(this.children.filter((child) => child.isInactive).map((child) => child.key));
  }

  get inactiveAdultKeys() {
    return new Set(this.adults.filter((adult) => adult.isInactive).map((adult) => adult.key));
  }

  get activeChildrenEl() {
    const inactiveKeys = this.inactiveChildKeys;
    return this.childrenEl.filter((section) => !inactiveKeys.has(section.dataset?.key));
  }

  get activeAdultsEl() {
    const inactiveKeys = this.inactiveAdultKeys;
    return this.adultsEl.filter((section) => !inactiveKeys.has(section.dataset?.key));
  }

  get memberStatusUpdates() {
    return [...this.children, ...this.adults]
      .filter((member) => member.isExisting && member.initialData?.recordId)
      .map((member) => ({
        contactId: member.initialData.recordId,
        status: member.isActive ? "Active" : "Inactive",
        reason: member.isActive ? null : String(member.statusReason || "").trim()
      }));
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
    if (this.showEntryGate && this._focusGate) {
      this._focusGate = false;
      this.template.querySelector("[data-lookup-ssn]")?.focus();
    }
    if (this.entryGateComplete && this._focusForm) {
      this._focusForm = false;
      this.template.querySelector('[data-form-heading]')?.focus();
    }

    const activeChildCount = this.activeChildrenEl.length;
    const activeAdultCount = this.activeAdultsEl.length;
    if (
      this.childrenPayload?.length === activeChildCount &&
      this.adultsPayload?.length === activeAdultCount
    ) {
      return;
    }

    this.updateSummary();
  }

  updateSummary() {
    const applicant = this.applicantEl;
    const children = this.activeChildrenEl;
    const adults = this.activeAdultsEl;

    this.applicantPayload = applicant?.payload || null;
    this.adultsPayload = adults.map((adult) => adult.payload);
    this.childrenPayload = children.map((child) => child.payload);
  }

  generateUniqueId(prefix = "uid") {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).substring(2)}`.toUpperCase();
  }

  addChildHandler() {
    const key = this.generateUniqueId("child");
    const title = `Child ${this.children.length + 1}`;

    this.children = [
      ...this.children,
      {
        key,
        title,
        initialData: null,
        isExisting: false,
        isActive: true,
        isInactive: false,
        statusReason: "",
        statusReasonError: ""
      }
    ];
  }


  removeChildHandler(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;
    this.children = renumberMembers(
      this.children.filter((child) => child.key !== key || child.isExisting),
      "Child"
    );
    this.submissionError = "";
    this.updateSummary();
  }

  handleChildStatusChange(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;

    const isActive = event.target.checked === true;
    this.children = this.children.map((child) =>
      child.key === key
        ? {
            ...child,
            isActive,
            isInactive: !isActive,
            statusReason: isActive ? "" : child.statusReason,
            statusReasonError: ""
          }
        : child
    );

    this.submissionError = "";
    this.updateSummary();
  }

  handleChildStatusReasonChange(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;

    const statusReason = event.target.value || "";
    this.children = this.children.map((child) =>
      child.key === key
        ? { ...child, statusReason, statusReasonError: "" }
        : child
    );
  }

  addAdultHandler() {
    const key = this.generateUniqueId("adult");
    const title = `Adult ${this.adults.length + 1}`;

    this.adults = [
      ...this.adults,
      {
        key,
        title,
        initialData: null,
        isExisting: false,
        isActive: true,
        isInactive: false,
        statusReason: "",
        statusReasonError: ""
      }
    ];
  }


  removeAdultHandler(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;
    this.adults = renumberMembers(
      this.adults.filter((adult) => adult.key !== key || adult.isExisting),
      "Adult"
    );
    this.submissionError = "";
    this.updateSummary();
  }

  handleAdultStatusChange(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;

    const isActive = event.target.checked === true;
    this.adults = this.adults.map((adult) =>
      adult.key === key
        ? {
            ...adult,
            isActive,
            isInactive: !isActive,
            statusReason: isActive ? "" : adult.statusReason,
            statusReasonError: ""
          }
        : adult
    );

    this.submissionError = "";
    this.updateSummary();
  }

  handleAdultStatusReasonChange(event) {
    const key = event.target?.dataset?.key;
    if (!key) return;

    const statusReason = event.target.value || "";
    this.adults = this.adults.map((adult) =>
      adult.key === key
        ? { ...adult, statusReason, statusReasonError: "" }
        : adult
    );
  }

  validateMemberStatusReasons() {
    let firstInvalidKey = null;

    const validateList = (members) =>
      members.map((member) => {
        if (!member.isExisting || member.isActive) {
          return { ...member, statusReasonError: "" };
        }

        const statusReason = String(member.statusReason || "").trim();
        const statusReasonError = statusReason
          ? ""
          : "Reason is required when a household member is Inactive.";

        if (statusReasonError && !firstInvalidKey) {
          firstInvalidKey = member.key;
        }

        return { ...member, statusReason, statusReasonError };
      });

    this.children = validateList(this.children);
    this.adults = validateList(this.adults);

    if (firstInvalidKey) {
      if (typeof globalThis.requestAnimationFrame === "function") {
        globalThis.requestAnimationFrame(() => {
          const field = this.template.querySelector(
            `[data-status-reason="${firstInvalidKey}"]`
          );
          field?.scrollIntoView?.({ behavior: "smooth", block: "center" });
          field?.focus?.();
        });
      }
      this.submissionError = "Enter a reason for every household member marked Inactive.";
      return false;
    }

    return true;
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

  getPrimaryAdultPayload(adults) {
    return Array.isArray(adults) && adults.length > 0 ? adults[0] : null;
  }

  buildApplicantObject(applicant) {
    return {
      sobjectType: "Contact",
      ...this.existingIdentityFields(applicant),
      ...this.submittedSsnFields(applicant),
      GenderIdentity: applicant.fieldsMap.Gender?.value || null,
      FirstName: applicant.fieldsMap.FirstName?.value || null,
      LastName: applicant.fieldsMap.LastName?.value || null,
      MailingStreet: applicant.fieldsMap.Street?.value || null,
      MailingCity: applicant.fieldsMap.City?.value || null,
      MailingState: applicant.fieldsMap.State?.value || null,
      MailingPostalCode: applicant.fieldsMap.ZipCode?.value || null,
      Birthdate: applicant.fieldsMap.DateOfBirth?.value || null,

      Phone: applicant.fieldsMap.Phone?.value || null,
      Email: applicant.fieldsMap.EmailAddress?.value || null,
      TLG_Employed_or_unemployed__c:
        applicant.fieldsMap.EmploymentStatus?.value || null,
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
      TLG_Veterans__c: applicant.fieldsMap.Veterans?.value || null
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
        ...this.existingIdentityFields(child),
        ...this.submittedSsnFields(child),
        FirstName: child.fieldsMap.FirstName?.value || null,
        LastName: child.fieldsMap.LastName?.value || null,
        Birthdate: child.fieldsMap.DateOfBirth?.value || null,
        GenderIdentity: child.fieldsMap.Gender?.value || null,
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
        ...this.existingIdentityFields(adult),
        ...this.submittedSsnFields(adult),
        FirstName: adult.fieldsMap.FirstName?.value || null,
        LastName: adult.fieldsMap.LastName?.value || null,
        Birthdate: adult.fieldsMap.DateOfBirth?.value || null,
        GenderIdentity: adult.fieldsMap.Gender?.value || null,

        Phone: adult.fieldsMap.Phone?.value || null,
        TLG_Employed_or_unemployed__c:
          adult.fieldsMap.EmploymentStatus?.value || null,
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
        TLG_Veterans__c: adult.fieldsMap.Veterans?.value || null
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

  buildHouseholdExpenseObject(applicant, accountName) {
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
      applicant?.fieldsMap?.ChristmasConsent?.value || false
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

    return {
      sobjectType: "Case",
      RecordType: {
        DeveloperName: this.isChristmasFlow
          ? "Christmas_Application"
          : this.isUsedCarFlow
            ? "Used_Car_Application"
            : "Assistance_Application"
      },
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
      TLG_Christmas_Assistance__c: this.isChristmasFlow,
TLG_Used_Car_Assistance__c: this.isUsedCarFlow,
      Interested_in_Santa_Gifts__c:
        applicant?.fieldsMap?.ChristmasConsent?.value || false,
      Origin: "Web"
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
    const householdSize = 1 + this.activeChildrenEl.length + this.activeAdultsEl.length;
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

  async proceedFromPage1() {
    if (!this.applicantEl || this.isProcessing) return;

    this.isProcessing = true;
    this.submissionError = "";

    try {
      if (this.reuseAccountId && !this.validateMemberStatusReasons()) return;

      const sections = [
        this.applicantEl,
        ...this.activeChildrenEl,
        ...this.activeAdultsEl,
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

      if (!this.validateUniqueMembers()) return;

      this.payloads = {
        applicant: this.applicantEl.payload,
        children: this.activeChildrenEl.map((child) => child.payload),
        adults: this.activeAdultsEl.map((adult) => adult.payload),
        householdExpense: this.householdExpenseEl.payload,
        householdIncome: this.householdIncomeEl.payload,
        householdSituation: this.householdSituationEl.payload
      };

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
      this.submissionError = "The application could not be processed. Please review your entries and try again.";
    } finally {
      this.isProcessing = false;
    }
  }

  async proceedFromPage2() {
    if (!this.assistanceEl || this.isProcessing) return;

    this.isProcessing = true;
    this.submissionError = "";

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
      this.submissionError = "The application could not be processed. Please try again.";
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
      accountName
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
      ...householdExpenseObject
    };

    const payload = {
      reuseAccountId: this.reuseAccountId,
      reuseRecordVersions: this.reuseRecordVersions,
      account: account,
      assistanceCase: caseObject,
      applicant: applicantObject,
      children: childObjectList,
      adults: adultObjectList,
      memberStatusUpdates: this.reuseAccountId ? this.memberStatusUpdates : [],
      landlord: landlordObject,
    };

    const result = await save({ payloadJson: JSON.stringify(payload) });

    if (result === "OK") {
      this.reuseAccountId = null;
      this.reuseRecordVersions = null;
      this.applicantInitialData = null;
      this.children = [];
      this.adults = [];
      this.payloads = {};
      this.applicantPayload = null;
      this.adultsPayload = [];
      this.childrenPayload = [];
      this.setPage(PAGE3);
    } else {
      this.submissionError = result || "The application could not be saved. Please try again.";
    }
  }
}