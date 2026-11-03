import {Controller} from "@hotwired/stimulus";

export default class extends Controller {
    static values = {
        id: String,
        reveal: String
    }

    connect() {
        this._inputChanged = this.inputChanged.bind(this);
        this.element.addEventListener('change', this._inputChanged);
        this.revealElement = document.getElementById(this.idValue);
    }

    disconnect() {
        this.element.removeEventListener('change', this._inputChanged);
    }

    inputChanged() {
        this.revealElement?.classList.toggle("hidden", this.element.value !== this.revealValue);
    }
}