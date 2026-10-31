import {Controller} from "@hotwired/stimulus"
import {reveal} from "controllers/scrolling"

// Connects to data-controller="search-matches" on a thread opened from a
// search (common/messages/_messages_panel).
//
// The stepper over the messages: "Match 2 of 3", counting the messages that
// hold a mark of the search (MessagesHelper#message_body_marks) and stepping
// through them one message at a time, round past either end. The current one
// is the card the thread landed on (data-landing, _thread): a step moves that
// attribute, which rings the card (_message_card), and brings the card into
// view as the landing did, but at once (controllers/scrolling's reveal). Both
// last as long as the thread is open: review_pane_controller keeps data-landing
// and the marked bodies through the cards' read-state morphs, and a reply that
// lands live is drawn unmarked. A morphing refresh of the page draws the count
// anew at the match the thread opened on, so it is read again from the ring.
//
// The page draws the stepper, at the match it lands on (ui_match_stepper),
// only on a thread holding a mark: a hit on the subject or a callsign alone
// opens one with none.
export default class extends Controller {
    static targets = ["count"]

    connect() {
        this.show = this.show.bind(this)
        document.addEventListener("turbo:morph", this.show)
    }

    disconnect() {
        document.removeEventListener("turbo:morph", this.show)
    }

    next() {
        this.step(1)
    }

    previous() {
        this.step(-1)
    }

    step(by) {
        const cards = this.cards
        const current = cards.findIndex((card) => card.hasAttribute("data-landing"))
        const index = (current + by + cards.length) % cards.length
        cards.forEach((card, at) => card.toggleAttribute("data-landing", at === index))
        this.show()
        reveal(cards[index], ".review-pane", {behavior: "auto"})
    }

    // The count, at the ringed card.
    show() {
        const cards = this.cards
        const index = cards.findIndex((card) => card.hasAttribute("data-landing"))
        this.countTarget.textContent = `Match ${index + 1} of ${cards.length}`
    }

    // The cards holding a mark, top to bottom.
    get cards() {
        const marks = this.element.querySelectorAll("#messages-thread [data-message-body] mark.search-hit")
        return [...new Set([...marks].map((mark) => mark.closest("article")))]
    }
}
