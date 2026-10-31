import {Controller} from "@hotwired/stimulus"
import {scrollParent} from "controllers/scrolling"

// Connects to data-controller="scroll-to-top"
//
// Scrolls the page to its top when the element renders. For pages that
// arrive as a form-submission render (the 422 results pattern): Turbo morphs
// those into the page (the layout's turbo_refreshes_with method: :morph), which
// keeps the element that scrolls it and its place -- right for a form
// re-rendered with errors, wrong for a results page, where the reader would
// land wherever the submit button was instead of at the summary.
//
// That element, not the window: body is h-dvh, and the layout scrolls
// div.drawer-content, or <main> on a page without a sidebar
// (controllers/scrolling). The window is what is left where nothing else does.
export default class extends Controller {
    connect() {
        const scroller = scrollParent(this.element) ?? window
        scroller.scrollTo(0, 0)
    }
}
