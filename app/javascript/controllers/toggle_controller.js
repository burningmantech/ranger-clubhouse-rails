import {Controller} from "@hotwired/stimulus";

export default class extends Controller {
    static values = {
        label: String,
        domId: String,
        turboSrc: String,
    }

    connect() {
        // Nothing to toggle without a target, and an empty id would make the
        // lookup itself throw. Nothing is bound either, so a click on such an
        // element stays harmless.
        if (!this.hasDomIdValue) return;

        this.toggleClick = this.toggleClick.bind(this);
        this.element.addEventListener("click", this.toggleClick);
        this.targetElement = document.querySelector(`#${this.domIdValue}`)
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

        if (this.toggled) {
            if (this.hasLabelValue && this.oldHTML !== null) {
                this.element.innerHTML = this.oldHTML;
            }
            this.targetElement.classList.add("hidden");
            this.targetElement.classList.add("hidden!");
            this.targetElement.setAttribute("aria-hidden", "true");
            this.element.setAttribute("aria-expanded", "false");
        } else {
            if (this.hasLabelValue) {
                this.oldHTML = this.element.innerHTML;
                this.element.innerHTML = this.labelValue;
            }
            this.targetElement.classList.remove("hidden");
            this.targetElement.classList.remove("hidden!");
            this.targetElement.setAttribute("aria-hidden", "false");
            this.element.setAttribute("aria-expanded", "true");

            if (this.hasTurboSrcValue) {
                this.targetElement.src = this.turboSrcValue;
            }
        }

        this.toggled = !this.toggled;
    }
}
