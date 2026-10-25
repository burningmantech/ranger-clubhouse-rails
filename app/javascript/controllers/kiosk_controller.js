import { Controller } from "@hotwired/stimulus";

// Runs an unattended page: reloads a Turbo Frame on a timer and shows the
// countdown. The wall display and the kiosk bookmark page both extend it --
// one adds the walk down the groups, the other the clock.
//
// One timer drives everything. It ticks once a second; a subclass hooks
// everySecond() for its own per-tick work and frameLoaded() for what has to
// happen when new markup arrives.
export default class extends Controller {
    static targets = ["frame", "countdown"];
    static values = {
        // Where the frame's content comes from. The one setting the page has to
        // supply, because only Rails knows the address.
        source: String,
        // How long between reloads, in seconds. Zero means never: the timer
        // still ticks for the subclass, the frame is left alone.
        refreshSeconds: Number,
        retrySeconds: { type: Number, default: 30 }
    };

    connect() {
        this.secondsToRefresh = this.refreshSecondsValue;

        // Held in full, and never read back off the frame: an answer that
        // arrives by way of a redirect leaves the address it landed on behind,
        // and asking that one again would not return the content -- only the
        // sign-in page, once a session has timed out.
        this.frameSource = new URL(this.sourceValue, document.baseURI).href;

        this.onFrameLoad = () => this.frameLoaded();
        // The server being unreachable -- what the short retry is really for.
        this.onFrameError = () => this.refreshFailed();
        // Turbo throws the frame away when an answer carries none -- an error
        // page, or the sign-in page. Handling it here also stands down the
        // app-wide answer to this event, which shows that page in place of
        // this one -- on a screen no one is watching, for good, with no timer
        // left to try again.
        this.onFrameMissing = (event) => {
            event.preventDefault();
            this.refreshFailed();
        };

        this.frameTarget.addEventListener("turbo:frame-load", this.onFrameLoad);
        this.frameTarget.addEventListener("turbo:fetch-request-error", this.onFrameError);
        this.frameTarget.addEventListener("turbo:frame-missing", this.onFrameMissing);

        this.showCountdown();
        this.timer = setInterval(() => this.tick(), 1000);
    }

    disconnect() {
        clearInterval(this.timer);
        this.timer = null;

        this.frameTarget.removeEventListener("turbo:frame-load", this.onFrameLoad);
        this.frameTarget.removeEventListener("turbo:fetch-request-error", this.onFrameError);
        this.frameTarget.removeEventListener("turbo:frame-missing", this.onFrameMissing);
    }

    tick() {
        this.everySecond();

        // Nothing is counting down: the page asked for no reload, and no
        // failed fetch has scheduled a retry.
        if (this.secondsToRefresh <= 0) {
            return;
        }

        this.secondsToRefresh -= 1;
        this.showCountdown();

        if (this.secondsToRefresh <= 0) {
            // Reset first: a reload that never answers must not start a new one
            // every second afterwards.
            this.secondsToRefresh = this.refreshSecondsValue;
            this.askForFrame();
        }
    }

    // Per-tick work for the subclass. Nothing by default.
    everySecond() {}

    askForFrame() {
        const frame = this.frameTarget;

        // Put the frame's own address back if something moved it off. Assigning
        // it is itself the request, so there is nothing more to do.
        if (frame.src !== this.frameSource) {
            frame.src = this.frameSource;
            return;
        }

        frame.reload();
    }

    frameLoaded() {
        this.secondsToRefresh = this.refreshSecondsValue;
        this.showCountdown();
    }

    refreshFailed() {
        // No one is here to reload the page, so come back soon rather than
        // waiting out a full interval with stale content on the screen.
        this.secondsToRefresh = this.retrySecondsValue;
        this.showCountdown();
    }

    showCountdown() {
        if (this.hasCountdownTarget) {
            this.countdownTarget.textContent = this.countdownText();
        }
    }

    // What the countdown reads. The board shows the bare seconds; the
    // bookmark page spells it out.
    countdownText() {
        return String(Math.max(this.secondsToRefresh, 0));
    }
}
