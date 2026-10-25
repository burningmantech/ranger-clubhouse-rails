import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.element.focus();
        //  Place cursor at the end of the input value
        const value = this.element.value;
        this.element.value = '';
        this.element.value = value;
    }
}