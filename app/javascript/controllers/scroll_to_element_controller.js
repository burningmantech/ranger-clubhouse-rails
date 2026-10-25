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
export default class extends Controller {
    static values = {id: String}

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

        const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
        target.scrollIntoView({behavior: reduced ? "auto" : "smooth", block: "start"})
    }
}
