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
