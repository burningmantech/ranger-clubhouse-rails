import { Controller } from "@hotwired/stimulus";

// Warns before the page is left with unsaved changes. Attach with
// data: { controller: "unsaved-changes" } on any ui_form; nothing
// form-specific lives here.
//
// A page whose "unsaved" is a state of its own rather than an edited field
// (the HQ shift page) extends this and overrides guard(): return
// { message, ... } to ask before leaving, or null to let the visit through.
// guardConfirmed and guardDeclined hear the answer.
export default class extends Controller {
    connect() {
        this.dirty = false;

        this.markDirty = this.markDirty.bind(this);
        this.clearDirty = this.clearDirty.bind(this);
        this.handleBeforeUnload = this.handleBeforeUnload.bind(this);
        this.handleTurboBeforeVisit = this.handleTurboBeforeVisit.bind(this);

        this.element.addEventListener("input", this.markDirty);
        this.element.addEventListener("change", this.markDirty);
        this.element.addEventListener("submit", this.clearDirty);
        window.addEventListener("beforeunload", this.handleBeforeUnload);
        document.addEventListener("turbo:before-visit", this.handleTurboBeforeVisit);
    }

    disconnect() {
        this.element.removeEventListener("input", this.markDirty);
        this.element.removeEventListener("change", this.markDirty);
        this.element.removeEventListener("submit", this.clearDirty);
        window.removeEventListener("beforeunload", this.handleBeforeUnload);
        document.removeEventListener("turbo:before-visit", this.handleTurboBeforeVisit);
    }

    markDirty() {
        this.dirty = true;
    }

    clearDirty() {
        this.dirty = false;
    }

    // The question to ask before leaving, or null when leaving is fine.
    guard() {
        if (!this.dirty) return null;

        return { message: "You have unsaved changes. Leaving this page will discard them. Continue?" };
    }

    guardConfirmed(_guard) {}

    guardDeclined(_guard) {}

    handleBeforeUnload(event) {
        if (!this.guard()) return;

        // Browsers ignore custom text and show their own generic message —
        // both preventDefault() and returnValue are required for Chrome/Firefox.
        event.preventDefault();
        event.returnValue = "";
    }

    handleTurboBeforeVisit(event) {
        const guard = this.guard();
        if (!guard) return;

        if (window.confirm(guard.message)) {
            this.guardConfirmed(guard);
        } else {
            event.preventDefault();
            this.guardDeclined(guard);
        }
    }
}
