import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        css: String,
        targetId: String,
    }

    connect() {
        if (this.targetIdValue) {
            this.charElement = document.getElementById(this.targetIdValue);
        } else {
            this.charElement = document.createElement("div");
            this.element.after(this.charElement);
        }
        // The count is the field's help text: heard with the field, not as
        // each character is typed.
        this.charElement.id ||= `${this.element.id || "field"}-counter-${Math.random().toString(36).slice(2, 8)}`;
        const describedBy = (this.element.getAttribute("aria-describedby") || "").split(" ").filter(Boolean);
        if (!describedBy.includes(this.charElement.id)) {
            this.element.setAttribute("aria-describedby", [...describedBy, this.charElement.id].join(" "));
        }
        this.maxlength = this.element.getAttribute("maxlength");
        this.charElement.classList.add(...this.cssValue.split(" "));
        this.updateCount = this.updateCount.bind(this);
        this.element.addEventListener("input", this.updateCount);
        this.updateCount();
    }

    disconnect() {
        this.element.removeEventListener("input", this.updateCount);
    }

    updateCount() {
        this.charElement.textContent = `${this.element.value.length} of ${this.maxlength} characters`
    }
}
