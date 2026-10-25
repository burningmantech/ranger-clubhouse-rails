import Kiosk from "controllers/kiosk_controller";

// Runs the wall display when no one is there to run it. The timed reload is
// the kiosk base's; this adds the walk down the groups, so each one reaches
// the top of the screen in turn, wrapping back to the first.
//
// The one timer drives both: it ticks once a second and counts down twice.
export default class extends Kiosk {
    static targets = ["group", "railItem", "header"];
    static values = {
        // The board's own timings; the base leaves the interval to the page.
        refreshSeconds: {type: Number, default: 300},
        dwellSeconds: {type: Number, default: 5}
    };

    connect() {
        this.secondsToScroll = this.dwellSecondsValue;
        this.groupIndex = 0;
        super.connect();
        this.measureHeader();
        this.highlightCurrentGroup();
    }

    everySecond() {
        this.advanceScroll();
    }

    advanceScroll() {
        // Nothing to walk through with a single group, and no wrap to make.
        if (this.groupTargets.length <= 1) {
            return;
        }

        this.secondsToScroll -= 1;
        if (this.secondsToScroll > 0) {
            return;
        }

        this.secondsToScroll = this.dwellSecondsValue;
        this.groupIndex = (this.groupIndex + 1) % this.groupTargets.length;
        this.highlightCurrentGroup();
        this.scrollToCurrentGroup();
    }

    scrollToCurrentGroup() {
        if (this.groupIndex === 0) {
            // Back to the very top, so the heading is on screen for the start
            // of each pass.
            window.scrollTo({top: 0, behavior: "smooth"});
        } else {
            this.groupTargets[this.groupIndex].scrollIntoView({behavior: "smooth", block: "start"});
        }
    }

    highlightCurrentGroup() {
        const groups = this.groupTargets;

        // A refresh can bring back a different number of groups, so the mark
        // is put back only after checking it still points at one of them.
        if (this.groupIndex >= groups.length) {
            this.groupIndex = 0;
        }

        groups.forEach((group, index) => {
            group.classList.toggle("photo-board-group-active", index === this.groupIndex);
        });

        this.railItemTargets.forEach((item, index) => {
            item.classList.toggle("photo-board-rail-item-active", index === this.groupIndex);
        });
    }

    frameLoaded() {
        super.frameLoaded();
        // A group that has just been moved back into place gets its full turn,
        // rather than whatever was left of the last one.
        this.secondsToScroll = this.dwellSecondsValue;
        // The board is new markup, so the mark has to be put back on it -- and
        // the screen moved back to it. People signing on and off changes how
        // tall the groups are, so the spot the display was parked at is no
        // longer the group wearing the mark.
        this.measureHeader();
        this.highlightCurrentGroup();
        this.scrollToCurrentGroup();
    }

    // The pinned heading is what a group has to clear to be readable at the top
    // of the screen. Its height is measured rather than guessed: it depends on
    // the type scale and on how many lines the heading wraps onto, so any
    // figure written down here would be wrong at some screen width.
    measureHeader() {
        if (!this.hasHeaderTarget) {
            return;
        }

        this.element.style.setProperty("--photo-board-header-height",
                                       `${this.headerTarget.offsetHeight}px`);
    }
}
