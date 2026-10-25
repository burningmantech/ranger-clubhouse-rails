import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
    connect() {
        // Automatically focus first error field on page load or Turbo update
        this.focusFirstError();
    }

    submit() {
        this.element.requestSubmit();
    }

    /**
     * Move focus to the validation feedback and scroll it into view.
     * Prefer the error summary (role="alert") so screen readers announce the
     * full list of errors; otherwise focus the first errored field.
     */
    focusFirstError() {
        // The summary is rendered as a sibling of the form, outside this element.
        const summary = this.element.parentElement?.querySelector('#form-error-summary')
            || document.getElementById('form-error-summary');

        if (summary) {
            summary.focus();
            summary.scrollIntoView({ behavior: 'smooth', block: 'center' });
            return;
        }

        const firstError = this.element.querySelector(
            '.input-error, .select-error, .textarea-error, .radio-error, .file-input-error'
        );

        if (firstError) {
            firstError.focus();
            firstError.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
    }
}
