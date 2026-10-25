import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
    static values = {
        oldStatus: String,
        warnings: Object
    }

    connect() {
        this.allowSubmit = false
    }

    async submit(event) {
        if (this.allowSubmit) {
            this.allowSubmit = false
            return
        }

        const newStatus = this.statusField?.value
        if (!newStatus || newStatus === this.oldStatusValue) {
            return
        }

        const warningModal = this.warningFor(newStatus)
        if (!warningModal) {
            return
        }

        event.preventDefault()

        const confirmed = await Turbo.config.forms.confirm(warningModal, this.element, event.submitter)
        if (!confirmed) {
            return
        }

        this.allowSubmit = true
        if (event.submitter) {
            this.element.requestSubmit(event.submitter)
        } else {
            this.element.requestSubmit()
        }
    }

    get statusField() {
        return this.element.querySelector("[name='person[status]']")
    }

    warningFor(newStatus) {
        if (!this.hasWarningsValue) {
            return null
        }

        return this.warningsValue[newStatus]
    }
}
