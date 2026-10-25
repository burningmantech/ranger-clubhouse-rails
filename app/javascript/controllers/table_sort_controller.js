// Sorts the rows already on the page when a column heading's button is
// pressed. The Salesforce Query results come from a POST the server cannot
// re-derive, and asking Salesforce again would cost two API calls a click.
// (The name is not "sortable": sortable_controller.js is drag-to-reorder.)
//
// Markup: data-controller="table-sort" on an element that outlives the table
// inside it. Each sortable th carries data-sort-type ("number" or "text") and
// holds a button with data-action="table-sort#sort" and an icon. A cell may
// carry data-sort-value to sort by something other than its text; "" sorts
// last in both directions. The optional status target is told what the rows
// are sorted by, and the sentence is read out through #live-region, because
// screen readers do not announce a change of aria-sort.
import { Controller } from "@hotwired/stimulus"

// Whole class names, so Tailwind sees each one.
const ICONS = {
    none: "fa-solid fa-sort text-stone-subtle",
    ascending: "fa-solid fa-caret-up",
    descending: "fa-solid fa-caret-down"
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" })

export default class extends Controller {
    static targets = [ "status" ]

    sort({ currentTarget }) {
        const th = currentTarget.closest("th")
        const table = th.closest("table")
        const direction = th.getAttribute("aria-sort") === "ascending" ? "descending" : "ascending"
        const sign = direction === "ascending" ? 1 : -1
        const numeric = th.dataset.sortType === "number"

        // Keys are read once per press. The first press pins the server's
        // order on each row, which breaks ties from then on.
        const rows = [ ...table.tBodies[0].rows ].map((row, index) => {
            row.dataset.position ??= index
            const cell = row.cells[th.cellIndex]
            const raw = cell.dataset.sortValue ?? cell.textContent.trim()
            return { row, raw, value: numeric ? Number(raw) : raw, position: Number(row.dataset.position) }
        })

        rows.sort((a, b) => {
            if (a.raw === "" || b.raw === "") return (a.raw === "") - (b.raw === "") || a.position - b.position
            const order = numeric ? a.value - b.value : collator.compare(a.value, b.value)
            return sign * order || a.position - b.position
        })
        // Moving the rows keeps them -- and the stripes, which come from :nth-child.
        table.tBodies[0].append(...rows.map(({ row }) => row))

        for (const heading of table.tHead.rows[0].cells) {
            heading.removeAttribute("aria-sort")
            const icon = heading.querySelector("button i")
            if (icon) icon.className = ICONS.none
        }
        th.setAttribute("aria-sort", direction)
        th.querySelector("button i").className = ICONS[direction]

        const sentence = `Sorted by ${currentTarget.textContent.trim()}, ${direction}.`
        if (this.hasStatusTarget) this.statusTarget.textContent = sentence
        const line = document.createElement("div")
        line.textContent = sentence
        document.getElementById("live-region")?.replaceChildren(line)
    }
}
