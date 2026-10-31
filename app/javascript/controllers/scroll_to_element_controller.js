import {Controller} from "@hotwired/stimulus"
import {reveal} from "controllers/scrolling"

// Connects to data-controller="scroll-to-element"
//
// Brings one element into view when the page renders, named by its id in
// data-scroll-to-element-id-value or by a selector in
// data-scroll-to-element-selector-value, unless it is in view already, where
// a scroll would only hide what sits above it. A selector follows an element
// that is not fixed at render: the mailbox's ringed card, which the stepper
// moves (common/messages/_thread).
//
// A page reached after a form submission cannot use "#id" for this: Turbo
// takes the page to visit from the fetch response's URL, and a URL's fragment
// is not part of it, so the reader lands at the top of the page instead of
// beside the thing they just changed.
//
// It also listens for turbo:morph. Doing the same thing twice -- moving one
// row down, and down again -- redirects to the URL the reader is already on,
// which Turbo treats as a refresh and morphs. Morphing leaves this element
// alone, so connect() never runs again, and without the listener the second
// move would leave the reader looking at whatever took the row's place.
//
// data-scroll-to-element-container-value names, as a selector, an ancestor
// that scrolls itself in some layouts: the mailbox's pane, from lg up
// (components/review-pane.css). How that one moves, and the page around it,
// is controllers/scrolling's reveal.
export default class extends Controller {
    static values = {id: String, selector: String, container: String}

    connect() {
        this.reveal = this.reveal.bind(this)
        document.addEventListener("turbo:morph", this.reveal)
        this.reveal()
    }

    disconnect() {
        document.removeEventListener("turbo:morph", this.reveal)
    }

    reveal() {
        const target = this.hasIdValue ? document.getElementById(this.idValue) : document.querySelector(this.selectorValue)
        if (target) {
            reveal(target, this.containerValue)
        }
    }
}
