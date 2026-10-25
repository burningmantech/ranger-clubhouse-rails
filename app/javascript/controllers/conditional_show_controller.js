import {Controller} from "@hotwired/stimulus";

export default class extends Controller {
    static targets = ["dependent"];
    static values = {
        id: String,
        reveal: String
    }

    connect() {
        this._inputChanged = this.inputChanged.bind(this);
        this.element.addEventListener('change', this._inputChanged);
        this.revealElement = document.querySelector(`#${this.idValue}`);
    }

    disconnect() {
        this.element.removeEventListener('change', this._inputChanged);
    }

    inputChanged() {
        if (this.element.value === this.revealValue) { // Example condition
            this.revealElement.classList.remove('hidden')
        } else {
            this.revealElement.classList.add('hidden');
        }
    }
}