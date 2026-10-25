import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="scroll-to-top"
//
// Scrolls the window to the top when the element renders. For pages that
// arrive as a form-submission render (the 422 results pattern): Turbo keeps
// the submitting page's scroll position on those, which is right for a form
// re-rendered with errors but wrong for a results page — the reader lands
// wherever the submit button was instead of at the summary.
export default class extends Controller {
    connect() {
        window.scrollTo(0, 0)
    }
}
