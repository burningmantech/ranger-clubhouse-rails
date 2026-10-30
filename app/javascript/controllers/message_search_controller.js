import {Controller} from "@hotwired/stimulus"

// The mailbox search form (common/messages/_search_field): the text searched
// for, and people as chips (?with[]=), each keeping the search to the
// conversations they are in. A suggestion taken from the autocomplete in it
// (MessagesConcern#suggest) runs the search at once: a person becomes a chip in
// place of the text typed to find them, and a team, or the search itself, is
// searched for as the text it put in the field. Removing a chip runs it again.
// Past the max a new chip replaces the oldest, as the compose form's do. The
// suggestions leave out whoever is a chip already, so the address they are
// fetched from names the chips, as the search's own does.
export default class extends Controller {
    static targets = ["chip", "input", "list", "template"]
    static values = {max: Number}

    chipTargetConnected() {
        this.suggestWithout()
    }

    chipTargetDisconnected() {
        this.suggestWithout()
    }

    take({detail: {value, selected}}) {
        if (JSON.parse(selected.dataset.autocompleteMeta || "{}").kind === "person") {
            this.inputTarget.value = ""
            this.add(value)
        }
        this.element.requestSubmit()
    }

    remove(event) {
        event.currentTarget.closest("[data-message-search-target='chip']").remove()
        this.inputTarget.focus()
        this.element.requestSubmit()
    }

    // A press on the box around the text, not on a chip's button or the
    // suggestions, puts the caret in the text, as one on the plain field the box
    // stands in for did. The focus never leaves it, so an open list stays.
    focus(event) {
        if (event.target.closest("button, input, [role=listbox]")) return

        event.preventDefault()
        this.inputTarget.focus()
    }

    add(callsign) {
        if (this.chipTargets.some(chip => this.valueOf(chip).toLowerCase() === callsign.toLowerCase())) return

        const chip = this.templateTarget.content.firstElementChild.cloneNode(true)
        chip.querySelector("span").textContent = callsign
        chip.querySelector("input").value = callsign
        chip.querySelector("button").setAttribute("aria-label", `Remove ${callsign}`)
        const over = this.chipTargets.length + 1 - this.maxValue
        if (over > 0) this.chipTargets.slice(0, over).forEach(old => old.remove())
        this.listTarget.append(chip)
    }

    // The autocomplete reads its address at each search.
    suggestWithout() {
        if (!this.hasInputTarget) return

        const autocomplete = this.inputTarget.closest("[data-controller~='autocomplete']")
        const url = new URL(autocomplete.dataset.autocompleteUrlValue, window.location.href)
        url.searchParams.delete("with[]")
        this.chipTargets.forEach(chip => url.searchParams.append("with[]", this.valueOf(chip)))
        autocomplete.dataset.autocompleteUrlValue = url.pathname + url.search
    }

    valueOf(chip) {
        return chip.querySelector("input").value
    }
}
