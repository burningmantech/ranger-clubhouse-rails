import { Controller } from "@hotwired/stimulus";

// The asset form's group select offers the groups of the chosen asset type,
// from { type: { "Active": [[title, id]] } }. The server draws it for the type
// the page was rendered with; this redraws it for the type the select shows.
export default class extends Controller {
    static targets = ["typeSelect", "groupField", "groupSelect"];
    static values = { groups: Object };

    // The type select can show another type than the server drew for: a
    // restored page (Back, a reload that keeps form values) or an asset with no
    // type, whose select falls to its first option. The choice is kept when the
    // type still has it.
    connect() {
        this.redraw(this.groupSelectTarget.value);
    }

    // A group belongs to one type, so the choice does not survive the change.
    handleTypeChange() {
        this.redraw("");
    }

    redraw(selected) {
        const groups = this.groupsValue[this.typeSelectTarget.value] || {};
        const select = this.groupSelectTarget;

        select.replaceChildren(new Option("", ""));
        for (const [label, options] of Object.entries(groups)) {
            const optgroup = document.createElement("optgroup");
            optgroup.label = label;
            for (const [title, id] of options) {
                optgroup.append(new Option(title, id, false, String(id) === selected));
            }
            select.append(optgroup);
        }

        this.groupFieldTarget.hidden = select.options.length === 1;
    }
}
