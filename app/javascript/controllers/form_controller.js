import { Controller } from "@hotwired/stimulus";
import { scrollBehavior } from "controllers/scrolling";

export default class extends Controller {
    connect() {
        // Automatically focus first error field on page load or Turbo update
        this.focusFirstError();
    }

    submit() {
        this.element.requestSubmit();
    }

    /**
     * Move focus to the first field with an error and scroll it into view, so it
     * can be corrected at once. The error summary (role="alert") is announced
     * on its own; it takes the focus only when no field is marked, as when every
     * error is on the record rather than on one field.
     */
    focusFirstError() {
        const firstError = this.element.querySelector(
            '.input-error, .select-error, .textarea-error, .radio-error, .checkbox-error, .file-input-error'
        );
        // The summary is rendered as a sibling of the form, outside this element.
        const target = firstError
            || this.element.parentElement?.querySelector('#form-error-summary')
            || document.getElementById('form-error-summary');

        if (target) {
            target.focus();
            target.scrollIntoView({ behavior: scrollBehavior(), block: 'center' });
        }
    }
}
