import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="stale-results"
//
// The results panel reports the values that were verified, not whatever is in
// the form now, so the first edit after a verify withdraws the commit button
// and explains why.
export default class extends Controller {
    static targets = ["commit", "stale"]

    markStale() {
        if (!this.hasCommitTarget) return;

        this.commitTarget.classList.add("hidden");
        this.staleTarget.classList.remove("hidden");
    }
}
