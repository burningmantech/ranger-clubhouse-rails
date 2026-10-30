import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="scroll-to-element"
//
// Brings one element into view when the page renders, named by its id in
// data-scroll-to-element-id-value.
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
// (components/review-pane.css). While it does, only it moves, putting the
// element at its top less the element's scroll-margin-top. scrollIntoView
// would move every container around the element too -- the page under the
// pane, carrying the list beside it away from the row the reader chose -- and
// its option to stop at the nearest (container: "nearest") is Chrome's alone.
export default class extends Controller {
    static values = {id: String, container: String}

    connect() {
        this.reveal = this.reveal.bind(this)
        document.addEventListener("turbo:morph", this.reveal)
        this.reveal()
    }

    disconnect() {
        document.removeEventListener("turbo:morph", this.reveal)
    }

    reveal() {
        const target = document.getElementById(this.idValue)
        if (!target) {
            return
        }

        const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
        const container = this.containerValue && target.closest(this.containerValue)
        if (container && ["auto", "scroll"].includes(getComputedStyle(container).overflowY)) {
            const top = target.getBoundingClientRect().top - container.getBoundingClientRect().top - container.clientTop
            container.scrollBy({top: top - parseFloat(getComputedStyle(target).scrollMarginTop), behavior})
        } else {
            target.scrollIntoView({behavior, block: "start"})
        }
    }
}
