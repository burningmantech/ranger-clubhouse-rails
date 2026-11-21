// A group of buttons that takes one tab stop: Tab lands on one of them and the
// left and right arrow keys reach the rest (Home and End the two ends), so a
// page with many such groups (a grid row's buttons, a picker's choices) can be
// tabbed through without stopping on every button. Shared by the controllers
// that draw such groups; the markup is a role="toolbar" element with
// tabindex="0" on one button and "-1" on the others.

// The buttons a reader can reach: not hidden at an end of a list, not disabled.
export const reachable = (toolbar) => [...toolbar.querySelectorAll("button:not(.invisible):not(:disabled)")]

// For a keydown on the toolbar: left and right move the focus one button, Home
// and End to the first and the last.
export function stepToolbar(event) {
    const buttons = reachable(event.currentTarget)
    const at = buttons.indexOf(document.activeElement)
    const next = {ArrowRight: buttons[at + 1], ArrowLeft: buttons[at - 1], Home: buttons[0], End: buttons.at(-1)}[event.key]
    if (!next) return

    event.preventDefault()
    next.focus()
}

// Puts the toolbar's one tab stop on `preferred`, or on the first button that
// can be reached. A toolbar with none to reach is left with no stop at all.
export function setTabStop(toolbar, preferred = null) {
    const stop = preferred ?? reachable(toolbar)[0]
    toolbar.querySelectorAll("button").forEach((button) => { button.tabIndex = button === stop ? 0 : -1 })
}
