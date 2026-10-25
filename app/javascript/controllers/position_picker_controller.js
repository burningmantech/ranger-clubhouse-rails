import CheckboxSelectAll from "controllers/checkbox_select_all_controller"

// Quick ways through a long list of position checkboxes: every one, none of
// them, or every position sharing one paycode. Each checkbox carries its
// paycode in a data attribute, and the count target keeps a running total so
// the reader can see what they picked without counting boxes.
export default class extends CheckboxSelectAll {
  selectAll(event) {
    event.preventDefault()
    this.setAll(() => true)
  }

  selectNone(event) {
    event.preventDefault()
    this.setAll(() => false)
  }

  // Replaces the selection rather than adding to it, so two clicks in a row
  // answer "just this paycode" both times.
  //
  // The attribute is read straight off the button rather than through
  // event.params: Stimulus runs params through JSON.parse, which rewrites a
  // paycode that looks like a number -- "660" becomes 660, "1.50" becomes 1.5 --
  // and the rewritten value then matches no checkbox at all. A paycode is free
  // text, so it is compared as the text it is.
  selectPaycode(event) {
    event.preventDefault()
    const wanted = event.currentTarget.dataset.positionPickerPaycodeParam
    this.setAll((box) => box.dataset.paycode === wanted)
  }

  // Must match BulkSelectHelper#position_picker_count_label.
  countLabel(selected, total) {
    return `${selected} of ${total} selected`
  }
}
