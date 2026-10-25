import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["short", "full", "toggle", "label", "icon"]
    static values = {
        moreText: {type: String, default: "more"},
        lessText: {type: String, default: "less"}
    }

    connect() {
        this.expanded = false
        this.updateState()
    }

    toggle(event) {
        event.preventDefault()
        this.expanded = !this.expanded
        this.updateState()
    }

    updateState() {
        if (this.expanded) {
            this.shortTarget.classList.add("hidden")
            this.fullTarget.classList.remove("hidden")
            if (this.hasToggleTarget) {
                this.toggleTarget.setAttribute("aria-expanded", "true")
            }
            // Update label text if separate label target exists
            if (this.hasLabelTarget) {
                this.labelTarget.textContent = this.lessTextValue
            } else if (this.hasToggleTarget) {
                this.toggleTarget.textContent = this.lessTextValue
            }
            // Rotate icon if it exists
            if (this.hasIconTarget) {
                this.iconTarget.classList.add("rotate-180")
            }
        } else {
            this.shortTarget.classList.remove("hidden")
            this.fullTarget.classList.add("hidden")
            if (this.hasToggleTarget) {
                this.toggleTarget.setAttribute("aria-expanded", "false")
            }
            // Update label text if separate label target exists
            if (this.hasLabelTarget) {
                this.labelTarget.textContent = this.moreTextValue
            } else if (this.hasToggleTarget) {
                this.toggleTarget.textContent = this.moreTextValue
            }
            // Reset icon rotation
            if (this.hasIconTarget) {
                this.iconTarget.classList.remove("rotate-180")
            }
        }
    }
}

