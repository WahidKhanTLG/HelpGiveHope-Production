import {
    LightningElement,
    api
} from "lwc";

import {
    FlowNavigationNextEvent,
    FlowNavigationFinishEvent
} from "lightning/flowSupport";

export default class BulkWishlistEmailScreen
    extends LightningElement {

    @api mode = "confirm";
    @api message = "";
    @api availableActions = [];

    get normalizedMode() {
        return String(
            this.mode || "confirm"
        )
            .trim()
            .toLowerCase();
    }

    get isConfirm() {
        return this.normalizedMode === "confirm";
    }

    get isSuccess() {
        return this.normalizedMode === "success";
    }

    get isError() {
        return this.normalizedMode === "error";
    }

    get title() {

        if (this.isSuccess) {
            return "Wishlist Emails Processed";
        }

        if (this.isError) {
            return "Wishlist Email Error";
        }

        return "Send Wishlist Email";
    }

    get description() {

        if (this.isSuccess) {
            return "The selected Christmas applications have finished processing.";
        }

        if (this.isError) {
            return "The bulk Wishlist email process encountered an error.";
        }

        return "Send personalized Wishlist emails to the selected Christmas applications.";
    }

    get iconName() {

        if (this.isSuccess) {
            return "utility:success";
        }

        if (this.isError) {
            return "utility:error";
        }

        return "utility:email";
    }

    get cardClass() {

        if (this.isSuccess) {
            return "card success-card";
        }

        if (this.isError) {
            return "card error-card";
        }

        return "card";
    }

    get primaryLabel() {

        if (this.isConfirm) {
            return "Send Wishlist Email";
        }

        return "Done";
    }

    get displayMessage() {

        if (this.message) {
            return this.message;
        }

        if (this.isError) {
            return "An unexpected error occurred while processing the selected applications.";
        }

        return "Wishlist email processing has completed.";
    }

    get primaryDisabled() {

        if (this.isConfirm) {
            return !this.availableActions.includes(
                "NEXT"
            );
        }

        return !this.availableActions.includes(
            "FINISH"
        );
    }

    handlePrimaryAction() {

        if (
            this.isConfirm &&
            this.availableActions.includes("NEXT")
        ) {
            this.dispatchEvent(
                new FlowNavigationNextEvent()
            );

            return;
        }

        if (
            !this.isConfirm &&
            this.availableActions.includes("FINISH")
        ) {
            this.dispatchEvent(
                new FlowNavigationFinishEvent()
            );
        }
    }
}