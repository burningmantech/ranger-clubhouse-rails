import {Controller} from "@hotwired/stimulus";

export default class extends Controller {
    static values = {
        label: String,
        domId: String,
        turboSrc: String,
    }

    connect() {
        // Nothing to toggle without a target. Nothing is bound either, so a
        // click on such an element stays harmless.
        if (!this.hasDomIdValue) return;

        this.toggleClick = this.toggleClick.bind(this);
        this.element.addEventListener("click", this.toggleClick);
        this.targetElement = document.getElementById(this.domIdValue)
        // The trigger's own aria-expanded describes the target's starting
        // state, so reading it keeps one source of truth rather than guessing
        // from the target's class list. Callers that leave it off get the
        // collapsed default stamped on, which is what screen readers need to
        // announce the control as a disclosure before it is ever clicked.
        this.toggled = this.element.getAttribute("aria-expanded") === "true";
        this.element.setAttribute("aria-expanded", this.toggled ? "true" : "false");
        // Remembered now rather than on the first click: a restored page can
        // hand back a control that is already expanded, and collapsing it has
        // to put a real label back instead of an empty one.
        this.oldHTML = this.toggled ? null : this.element.innerHTML;
    }

    disconnect() {
        if (this.toggleClick) {
            this.element.removeEventListener("click", this.toggleClick);
        }
    }

    toggleClick(event) {
        event.preventDefault();

        const open = !this.toggled;
        if (this.hasLabelValue) {
            if (open) {
                this.oldHTML = this.element.innerHTML;
                this.element.innerHTML = this.labelValue;
            } else if (this.oldHTML !== null) {
                this.element.innerHTML = this.oldHTML;
            }
        }
        // Both names, as the markup has them: hidden! outweighs a display
        // utility such as flex on the target.
        this.targetElement.classList.toggle("hidden", !open);
        this.targetElement.classList.toggle("hidden!", !open);
        this.targetElement.setAttribute("aria-hidden", String(!open));
        this.element.setAttribute("aria-expanded", String(open));
        if (open && this.hasTurboSrcValue) {
            this.targetElement.src = this.turboSrcValue;
        }

        this.toggled = open;
    }
}
