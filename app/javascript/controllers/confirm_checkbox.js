// Asks before a box stays ticked, and unticks it on no. True when it stays.
export function confirmChecked(checkbox, message) {
    if (window.confirm(message)) return true
    checkbox.checked = false
    return false
}
