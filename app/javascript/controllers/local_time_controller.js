import { Controller } from "@hotwired/stimulus"

// Spelled out because timeStyle cannot be paired with timeZoneName. h23, not
// hour12: false, which some locales render as 24:00 at midnight.
const FORMAT = new Intl.DateTimeFormat(undefined, {
    weekday: "long", year: "numeric", month: "long", day: "numeric",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZoneName: "short"
})

// Lives on <body>. Restates each timestamp's tooltip in the browser's own
// timezone as it lands, whether with the page, a frame or a stream. The
// server's title, in the app's zone, stays if the value is bad.
export default class extends Controller {
    static targets = ["time"]

    timeTargetConnected(element) {
        const date = new Date(element.dataset.utc)
        if (isNaN(date)) return

        element.title = FORMAT.format(date)
    }
}
