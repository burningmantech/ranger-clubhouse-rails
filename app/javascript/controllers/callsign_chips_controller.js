import {Controller} from "@hotwired/stimulus"

// The callsign chips field (AppFormBuilder#callsign_chips_field): a suggestion
// taken from the autocomplete inside it, or a callsign typed and Entered,
// becomes a chip carrying the value the form sends; its button removes it.
// The server checks every callsign on send, so a typed one is taken as typed.
// With a max (the HQ window's relay names one sender), a new chip past it
// replaces the oldest.
//
// Text never made a chip is never dropped unseen (review finding 5): the
// lookup input has no name, so the form's submit makes it a chip first, and the
// server takes or refuses it like any other. An Enter the autocomplete held for
// the search in flight makes the text a chip once that search lands, unless
// its sole suggestion was taken.
export default class extends Controller {
    static targets = ["chip", "input", "list", "template"]
    static values = {max: Number}

    connect() {
        this.form = this.element.closest("form")
        this.form?.addEventListener("submit", this.commitTyped)
    }

    disconnect() {
        this.form?.removeEventListener("submit", this.commitTyped)
    }

    add(event) {
        this.addChip(event.detail.value)
    }

    // A Find Recipient choice is streamed in (MessagesConcern#select_callsign),
    // past addChip, so one already chipped goes here.
    chipTargetConnected(chip) {
        const callsign = this.valueOf(chip).toLowerCase()
        if (this.chipTargets.some(other => other !== chip && this.valueOf(other).toLowerCase() === callsign)) chip.remove()
    }

    // On the field, so the autocomplete's own Enter (taking a suggestion) has
    // run first. Enter never sends the form from here: it makes a chip. One the
    // autocomplete kept with the text still there is waiting for its search
    // (loaded); any other key calls that off.
    keydown(event) {
        if (event.target !== this.inputTarget) return
        if (event.key !== "Enter") {
            this.enterHeld = false
            return
        }
        if (event.defaultPrevented) {
            this.enterHeld = this.inputTarget.value.trim() !== ""
            return
        }

        event.preventDefault()
        this.addChip(this.inputTarget.value)
    }

    // The autocomplete's search has landed, after taking its sole suggestion
    // for a held Enter if it had one (that emptied the text).
    loaded() {
        if (!this.enterHeld) return

        this.enterHeld = false
        this.addChip(this.inputTarget.value)
    }

    commitTyped = () => {
        this.enterHeld = false
        this.addChip(this.inputTarget.value)
    }

    remove(event) {
        event.currentTarget.closest("[data-callsign-chips-target='chip']").remove()
        this.inputTarget.focus()
    }

    addChip(value) {
        const callsign = value.trim()
        this.inputTarget.value = ""
        if (!callsign || this.chipTargets.some(chip => this.valueOf(chip).toLowerCase() === callsign.toLowerCase())) return

        const chip = this.templateTarget.content.firstElementChild.cloneNode(true)
        chip.querySelector("span").textContent = callsign
        chip.querySelector("input").value = callsign
        chip.querySelector("button").setAttribute("aria-label", `Remove ${callsign}`)
        if (this.hasMaxValue) this.chipTargets.slice(0, this.chipTargets.length - this.maxValue + 1).forEach(old => old.remove())
        this.listTarget.append(chip)
    }

    valueOf(chip) {
        return chip.querySelector("input").value
    }
}
