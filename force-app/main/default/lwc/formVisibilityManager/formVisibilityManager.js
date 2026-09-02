import { LightningElement, track, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAllFormCatalogs from "@salesforce/apex/FormVisibilityController.getAllFormCatalogs";
import updateFormStatus from "@salesforce/apex/FormVisibilityController.updateFormStatus";
import createFormCatalog from "@salesforce/apex/FormVisibilityController.createFormCatalog";

const CANONICAL_FORM_NAMES = Object.freeze([
  {
    key: "general-assistance",
    label: "General Assistance",
    name: "General Assistance Application"
  },
  {
    key: "used-car",
    label: "Used Car / Car Repair",
    name: "Used Car / Car Repair Application"
  },
  {
    key: "christmas",
    label: "Christmas Assistance",
    name: "Christmas Assistance Application"
  }
]);

function normalizeFormName(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll("assitance", "assistance")
    .replaceAll(/[^a-z0-9]+/gu, " ")
    .trim();
}

export default class FormVisibilityManager extends LightningElement {
  @track formCatalogs = [];
  @track isLoading = true;
  @track error;
  @track lastSavedFormId;
  @track pendingChanges = new Map();
  wiredFormsResult;

  // New-form modal state
  @track showNewFormModal = false;
  @track newFormName = "";
  @track newFormIsActive = true;
  @track newFormMessage = "";
  @track newFormStartDate = "";
  @track newFormEndDate = "";

  connectedCallback() {
    document.title = "Form Visibility Manager";
  }

  get canonicalForms() {
    return CANONICAL_FORM_NAMES;
  }

  enrichFormCatalog(form) {
    const canonicalMatch = this.getCanonicalMatch(form.Name);

    return {
      ...form,
      rowClass: form.Id === this.lastSavedFormId ? "highlight-row" : "",
      statusBadgeClass:
        form.Status__c === "Active"
          ? "status-badge status-badge-active"
          : "status-badge status-badge-inactive",
      statusLabel: form.Status__c === "Active" ? "Active" : "Inactive",
      isActiveBool: form.Status__c === "Active",
      showMessage: form.Status__c === "Inactive",
      hasChanges: false,
      canonicalName: canonicalMatch?.name || "",
      canonicalLabel: canonicalMatch?.label || "",
      isCanonicalWebsiteForm: Boolean(canonicalMatch),
      canonicalHintClass: canonicalMatch
        ? "canonical-hint canonical-hint-match"
        : "canonical-hint canonical-hint-custom",
      canonicalHintText: canonicalMatch
        ? `Canonical website form: ${canonicalMatch.name}`
        : "Custom/admin form — not one of the three public assistance forms"
    };
  }

  getCanonicalMatch(formName) {
    const normalizedName = normalizeFormName(formName);

    return CANONICAL_FORM_NAMES.find((form) => {
      const normalizedCanonical = normalizeFormName(form.name);
      if (normalizedName === normalizedCanonical) {
        return true;
      }

      if (
        form.key === "general-assistance" &&
        (normalizedName.includes("year round") ||
          normalizedName.includes("general assistance"))
      ) {
        return true;
      }

      if (
        form.key === "used-car" &&
        (normalizedName.includes("used car") ||
          normalizedName.includes("repair car") ||
          normalizedName.includes("car repair"))
      ) {
        return true;
      }

      if (
        form.key === "christmas" &&
        normalizedName.includes("christmas")
      ) {
        return true;
      }

      return false;
    });
  }

  getButtonVariant(hasChanges) {
    return hasChanges ? "brand" : "neutral";
  }
  getButtonDisabled(hasChanges) {
    return !hasChanges;
  }

  highlightRow(formId) {
    this.lastSavedFormId = formId;
    this.formCatalogs = this.formCatalogs.map((form) => ({
      ...form,
      rowClass: form.Id === formId ? "highlight-row" : "",
      statusBadgeClass:
        form.Status__c === "Active"
          ? "status-badge status-badge-active"
          : "status-badge status-badge-inactive",
      statusLabel: form.Status__c === "Active" ? "Active" : "Inactive",
      isActiveBool: form.Status__c === "Active"
    }));
  }

  refreshData() {
    this.isLoading = true;
    return refreshApex(this.wiredFormsResult).finally(() => {
      this.isLoading = false;
    });
  }

  @wire(getAllFormCatalogs)
  wiredForms(result) {
    this.wiredFormsResult = result;
    this.isLoading = true;
    if (result.data) {
      const data = structuredClone(result.data);
      this.formCatalogs = data.map((form) => this.enrichFormCatalog(form));
      this.error = undefined;
      this.pendingChanges.clear();
    } else if (result.error) {
      this.error = result.error;
      this.formCatalogs = [];
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error loading form data",
          message: result.error.message,
          variant: "error"
        })
      );
    }
    this.isLoading = false;
  }

  handleToggleActive(event) {
    const formId = event.target.dataset.id;
    const isActive = event.target.checked;
    const index = this.formCatalogs.findIndex((f) => f.Id === formId);
    if (index === -1) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: "Form not found in local data. Please refresh.",
          variant: "error"
        })
      );
      return;
    }
    this.formCatalogs[index].Status__c = isActive ? "Active" : "Inactive";
    this.formCatalogs[index].statusBadgeClass = isActive
      ? "status-badge status-badge-active"
      : "status-badge status-badge-inactive";
    this.formCatalogs[index].statusLabel = isActive ? "Active" : "Inactive";
    this.formCatalogs[index].isActiveBool = isActive;
    this.formCatalogs[index].showMessage = !isActive;
    this.formCatalogs[index].hasChanges = true;

    if (!this.pendingChanges.has(formId)) this.pendingChanges.set(formId, {});
    this.pendingChanges.get(formId).isActive = isActive;

    this.formCatalogs = [...this.formCatalogs];
  }

  handleMessageChange(event) {
    const formId = event.target.dataset.id;
    const message = event.target.value;
    const index = this.formCatalogs.findIndex((f) => f.Id === formId);
    if (index !== -1) {
      this.formCatalogs[index].Message__c = message;
      this.formCatalogs[index].hasChanges = true;
      if (!this.pendingChanges.has(formId)) this.pendingChanges.set(formId, {});
      this.pendingChanges.get(formId).message = message;
      this.formCatalogs = [...this.formCatalogs];
    }
  }

  // Start/End date handlers
  handleStartDateChange(event) {
    const formId = event.target.dataset.id;
    const value = event.detail.value; // 'YYYY-MM-DD'
    this.updateFormField(formId, "Start_Date__c", value);
  }
  handleEndDateChange(event) {
    const formId = event.target.dataset.id;
    const value = event.detail.value;
    this.updateFormField(formId, "End_Date__c", value);
  }
  updateFormField(id, field, value) {
    const idx = this.formCatalogs.findIndex((f) => f.Id === id);
    if (idx === -1) return;
    const updated = {
      ...this.formCatalogs[idx],
      [field]: value,
      hasChanges: true
    };
    this.formCatalogs = [
      ...this.formCatalogs.slice(0, idx),
      updated,
      ...this.formCatalogs.slice(idx + 1)
    ];
    if (!this.pendingChanges.has(id)) this.pendingChanges.set(id, {});
    this.pendingChanges.get(id)[field] = value;
  }

  handleSaveForm(event) {
    const formId = event.target.dataset.id;
    const index = this.formCatalogs.findIndex((f) => f.Id === formId);
    if (index === -1) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: "Form not found. Please refresh and try again.",
          variant: "error"
        })
      );
      return;
    }
    if (!this.pendingChanges.has(formId)) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Info",
          message: "No changes to save.",
          variant: "info"
        })
      );
      return;
    }

    const changes = this.pendingChanges.get(formId);
    const current = this.formCatalogs[index];

    const isActive = Object.hasOwn(changes, "isActive")
      ? changes.isActive
      : current.Status__c === "Active";
    const message = Object.hasOwn(changes, "message")
      ? changes.message
      : current.Message__c;
    const startDate = Object.hasOwn(changes, "Start_Date__c")
      ? changes.Start_Date__c
      : current.Start_Date__c;
    const endDate = Object.hasOwn(changes, "End_Date__c")
      ? changes.End_Date__c
      : current.End_Date__c;

    if (startDate && endDate && endDate < startDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Validation Error",
          message: "End Date cannot be before Start Date.",
          variant: "error"
        })
      );
      return;
    }

    this.isLoading = true;
    updateFormStatus({
      formId,
      isActive,
      message,
      startDate: startDate || null,
      endDate: endDate || null
    })
      .then(() => {
        this.highlightRow(formId);
        this.pendingChanges.delete(formId);
        this.formCatalogs[index].hasChanges = false;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "Form updated successfully",
            variant: "success"
          })
        );
        return refreshApex(this.wiredFormsResult);
      })
      .catch((error) => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error updating form",
            message: error?.body?.message || error.message,
            variant: "error"
          })
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Modal open/close
  handleOpenNewFormModal() {
    this.showNewFormModal = true;
  }
  handleCloseNewFormModal() {
    this.showNewFormModal = false;
    this.newFormName = "";
    this.newFormIsActive = true;
    this.newFormMessage = "";
    this.newFormStartDate = "";
    this.newFormEndDate = "";
  }

  // New-form handlers
  handleNewFormNameChange(e) {
    this.newFormName = e.target.value;
  }
  handleNewFormStatusChange(e) {
    this.newFormIsActive = e.target.checked;
  }
  handleNewFormMessageChange(e) {
    this.newFormMessage = e.target.value;
  }
  handleNewFormStartDateChange(e) {
    this.newFormStartDate = e.detail.value;
  }
  handleNewFormEndDateChange(e) {
    this.newFormEndDate = e.detail.value;
  }

  handleCreateForm() {
    if (!this.newFormName) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: "Form name is required",
          variant: "error"
        })
      );
      return;
    }
    if (
      this.newFormStartDate &&
      this.newFormEndDate &&
      this.newFormEndDate < this.newFormStartDate
    ) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Validation Error",
          message: "End Date cannot be before Start Date.",
          variant: "error"
        })
      );
      return;
    }

    this.isLoading = true;
    createFormCatalog({
      formName: this.newFormName,
      isActive: this.newFormIsActive,
      message: this.newFormMessage,
      startDate: this.newFormStartDate || null,
      endDate: this.newFormEndDate || null
    })
      .then((id) => {
        this.lastSavedFormId = id;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "Form created successfully",
            variant: "success"
          })
        );
        this.handleCloseNewFormModal();
        return refreshApex(this.wiredFormsResult);
      })
      .catch((error) => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error creating form",
            message: error?.body?.message || error.message,
            variant: "error"
          })
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleUseCanonicalName(event) {
    this.newFormName = event.target.dataset.name || "";
  }
}