import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

// Warns before the page is left with unsaved changes. Attach with
// data: { controller: "unsaved-changes" } on any ui_form; nothing
// form-specific lives here.
//
// A page whose "unsaved" is a state of its own rather than an edited field
// (the HQ shift page) extends this and overrides guard(): return
// { question, ... } to ask before leaving -- question being a confirm as
// application.js takes one -- or null to let the visit through.
// guardConfirmed and guardDeclined hear the answer.
//
// A visit inside the site asks in the app's dialog. The dialog answers later,
// so the visit is stopped, and on yes started again with what it carried.
// Closing or reloading the tab gets the browser's own prompt: nothing else
// can ask then. Back and Forward are not asked about: Turbo restores those
// pages without a turbo:before-visit, and the browser asks nothing either.
//
// A form drawn again with what was typed -- a refused or questioned save --
// sets data-unsaved-changes-dirty-value="true": the submit that brought it back
// disarmed the guard, and the edits are still unsaved.
export default class extends Controller {
    static values = { dirty: Boolean };

    connect() {
        this.dirty = this.dirtyValue;

        this.markDirty = this.markDirty.bind(this);
        this.clearDirty = this.clearDirty.bind(this);
        this.handleBeforeUnload = this.handleBeforeUnload.bind(this);
        this.handleTurboBeforeVisit = this.handleTurboBeforeVisit.bind(this);
        this.rememberClick = this.rememberClick.bind(this);
        this.rememberSubmission = this.rememberSubmission.bind(this);

        this.element.addEventListener("input", this.markDirty);
        this.element.addEventListener("change", this.markDirty);
        this.element.addEventListener("submit", this.clearDirty);
        window.addEventListener("beforeunload", this.handleBeforeUnload);
        document.addEventListener("turbo:before-visit", this.handleTurboBeforeVisit);
        document.addEventListener("turbo:click", this.rememberClick);
        document.addEventListener("turbo:submit-end", this.rememberSubmission);
    }

    disconnect() {
        this.element.removeEventListener("input", this.markDirty);
        this.element.removeEventListener("change", this.markDirty);
        this.element.removeEventListener("submit", this.clearDirty);
        window.removeEventListener("beforeunload", this.handleBeforeUnload);
        document.removeEventListener("turbo:before-visit", this.handleTurboBeforeVisit);
        document.removeEventListener("turbo:click", this.rememberClick);
        document.removeEventListener("turbo:submit-end", this.rememberSubmission);
    }

    markDirty() {
        this.dirty = true;
    }

    // A morph that redraws the form reports the value only when it changes, so
    // clearDirty() sets it false first.
    dirtyValueChanged(value) {
        if (value) this.dirty = true;
    }

    clearDirty() {
        this.dirty = false;
        this.dirtyValue = false;
    }

    // The question to ask before leaving, or null when leaving is fine.
    guard() {
        if (!this.dirty) return null;

        return {
            question: {
                title: "Unsaved Changes",
                message: "Leave this page? Your changes have not been saved and will be lost.",
                confirmLabel: "Leave Page",
                cancelLabel: "Stay on Page",
                variant: "error"
            }
        };
    }

    guardConfirmed(_guard) {}

    guardDeclined(_guard) {}

    handleBeforeUnload(event) {
        // A leave already agreed to in the dialog is not asked about again
        // when Turbo turns that visit into a full page load.
        if (this.leaveConfirmed || !this.guard()) return;

        // Browsers ignore custom text and show their own generic message —
        // both preventDefault() and returnValue are required for Chrome/Firefox.
        event.preventDefault();
        event.returnValue = "";
    }

    async handleTurboBeforeVisit(event) {
        // A page whose sign-in has ended leaves without asking: nothing on it
        // can be saved now (session_watch_controller.js).
        if (document.documentElement.hasAttribute("data-signed-out")) return;

        // The visit started again below, after a yes.
        if (this.leaveConfirmed) return;

        // A visit proposed while the dialog is up (a stream's redirect, say)
        // is dropped: the reader is answering about the first one.
        if (this.asking) {
            event.preventDefault();
            return;
        }

        const guard = this.guard();
        if (!guard) return;

        event.preventDefault();
        this.asking = true;
        const url = event.detail.url;
        const options = await this.visitOptionsFor(url);

        const confirmed = await Turbo.config.forms.confirm(guard.question, this.element);
        this.asking = false;

        if (confirmed) {
            this.guardConfirmed(guard);
            this.leaveConfirmed = true;
            Turbo.visit(url, options);
        } else {
            this.guardDeclined(guard);
        }
    }

    // What the stopped visit carried, so the one started again on yes is the
    // same, as Turbo would have chosen it: a link's data-turbo-action, or a
    // form's answer -- its page and the flash in it are not fetched again.
    rememberClick({ target, detail }) {
        this.lastClick = { url: detail.url, action: visitAction(target) };
    }

    rememberSubmission({ detail }) {
        this.lastSubmission = detail;
    }

    async visitOptionsFor(url) {
        const { formSubmission, fetchResponse } = this.lastSubmission ?? {};
        this.lastSubmission = null;

        if (fetchResponse?.location?.href === url) {
            const sameLocation = fetchResponse.redirected && url === window.location.href;
            return {
                action: visitAction(formSubmission.submitter, formSubmission.formElement) ??
                    (sameLocation ? "replace" : "advance"),
                shouldCacheSnapshot: formSubmission.isSafe,
                response: {
                    statusCode: fetchResponse.statusCode,
                    responseHTML: await fetchResponse.responseHTML,
                    redirected: fetchResponse.redirected
                }
            };
        }

        return { action: (this.lastClick?.url === url && this.lastClick.action) || "advance" };
    }
}

// The data-turbo-action of the first element that has one, if Turbo takes it.
function visitAction(...elements) {
    const action = elements.map((element) => element?.getAttribute?.("data-turbo-action")).find(Boolean);
    return ["advance", "replace", "restore"].includes(action) ? action : null;
}
