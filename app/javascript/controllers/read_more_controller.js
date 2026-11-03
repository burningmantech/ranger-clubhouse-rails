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
        const open = this.expanded
        this.shortTarget.classList.toggle("hidden", open)
        this.fullTarget.classList.toggle("hidden", !open)
        if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(open))

        // The label's text goes in its own target where there is one, else in the toggle
        const label = open ? this.lessTextValue : this.moreTextValue
        if (this.hasLabelTarget) {
            this.labelTarget.textContent = label
        } else if (this.hasToggleTarget) {
            this.toggleTarget.textContent = label
        }

        if (this.hasIconTarget) this.iconTarget.classList.toggle("rotate-180", open)
    }
}

