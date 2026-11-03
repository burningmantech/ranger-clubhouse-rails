// Tells a screen reader something: one line added to the layout's #live-region
// (layouts/application), which reads out what is added to it. The line is
// returned for a caller that takes it down again. The kiosk and print layouts
// have no region, and nothing of theirs announces.
export function announce(text) {
    const line = document.createElement("div")
    line.textContent = text
    document.getElementById("live-region")?.append(line)
    return line
}
