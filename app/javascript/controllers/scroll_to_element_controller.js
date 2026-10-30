import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="scroll-to-element"
//
// Brings one element into view when the page renders, named by its id in
// data-scroll-to-element-id-value, unless it is already wholly on screen,
// where a scroll would only hide what sits above it.
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
// (components/review-pane.css). While it does, it moves first, putting the
// element at its top less the element's scroll-margin-top; scrollIntoView
// would move every container around the element too -- the page under the
// pane, carrying the list beside it away from the row the reader chose -- and
// its option to stop at the nearest (container: "nearest") is Chrome's alone.
// The page then moves only if the element is still off screen, as little as
// it can: when the container itself is -- stacked under the list in the HQ
// window, or starting too low for its foot to show.
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
        if (!target || this.onScreen(target)) {
            return
        }

        const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
        const container = this.containerValue && target.closest(this.containerValue)
        if (container && ["auto", "scroll"].includes(getComputedStyle(container).overflowY)) {
            // getBoundingClientRect measures what is drawn, after any CSS zoom
            // on the way up (the HQ shell's, components/hq-window.css), but
            // scrollTop counts the container's own pixels.
            const box = container.getBoundingClientRect()
            const zoom = container.offsetHeight ? box.height / container.offsetHeight : 1
            container.scrollTop += (target.getBoundingClientRect().top - box.top) / zoom - container.clientTop -
                parseFloat(getComputedStyle(target).scrollMarginTop)
            if (!this.onScreen(target)) {
                target.scrollIntoView({behavior, block: "nearest"})
            }
        } else {
            target.scrollIntoView({behavior, block: "start"})
        }
    }

    // Wholly on screen: the middle of its top and of its bottom edge hit-test to
    // it, so it is neither clipped by a scroller, past the window's edge, nor
    // under something drawn over it.
    onScreen(element) {
        const {left, right, top, bottom} = element.getBoundingClientRect()
        const x = (left + right) / 2
        return [top + 2, bottom - 2].every((y) => element.contains(document.elementFromPoint(x, y)))
    }
}
