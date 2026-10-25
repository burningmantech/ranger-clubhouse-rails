// Modal Controller for Stimulus
// Uses native <dialog> with DaisyUI modal classes
// See: https://daisyui.com/components/modal/

import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        autofocusOnCloseId: String,
        closable: {type: Boolean, default: true}
    }

    connect() {
        this.handleCancel = this.handleCancel.bind(this)
        this.handleClose = this.handleClose.bind(this)

        // Listen for native dialog events
        this.element.addEventListener("cancel", this.handleCancel)
        this.element.addEventListener("close", this.handleClose)

        // Auto-show on connect (for Turbo Frame/Stream rendered modals). The
        // Turbo confirm dialog is the exception: application.js shows it, and
        // this controller may connect only after it has been answered and
        // closed, when showing it again would raise a dialog nothing answers.
        if (!this.element.closest("#turbo-confirm-modal")) {
            this.show()
        }
    }

    disconnect() {
        this.element.removeEventListener("cancel", this.handleCancel)
        this.element.removeEventListener("close", this.handleClose)
        if (this.element.open) {
            this.element.close()
        }
    }

    show() {
        if (this.element.open) return
        this.element.showModal()
    }

    hide() {
        if (!this.element.open) return
        this.element.close()
    }

    toggle() {
        if (this.element.open) {
            this.hide()
        } else {
            this.show()
        }
    }

    // Prevent ESC closing when closable is false
    handleCancel(event) {
        if (!this.closableValue) {
            event.preventDefault()
        }
    }

    // Cleanup after dialog closes
    handleClose() {
        // Restore focus if specified
        if (this.autofocusOnCloseIdValue) {
            document.querySelector(this.autofocusOnCloseIdValue)?.focus()
        }

        // Remove from the DOM once the closing fade has played
        setTimeout(() => {
            this.element.remove()
        }, 100)
    }

    // For form submissions that should close the modal
    closeOnSubmit() {
        this.hide()
    }
}
