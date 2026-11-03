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
        // The trigger's own aria-expanded is the one record of the target's
        // state, read rather than guessed from the target's class list.
        // Callers that leave it off get the collapsed default stamped on,
        // which is what screen readers need to announce the control as a
        // disclosure before it is ever clicked.
        this.element.setAttribute("aria-expanded", String(this.expanded));
        // Remembered now rather than on the first click: a restored page can
        // hand back a control that is already expanded, and collapsing it has
        // to put a real label back instead of an empty one.
        this.oldHTML = this.expanded ? null : this.element.innerHTML;
    }

    // Whether the target is showing, as the trigger says.
    get expanded() {
        return this.element.getAttribute("aria-expanded") === "true";
    }

    disconnect() {
        if (this.toggleClick) {
            this.element.removeEventListener("click", this.toggleClick);
        }
    }

    toggleClick(event) {
        event.preventDefault();

        const open = !this.expanded;
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
    }
}
