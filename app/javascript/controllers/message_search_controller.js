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
// The field sits outside the list's frame and changes before the search it
// runs is sent, so until that search settles it shows one the list does not
// (searching). One that fails -- the connection down; an error's answer
// replaces the page (application.js) -- sets the field back to the address,
// which the list on screen still answers to. So does a page Turbo kept for
// Back, taken as a search's answer arrived, with the field already showing it.
export default class extends CallsignChips {
    static values = {searching: Boolean}

    connect() {
        if (this.searchingValue) this.showAddress()
    }

    disconnect() {}

    chipTargetConnected() {
        this.suggestWithout()
    }

    chipTargetDisconnected() {
        this.suggestWithout()
    }

    take({detail: {value, meta}}) {
        if (meta?.kind === "person") this.addChip(value)
        this.element.requestSubmit()
    }

    remove(event) {
        super.remove(event)
        this.element.requestSubmit()
    }

    // turbo:submit-start
    searching() {
        this.searchingValue = true
    }

    // turbo:submit-end. A search stopped for the next one (no success either
    // way) leaves the field to that one.
    settle({detail: {success}}) {
        if (success === undefined) return
        if (success === false) this.showAddress()
        this.searchingValue = false
    }

    // The field as the address has it: its text, and its people as chips.
    showAddress() {
        const params = new URLSearchParams(window.location.search)
        this.chipTargets.forEach((chip) => chip.remove())
        params.getAll("with[]").forEach((callsign) => this.addChip(callsign))
        this.inputTarget.value = params.get("q") ?? ""
        this.searchingValue = false
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
