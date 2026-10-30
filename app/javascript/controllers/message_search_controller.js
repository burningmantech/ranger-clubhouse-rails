import {Controller} from "@hotwired/stimulus"

// The mailbox search form (common/messages/_search_field): the text searched
// for, and people as chips (?with[]=), each keeping the search to the
// conversations they are in. A suggestion taken from the autocomplete in it
// (MessagesConcern#suggest) runs the search at once: a person becomes a chip in
// place of the text typed to find them, and a team, or the search itself, is
// searched for as the text it put in the field. Removing a chip runs it again.
// Past the max a new chip replaces the oldest, as the compose form's do.
export default class extends Controller {
    static targets = ["chip", "input", "list", "template"]
    static values = {max: Number}

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

    valueOf(chip) {
        return chip.querySelector("input").value
    }
}
