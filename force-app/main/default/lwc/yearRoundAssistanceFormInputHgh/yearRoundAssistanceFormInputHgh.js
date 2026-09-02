import { LightningElement, api } from "lwc";

export default class YearRoundAssistanceFormInputHgh extends LightningElement {
  @api name;
  @api label;
  @api placeholder;
  @api required;
  @api minDate;
  @api maxDate;

  _type = "text";
  _disabled = false;
  _restrictTyping = false;
  _dateValue = "";

  errorMessage = "";
  showError = false;

  renderedCallback() {
    if (this._type === "date") return;
    if (!this.inputEl || this.disabled === undefined) return;
    this.inputEl.disabled = this.disabled;
  }

  get isDateType() {
    return this._type === "date";
  }

  get dateInputEl() {
    return this.template.querySelector("lightning-input");
  }

  get id() {
    return this.name.replaceAll(/[^a-zA-Z0-9]+/g, "-");
  }

  get inputId() {
    return `${this.id}-input`;
  }

  get textareaId() {
    return `${this.id}-textarea`;
  }

  get controlId() {
    return this.showInput ? this.inputId : this.textareaId;
  }

  get inputEl() {
    return (
      this.template.querySelector(`input[name=${this.name}]`) ||
      this.template.querySelector(`textarea[name=${this.name}]`)
    );
  }

  get showInput() {
    return this.type !== "textarea";
  }

  get inputType() {
    return this._type;
  }

  get inputPlaceholder() {
    return this.placeholder;
  }

  @api get type() {
    return this._type;
  }

  set type(value) {
    const formattedType = (value || "").toString().trim().toLowerCase();
    this._type = /^(text|date|textarea)$/i.test(formattedType)
      ? formattedType
      : "text";
  }

  @api get disabled() {
    return this._disabled === true;
  }

  set disabled(value) {
    this._disabled = /^(true|yes|y)$/i.test(value);

    if (this._type === "date") {
      if (this._disabled) {
        this._dateValue = "";
        this.setCustomValidity("");
        this.reportValidity();
      }
      return;
    }

    if (!this.inputEl) return;
    this.inputEl.disabled = this._disabled;
    if (this._disabled) {
      this.inputEl.value = "";
      this.setCustomValidity("");
      this.reportValidity();
    }
  }

  @api get restrictTyping() {
    return this._restrictTyping === true;
  }

  set restrictTyping(value) {
    this._restrictTyping = /^(true|yes|y)$/i.test(value);
  }

  @api get value() {
    if (this._type === "date") {
      return this.dateInputEl?.value || this._dateValue || "";
    }
    return this.inputEl?.value || "";
  }

  set value(newValue) {
    if (this._type === "date") {
      this._dateValue = newValue || "";
      const el = this.dateInputEl;
      if (el) el.value = this._dateValue;
      return;
    }
    const inputEl = this.inputEl;
    if (inputEl) inputEl.value = newValue || "";
  }

  @api setCustomValidity(errorMessage) {
    if (this._type === "date") {
      const el = this.dateInputEl;
      if (el) el.setCustomValidity(errorMessage || "");
      return;
    }
    this.errorMessage = (errorMessage || "").trim();
  }

  @api reportValidity() {
    if (this._type === "date") {
      const el = this.dateInputEl;
      if (el) return el.reportValidity();
      return true;
    }
    this.showError = Boolean(this.errorMessage);
    if (this.showError) {
      this.scrollIntoView();
    }
    return !this.showError;
  }

  @api scrollIntoView() {
    const containerEl = this.template.querySelector(`div[data-id="container"]`);
    if (!containerEl) return;
    const y = containerEl.getBoundingClientRect().top + globalThis.scrollY;
    globalThis.scroll({ top: y, behavior: "smooth" });
  }

  get styling() {
    if (this._type === "date") return "slds-form-element";
    return this.showError
      ? "slds-form-element slds-has-error"
      : "slds-form-element";
  }

  blurHandler() {
    this.dispatchEvent(
      new CustomEvent("blur", { detail: { value: this.value } })
    );
  }

  changeHandler() {
    this.dispatchEvent(
      new CustomEvent("change", { detail: { value: this.value } })
    );
  }

  dateChangeHandler(event) {
    this._dateValue = event.detail.value || "";
    this.dispatchEvent(
      new CustomEvent("change", { detail: { value: this._dateValue } })
    );
  }

  dateBlurHandler() {
    const blurEvent = new CustomEvent("blur", { detail: { value: this.value } });
    this.dispatchEvent(blurEvent);
  }

  keypressHandler(event) {
    this.dispatchEvent(
      new CustomEvent("change", { detail: { value: this.value } })
    );
    if (this.restrictTyping) {
      if (event.preventDefault) {
        event.preventDefault();
      } else {
        event.returnValue = false;
      }
    }
  }
}