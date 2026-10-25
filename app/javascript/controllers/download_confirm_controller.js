import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Asks before starting a download, then lets the browser fetch the file.
//
// A plain data-turbo-confirm cannot do this job: Turbo turns any link carrying
// one into a form submission, and a form submission reads the response in
// JavaScript, so the file is fetched and thrown away instead of being saved.
// Setting location ourselves is an ordinary navigation, which the browser hands
// to its own download handling, leaving this page where it was.
export default class extends Controller {
  static values = { message: String }

  async confirm(event) {
    // A modified click means "open this somewhere else" — the browser handles
    // those itself, and taking them over would turn a new-tab click into a
    // navigation of the page the reader wanted to keep.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()

    if (await Turbo.config.forms.confirm(this.messageValue, this.element)) {
      window.location.href = this.element.href
    }
  }
}
