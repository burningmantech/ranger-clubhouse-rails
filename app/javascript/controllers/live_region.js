// Tells a screen reader something: one line added to a live region, which
// reads out what is added to it. The region is the one inside an open modal
// dialog where there is one (data-live-region: everything outside the dialog
// is inert), else the layout's #live-region (layouts/application). The line
// is returned, and the caller's previous line, when given, is taken down
// first, so a control that speaks again and again leaves one line, not a
// trail. The kiosk and print layouts have no region, and nothing of theirs
// announces.
export function announce(text, previous = null) {
    previous?.remove()
    const line = document.createElement("div")
    line.textContent = text
    region()?.append(line)
    return line
}

function region() {
    return document.querySelector("dialog:modal [data-live-region]") ?? document.getElementById("live-region")
}
