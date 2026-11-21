import {Controller} from "@hotwired/stimulus"
import {Turbo} from "@hotwired/turbo-rails"
import {setTabStop, stepToolbar} from "controllers/toolbar"

// Connects to data-controller="form-rows"
//
// The rows of a form edited in the page: arrows that move a row up or down, a
// button that inserts a blank row under it and one that deletes it. Nothing is
// sent to the server. The form posts its rows in the order they stand, so the
// change is saved when the form is, and is lost if it is not.
//
// (The arrows of a list with nothing unsaved beside it are the other kind, a
// PATCH and a reload per click: common/_move_buttons.)
//
// Markup, inside data-controller="form-rows":
//   data-form-rows-target="row"       each row
//   data-form-rows-target="template"  a <template> holding one blank row
//   data-action="form-rows#up", "#down", "#insert", "#remove" on a row's buttons
//   data-action="keydown->form-rows#step" on the role="toolbar" around them
//   data-form-rows-noun-value         what a row is called when asking before a
//                                     delete ("column"; "row" when not given)
//
// The row itself moves, with everything in it: what its fields hold, a hidden
// field and the label drawn beside it, the red mark of a refused save. A row's
// place is in what it prints, so after any change every row is numbered again.
// An element names what to rewrite, with {n} for the row's number and {i} for
// its index:
//   data-form-rows-number            its text becomes the number
//   data-form-rows-label="... {n}"   its aria-label
//   data-form-rows-id="...-{i}-..."  its id, which keeps the ids unique and as
//                                    the server would draw them, so a morph of
//                                    the page lines the rows up
// The first row's up arrow and the last row's down arrow are hidden, not
// removed: each keeps its place, so the other buttons do not shift.
//
// A row's toolbar is one tab stop (controllers/toolbar): Tab lands on its first
// button that shows, and the left and right arrow keys reach the others.
const BUTTONS = {
    up: '[data-action~="form-rows#up"]',
    down: '[data-action~="form-rows#down"]',
    remove: '[data-action~="form-rows#remove"]',
}

// What a row holds, a hidden field included, and the fields a reader can see.
const FIELDS = "input, select, textarea"
const VISIBLE_FIELDS = "input:not([type=hidden]), select, textarea"

const values = (row, selector) => [...row.querySelectorAll(selector)].map((field) => field.value.trim()).filter(Boolean)

export default class extends Controller {
    static targets = ["row", "template"]
    static values = {noun: {type: String, default: "row"}}

    up(event) {
        this.move(event, -1)
    }

    down(event) {
        this.move(event, 1)
    }

    // Moving the element takes the focus off the button that was pressed, so
    // it is put back: on the same arrow, to keep moving the same row with the
    // same key, or on the other one when the row has reached an end.
    move(event, step) {
        const rows = this.rowTargets
        const row = this.rowOf(event)
        const from = rows.indexOf(row)
        const to = from + step
        if (from < 0 || to < 0 || to >= rows.length) return

        if (step < 0) rows[to].before(row)
        else rows[to].after(row)
        this.renumber()
        this.changed()

        const [same, other] = step < 0 ? [BUTTONS.up, BUTTONS.down] : [BUTTONS.down, BUTTONS.up]
        const arrow = row.querySelector(same)
        const target = arrow && !arrow.classList.contains("invisible") ? arrow : row.querySelector(other)
        target?.focus()
    }

    insert(event) {
        const added = this.blankRow()
        this.rowOf(event).after(added)
        this.renumber()
        this.changed()
        added.querySelector(VISIBLE_FIELDS)?.focus()
    }

    // A row that holds something is asked about first: one press would
    // otherwise take a filled row with nothing to show which one went. The
    // last row left is swapped for a blank one rather than removed, since
    // there has to be a row to insert the next one under.
    async remove(event) {
        const row = this.rowOf(event)
        if (values(row, FIELDS).length && !(await this.confirmRemoval(row))) return

        const rows = this.rowTargets
        const index = rows.indexOf(row)
        if (index < 0) return

        if (rows.length === 1) row.replaceWith(this.blankRow())
        else row.remove()
        this.renumber()
        this.changed()

        // To the row that took its place, so the next delete is one press away.
        const left = this.rowTargets
        left[Math.min(index, left.length - 1)]?.querySelector(BUTTONS.remove)?.focus()
    }

    // Named by its number and the first thing a reader can see in it.
    confirmRemoval(row) {
        const name = values(row, VISIBLE_FIELDS)[0]
        const thing = this.nounValue + " " + (this.rowTargets.indexOf(row) + 1) + (name ? ", “" + name + "”" : "")
        const action = "Delete " + this.nounValue.charAt(0).toUpperCase() + this.nounValue.slice(1)

        return Turbo.config.forms.confirm({
            title: action,
            message: "Delete " + thing + "? It is gone for good once the form is saved.",
            confirmLabel: action,
            variant: "error",
        }, this.element)
    }

    step(event) {
        stepToolbar(event)
    }

    renumber() {
        const rows = this.rowTargets
        rows.forEach((row, index) => {
            const fill = (text) => text.replace("{n}", index + 1).replace("{i}", index)

            row.querySelectorAll("[data-form-rows-number]").forEach((cell) => { cell.textContent = index + 1 })
            row.querySelectorAll("[data-form-rows-label]").forEach((element) => {
                element.setAttribute("aria-label", fill(element.dataset.formRowsLabel))
            })
            row.querySelectorAll("[data-form-rows-id]").forEach((element) => {
                element.id = fill(element.dataset.formRowsId)
            })
            row.querySelector(BUTTONS.up)?.classList.toggle("invisible", index === 0)
            row.querySelector(BUTTONS.down)?.classList.toggle("invisible", index === rows.length - 1)

            // The tab stop is the first button that shows, which the two lines
            // above may just have changed.
            row.querySelectorAll('[role="toolbar"]').forEach((toolbar) => setTabStop(toolbar))
        })
    }

    blankRow() {
        return this.templateTarget.content.firstElementChild.cloneNode(true)
    }

    rowOf(event) {
        return this.rowTargets.find((row) => row.contains(event.currentTarget))
    }

    // An input event, so a form that watches for unsaved changes sees one.
    changed() {
        this.element.dispatchEvent(new Event("input", {bubbles: true}))
    }
}
