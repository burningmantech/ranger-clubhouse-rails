import {Controller} from "@hotwired/stimulus"

// On a <details> holding form fields: they are sent only while it is open, so a
// choice folded away out of sight is not sent either. A disabled field is left
// out of the form's data and keeps its value, so opening it again sends it
// again. The compose form's Cadre or Delegation select (review finding 6): a
// team chosen and folded away sent the message to every member of it.
export default class extends Controller {
    connect() {
        this.sync()
    }

    sync() {
        this.element.querySelectorAll("input, select, textarea").forEach(field => field.disabled = !this.element.open)
    }
}
