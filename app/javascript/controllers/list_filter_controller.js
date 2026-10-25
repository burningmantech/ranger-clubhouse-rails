import { Controller } from "@hotwired/stimulus";

/**
 * Narrows a list to the rows matching what was typed.
 *
 * Purely a view over the rows already on the page -- it hides and shows, it
 * never fetches. Each row carries the text to match, already lower-cased, in
 * the data attribute named by the key value: data-callsign on a roll call
 * roster, data-name on the languages list.
 *
 * Rows can be replaced under it by turbo streams (the roster is, on every
 * tap), so a row is filtered again the moment it arrives: that is what keeps
 * a just-tapped row from reappearing in a filtered list it does not belong to.
 *
 * Optional targets: group (a heading hidden when every row beneath it is),
 * empty (shown when a term matches nothing), summary (a whole-page count,
 * hidden while a term is narrowing the page).
 */
export default class extends Controller {
    static targets = ["input", "row", "group", "empty", "summary"];
    static values = { key: { type: String, default: "name" } };

    // Coming back to a page reuses the copy it was left in, where rows the
    // reader had typed past are still hidden -- but the box they typed into
    // comes back empty. Running the filter again lines the two up.
    connect() {
        this.apply();
    }

    // A row arriving by turbo stream is filtered on its own; the whole list
    // is not walked again for it.
    rowTargetConnected(row) {
        const term = this.term;
        this.filterRow(row, term);
        if (term) this.showEmpty(term);
    }

    rowTargetDisconnected() {
        const term = this.term;
        if (term) this.showEmpty(term);
    }

    apply() {
        const term = this.term;
        const rows = this.rowTargets;
        rows.forEach((row) => this.filterRow(row, term));

        // A heading with every row beneath it hidden reads as a section that
        // lost its contents, so the heading goes with them.
        this.groupTargets.forEach((group) => {
            group.hidden = rows.every((row) => row.hidden || !group.contains(row));
        });

        this.showEmpty(term);

        // The summary counts the whole page, so it stops being true the moment
        // rows are hidden. What is left on screen says it better.
        if (this.hasSummaryTarget) {
            this.summaryTarget.hidden = term !== "";
        }
    }

    filterRow(row, term) {
        row.hidden = term !== "" && !(row.getAttribute(`data-${this.keyValue}`) || "").includes(term);
    }

    // Shown only when a term matches nothing: a list that is empty before
    // anything is typed has an empty state of its own.
    showEmpty(term) {
        if (!this.hasEmptyTarget) return;

        this.emptyTarget.hidden = term === "" || this.rowTargets.some((row) => !row.hidden);
    }

    get term() {
        return this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : "";
    }
}
