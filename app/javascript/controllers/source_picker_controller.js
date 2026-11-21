import {Controller} from "@hotwired/stimulus"
import {setTabStop, stepToolbar} from "controllers/toolbar"

// Connects to data-controller="source-picker"
//
// Chooses what fills a column of a TRS format from a dialog of buttons, in
// place of typing its key. The grid's form posts a hidden field per column;
// this writes that field, and the name on the button beside it.
//
// Markup, inside data-controller="source-picker":
//   data-source-picker-target="field"  around one column's hidden field and its
//                                      button (data-action="source-picker#open")
//   data-source-picker-target="label"  inside that button, holding the name
//   data-source-picker-target="template"  a <template> holding the dialog
//   ...and inside the dialog:
//   data-source-picker-target="title", "header"
//   data-source-picker-target="note"    the line that says which column holds
//                                       a greyed choice, once one is pressed
//   data-source-picker-target="choice"  a button with data-source (the key) and
//                                       data-label (its name), data-action=
//                                       "source-picker#choose"
//   data-action="keydown->source-picker#step" on each role="toolbar" of choices
//
// The dialog is a copy of the template each time. One built by the modal
// helper is taken out of the page when it closes, and its own controller loads
// lazily: it may arrive after the dialog was answered, and would then show it
// again. So this shows the copy itself, closes it on any button that is not a
// choice, and removes it on close, leaving that controller nothing to find.
export default class extends Controller {
    static targets = ["template", "title", "header", "note", "choice", "field", "label"]

    disconnect() {
        this.dialog?.close()
    }

    open(event) {
        const opener = event.currentTarget
        const fields = this.fieldTargets
        const field = fields.find((candidate) => candidate.contains(opener))
        const value = (other) => other.querySelector("input[type=hidden]").value
        // Which column holds each source already, this one left out.
        const taken = new Map(fields.filter((other) => other !== field && value(other))
                                    .map((other) => [value(other), fields.indexOf(other) + 1]))

        const dialog = this.templateTarget.content.firstElementChild.cloneNode(true)
        this.element.append(dialog)
        this.dialog = dialog
        this.field = field
        this.taken = taken

        this.titleTarget.textContent = "Source for Column " + (fields.indexOf(field) + 1)
        // What the column is called in the file, from the row's own text field.
        this.headerTarget.textContent = field.closest("tr")?.querySelector("input[type=text]")?.value ?? ""

        this.choiceTargets.forEach((choice) => {
            const key = choice.dataset.source
            const current = key === value(field)
            const column = taken.get(key)
            const inUse = column !== undefined

            // Greyed, yet it still takes the pointer and the focus: its tooltip
            // and a press both say which column holds it (choose). daisyUI greys
            // an aria-disabled button and takes the pointer off it, so the
            // pointer is given back.
            choice.setAttribute("aria-disabled", inUse)
            choice.classList.toggle("pointer-events-auto", inUse)
            choice.title = inUse ? "Fills column " + column : ""
            choice.setAttribute("aria-pressed", current)
            choice.classList.toggle("btn-primary", current)
            choice.classList.toggle("btn-secondary", !current)
            choice.classList.toggle("btn-outline", !current)
            // Where the dialog puts the focus when it opens.
            choice.toggleAttribute("autofocus", current)
        })
        // Each group's tab stop: the current choice, or the first that is free.
        dialog.querySelectorAll('[role="toolbar"]').forEach((group) => {
            setTabStop(group, group.querySelector('[aria-pressed="true"]') ??
                              group.querySelector('button:not([aria-disabled="true"])'))
        })

        // The second press of a double-click on the column's button lands on
        // whatever the dialog has put under the pointer: a choice, Cancel, the
        // backdrop. It is dropped before any of them hears it.
        dialog.addEventListener("click", (click) => {
            if (click.detail > 1) {
                click.preventDefault()
                click.stopPropagation()
            }
        }, {capture: true})
        dialog.addEventListener("click", (click) => {
            const button = click.target.closest("button")
            if (button && !this.choiceTargets.includes(button)) dialog.close()
        })
        // A dialog hands the focus back to whatever had it, but a button pressed
        // with a mouse never took it in Safari or in Firefox on a Mac, and the
        // focus would be left on the page. So it is put on the column's button.
        dialog.addEventListener("close", () => {
            dialog.remove()
            this.dialog = this.field = this.taken = null
            opener.focus()
        }, {once: true})
        dialog.showModal()
    }

    choose(event) {
        const choice = event.currentTarget
        if (!this.field) return

        // A greyed choice changes nothing. It says where it is in use.
        const column = this.taken.get(choice.dataset.source)
        if (column !== undefined) {
            this.noteTarget.textContent = choice.dataset.label + " already fills column " + column +
                ". Change that column first to free it."
            this.noteTarget.scrollIntoView({block: "nearest"})
            return
        }

        // The choice the column already had is no change, and must not read as one.
        const input = this.field.querySelector("input[type=hidden]")
        if (input.value !== choice.dataset.source) {
            const label = this.labelTargets.find((candidate) => this.field.contains(candidate))
            input.value = choice.dataset.source
            label.textContent = choice.dataset.label
            label.classList.toggle("text-stone-muted", input.value === "")
            // An input event, so a form that watches for unsaved changes sees one.
            input.dispatchEvent(new Event("input", {bubbles: true}))
        }
        this.dialog.close()
    }

    step(event) {
        stepToolbar(event)
    }
}
