import Kiosk from "controllers/kiosk_controller";

// Runs the kiosk bookmark page when no one is there to run it. The timed
// reload is the kiosk base's; this adds the clock, and words the countdown.
//
// A document that has been deleted answers with nothing at all, which reaches
// neither of the base's failure paths. That is deliberate: the last good copy
// of the links stays on the screen, and the page keeps asking, so it comes
// back on its own if the document does.
export default class extends Kiosk {
    static targets = ["clock"];

    connect() {
        super.connect();
        this.showClock();
    }

    everySecond() {
        this.showClock();
    }

    frameLoaded() {
        super.frameLoaded();
        // The document is new markup, so the clock is a new element.
        this.showClock();
    }

    showClock() {
        if (this.hasClockTarget) {
            this.clockTarget.textContent = new Date().toLocaleString(undefined, {
                weekday: "short", month: "short", day: "numeric",
                hour: "2-digit", minute: "2-digit", second: "2-digit"
            });
        }
    }

    countdownText() {
        return this.secondsToRefresh > 0 ? `Page refresh in ${this.timeLeft()}` : "";
    }

    // Minutes round up, so the last stretch reads "1 minute" rather than
    // sitting at zero, and seconds only appear inside the final minute.
    timeLeft() {
        const seconds = this.secondsToRefresh;

        if (seconds < 60) {
            return `${seconds} second${seconds === 1 ? "" : "s"}`;
        }

        const minutes = Math.ceil(seconds / 60);
        return `${minutes} minute${minutes === 1 ? "" : "s"}`;
    }
}
