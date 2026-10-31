import CallsignChips from "controllers/callsign_chips_controller"

// The mailbox search form (common/messages/_search_field): the text searched
// for, and people as chips (?with[]=), each keeping the search to the
// conversations they are in. The chips are the compose form's
// (callsign_chips_controller), less its rule that typed text becomes a chip:
// here the text is the search. A suggestion taken from the autocomplete in it
// (MessagesConcern#suggest) runs the search at once: a person becomes a chip in
// place of the text typed to find them, and a team, or the search itself, is
// searched for as the text it put in the field. Removing a chip runs it again.
// Past the max a new chip replaces the oldest, as the compose form's do. The
// suggestions leave out whoever is a chip already, so the address they are
// fetched from names the chips, as the search's own does.
//
// The chips sit outside the list's frame and change before the search they run
// is sent: one that fails (an error, the connection down) puts back the chips
// the list on screen still answers to.
export default class extends CallsignChips {
    connect() {}

    disconnect() {}

    chipTargetConnected() {
        this.suggestWithout()
    }

    chipTargetDisconnected() {
        this.suggestWithout()
    }

    take({detail: {value, meta}}) {
        this.keepChips()
        if (meta?.kind === "person") this.addChip(value)
        this.element.requestSubmit()
    }

    remove(event) {
        this.keepChips()
        super.remove(event)
        this.element.requestSubmit()
    }

    // turbo:submit-end. A search stopped for the next one (no success either
    // way) leaves the chips kept for that one.
    settle({detail: {success}}) {
        if (success === undefined) return
        if (success === false && this.kept !== undefined) this.listTarget.innerHTML = this.kept
        this.kept = undefined
    }

    keepChips() {
        this.kept ??= this.listTarget.innerHTML
    }

    // A press on the box around the text, not on a chip's button or the
    // suggestions, puts the caret in the text, as one on the plain field the box
    // stands in for did. The focus never leaves it, so an open list stays.
    focus(event) {
        if (event.target.closest("button, input, [role=listbox]")) return

        event.preventDefault()
        this.inputTarget.focus()
    }

    // The autocomplete reads its address at each search.
    suggestWithout() {
        if (!this.hasInputTarget) return

        const autocomplete = this.inputTarget.closest("[data-controller~='autocomplete']")
        const url = new URL(autocomplete.dataset.autocompleteUrlValue, window.location.href)
        url.searchParams.delete("with[]")
        this.chipTargets.forEach(chip => url.searchParams.append("with[]", this.chipValue(chip)))
        autocomplete.dataset.autocompleteUrlValue = url.pathname + url.search
    }
}
