import { Controller } from "@hotwired/stimulus"

// Lexxy is roughly 640KB of JavaScript, and it is the editor for a handful of
// forms — announcements, surveys, documents, training resources — out of the
// whole application. Imported from application.js it would be parsed on every
// page load, including the ones a Ranger opens on a phone in the dust.
//
// Importing it here instead defers that download to the moment a rich text
// field actually connects: Stimulus lazy-loads this controller when the first
// element carrying data-controller="lexxy" appears, and <lexxy-editor> is a
// custom element, so it upgrades itself as soon as the definition lands.
import { Extension, Lexical, configure } from "lexxy"

// Lexxy shows a merged table cell (colspan, rowspan) when a table is pasted or
// loaded with one, then leaves both attributes out of what it submits, so the
// cells beside it slide into the wrong columns once saved. Declaring them as
// allowed keeps them in the value. ApplicationHelper#rich_text allows them too.
class MergedCells extends Extension {
  get allowedElements() {
    return [
      { tag: "td", attributes: ["colspan", "rowspan"] },
      { tag: "th", attributes: ["colspan", "rowspan"] }
    ]
  }
}

// Google Docs writes every run of text as a <span> whose style carries its
// colour, its weight, its slant and its underline. Lexxy takes any span with a
// colour for a highlight and reads nothing else from it, so pasted text came out
// with no bold and no italic. Each run's emphasis is rewritten as the <strong>,
// <em>, <u> and <s> elements Lexxy does read, and the result goes in the way
// Lexxy puts pasted HTML in itself.
//
// Low priority is after Lexxy's own paste handler, which takes a paste into a
// code block, a bare address and plain text, and before Lexical's default, which
// is what lost the emphasis.
class PastedEmphasis extends Extension {
  get lexicalExtension() {
    return this.defineExtension({
      name: "clubhouse/pasted-emphasis",
      register: (editor) => editor.registerCommand(
        Lexical.PASTE_COMMAND, this.handlePaste, Lexical.COMMAND_PRIORITY_LOW
      )
    })
  }

  handlePaste = (event) => {
    const clipboard = event.clipboardData
    // Copied from an editor like this one: Lexical carries its own format.
    if (!clipboard || clipboard.types.includes("application/x-lexical-editor")) return false

    const pasted = new DOMParser().parseFromString(clipboard.getData("text/html"), "text/html")
    if (!markEmphasis(pasted)) return false

    event.preventDefault()
    this.editorElement.contents.insertDOM(pasted, { tag: Lexical.PASTE_TAG })
    return true
  }
}

// True when any run was rewritten. A link's underline is the link's own, so it
// is not turned into underlined text.
function markEmphasis(pasted) {
  let marked = false

  for (const span of pasted.querySelectorAll("span[style]")) {
    const { fontWeight, fontStyle, textDecorationLine } = span.style
    const tags = [
      (fontWeight === "bold" || Number(fontWeight) >= 600) && "strong",
      fontStyle === "italic" && "em",
      textDecorationLine.includes("underline") && !span.closest("a") && "u",
      textDecorationLine.includes("line-through") && "s"
    ].filter(Boolean)

    for (const tag of tags) {
      const emphasis = pasted.createElement(tag)
      emphasis.append(...span.childNodes)
      span.append(emphasis)
      marked = true
    }
  }

  return marked
}

// Lexxy defines its elements a tick after it is imported, so that this can come
// first.
configure({ global: { extensions: [MergedCells, PastedEmphasis] } })

// A click on a field's label puts the caret in the field. A custom element is
// not focusable, and Lexxy keeps focus on the editing area inside it, so the
// browser has nowhere to put it and the click does nothing. Every other field
// here answers its label; this makes the editor do the same.
document.addEventListener("click", (event) => {
  const label = event.target.closest?.("label[for]")
  const editor = label && document.getElementById(label.htmlFor)

  if (editor?.matches("lexxy-editor")) editor.focus()
})

export default class extends Controller {
  connect() {
    this.element.addEventListener("lexxy:initialize", this.handleInitialize)
    // In the capture phase, so that it runs before Lexxy's own listener empties
    // the editor.
    document.addEventListener("turbo:before-cache", this.handleBeforeCache, true)

    this.handleInitialize()
  }

  disconnect() {
    this.element.removeEventListener("lexxy:initialize", this.handleInitialize)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache, true)
  }

  // Lexxy builds its tools inside the editor, which is inside the form, so its
  // link box and its code language list are controls of that form. The browser
  // then validates the link box with everything else: an address typed without
  // "https://", or a relative link opened and closed again, stays in the hidden
  // box, and Save does nothing and says nothing. An empty form attribute takes
  // a control out of its form; the box still checks itself when it is used.
  handleInitialize = () => {
    for (const control of this.element.querySelectorAll("input, select")) {
      control.setAttribute("form", "")
    }
  }

  // Lexxy answers Turbo's snapshot of the page by taking its editing area out,
  // on the assumption that the page is about to be replaced. Two things follow.
  //
  // The snapshot is what the Back button returns to, and the editor in it
  // rebuilds from its value attribute, which still holds what the server sent.
  // Writing the typed text there first is what brings a draft back with the
  // rest of the form.
  //
  // And Turbo also takes a snapshot when the page is not replaced at all: the
  // address moving to a place on the same page, or a refresh that leaves the
  // editor as it stands. The toolbar is then left with nothing under it
  // (basecamp/lexxy#1200). Once Turbo has its copy, which it takes one tick
  // after this event, an editor still on the page is rebuilt the way Lexxy
  // rebuilds one after a morph: by its connected attribute changing. That
  // rebuild, the timer below, is what to delete once Lexxy fixes this itself.
  handleBeforeCache = () => {
    const editor = this.element
    if (typeof editor.value !== "string") return

    editor.setAttribute("value", editor.value)

    setTimeout(() => setTimeout(() => {
      if (editor.isConnected && !editor.editorContentElement) editor.removeAttribute("connected")
    }))
  }
}
