// Tells a screen reader something: one line added to the layout's #live-region
// (layouts/application), which reads out what is added to it. The line is
// returned, and the caller's previous line, when given, is taken down first,
// so a control that speaks again and again leaves one line, not a trail. The
// kiosk and print layouts have no region, and nothing of theirs announces.
export function announce(text, previous = null) {
    previous?.remove()
    const line = document.createElement("div")
    line.textContent = text
    document.getElementById("live-region")?.append(line)
    return line
}
