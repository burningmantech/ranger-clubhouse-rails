import UnsavedChanges from "controllers/unsaved_changes_controller";
import { scrollParent, scrollWithin } from "controllers/scrolling";

// HQ Window shift page controller — port of the client state machine in
// port/controllers/hq/shift.js + port/components/hq-timesheet-verification.js
// and the route guards in port/routes/hq/shift.js.
//
// Owns three pieces of client-only state:
//  - the suggested-task checklist chips (complete/add/ignore transitions;
//    labels arrive server-rendered in the labels value — no copy lives here)
//  - the Skip Review flags (never persisted, reset on reload, exactly as
//    upstream: entries skipped client-side count as reviewed so Start Shift
//    can be shown)
//  - the leave-page guards ("No Shift Started/Ended" and "Barcode Entered
//    But Not Checked Out"): the unsaved-changes controller's
//    turbo:before-visit + beforeunload guards, with guard() overridden.
//
// Turbo-stream mutations replace the #hq-shift-signal element; its
// targetConnected callback applies the matching checklist transition.
export default class extends UnsavedChanges {
    static targets = [
        "todo", "todoList", "todoCount", "todoTemplate", "allDone",
        "nextAction", "nextActionLabel",
        "signal", "startPanel", "reviewNotice", "skipAllRow",
        "entryStatus", "entrySkippedStatus"
    ];

    static values = {
        labels: { type: Object, default: {} },
        shiftHandled: { type: Boolean, default: false },
        endedEntry: { type: Number, default: 0 },
        offDuty: { type: Boolean, default: true },
        choreograph: { type: String, default: "" }
    };

    // Stimulus starts its target observer before calling connect(), so
    // signalTargetConnected can fire first — on a restored Turbo snapshot the
    // signal element still carries data-event from the last stream. State must
    // therefore exist before any target callback runs.
    initialize() {
        this.skipped = new Set();
        this.shiftHandled = false;
        this.submitting = false;
        this.leaving = false;
        this.reviewFinishedOnce = false;
    }

    connect() {
        this.shiftHandled = this.shiftHandledValue;

        this.handleSubmitStart = this.handleSubmitStart.bind(this);
        this.handleSubmitEnd = this.handleSubmitEnd.bind(this);
        this.handleBeforeRender = this.handleBeforeRender.bind(this);
        document.addEventListener("turbo:submit-start", this.handleSubmitStart);
        document.addEventListener("turbo:submit-end", this.handleSubmitEnd);
        document.addEventListener("turbo:before-render", this.handleBeforeRender);
        super.connect();

        // Post-start-shift choreography: jump to Radios & Gear and put the
        // cursor in the barcode field.
        if (this.choreographValue === "assets") {
            this.openAndScroll("hq-assets-section");
            this.focusBarcode();
        }
    }

    disconnect() {
        super.disconnect();
        document.removeEventListener("turbo:submit-start", this.handleSubmitStart);
        document.removeEventListener("turbo:submit-end", this.handleSubmitEnd);
        document.removeEventListener("turbo:before-render", this.handleBeforeRender);
    }

    // --- Skip Review (client-only, resets on reload) -----------------------

    skipEntry(event) {
        const id = Number(event.currentTarget.dataset.entryId);
        if (id) {
            this.skipped.add(id);
        }
        this.applySkipDisplays();
        this.recompute();
    }

    skipAll() {
        this.unreviewedRows().forEach((row) => this.skipped.add(Number(row.dataset.entryId)));
        this.applySkipDisplays();
        this.recompute();
    }

    // Turbo-stream mutations replace the signal element with fresh data
    // attributes; the initial (empty) element carries no event.
    signalTargetConnected(el) {
        const { event, pog, complete } = el.dataset;
        if (!event) {
            return;
        }

        if (event === "verification") {
            // The verification list was just re-rendered — re-apply the
            // client-side skip flags, then recount.
            this.applySkipDisplays();
            this.recompute();
        } else if (event === "pog-issued" && (pog === "meal" || pog === "half-meal")) {
            this.completeTodo("meal_pog");
            this.updateTodoCount();
        } else if (event === "assets") {
            // Radios & Gear was streamed back in place: apply the radio
            // checklist transitions and put the cursor back in the barcode
            // field, which the section replace destroyed. The scan loop
            // depends on that focus surviving every checkout.
            (complete ?? "").split(",").filter(Boolean).forEach((task) => this.completeTodo(task));
            this.updateTodoCount();
            this.focusBarcode();
        }
    }

    // --- Review accounting -------------------------------------------------

    unreviewedRows() {
        return Array.from(this.element.querySelectorAll('#hq-verification tr[data-needs-review="true"]'));
    }

    effectiveUnreviewedCount() {
        return this.unreviewedRows().filter((row) => !this.skipped.has(Number(row.dataset.entryId))).length;
    }

    applySkipDisplays() {
        const needsReview = new Set(this.unreviewedRows().map((row) => Number(row.dataset.entryId)));

        // Entries that were verified or corrected server-side are no longer
        // skipped (upstream clears isIgnoring on verify/correction).
        this.skipped.forEach((id) => {
            if (!needsReview.has(id)) {
                this.skipped.delete(id);
            }
        });

        this.entryStatusTargets.forEach((el) => {
            el.hidden = this.skipped.has(Number(el.dataset.entryId));
        });
        this.entrySkippedStatusTargets.forEach((el) => {
            el.hidden = !this.skipped.has(Number(el.dataset.entryId));
        });
    }

    recompute() {
        const remaining = this.effectiveUnreviewedCount();

        if (remaining === 0) {
            this.completeTodo("verify_timesheet");
        } else {
            this.addTodo("verify_timesheet");
        }

        if (this.hasStartPanelTarget) {
            this.startPanelTarget.hidden = remaining > 0;
        }
        if (this.hasReviewNoticeTarget) {
            this.reviewNoticeTarget.hidden = remaining === 0;
        }
        if (this.hasSkipAllRowTarget) {
            this.skipAllRowTarget.hidden = remaining === 0;
        }

        // After ending a shift, finishing the review moves the flow along to
        // Radios & Gear — collect the radio first, with Meals & Showers open
        // right below it (upstream afterShiftReview scrolls to the assets
        // accordion and merely opens the pogs one).
        if (remaining === 0 && this.endedEntryValue && !this.reviewFinishedOnce) {
            this.reviewFinishedOnce = true;
            this.openAndScroll("hq-assets-section");
            const pogs = document.getElementById("hq-pogs-section");
            if (pogs) {
                pogs.open = true;
            }
        }

        this.updateTodoCount();
    }

    // --- Todo checklist ----------------------------------------------------

    findTodo(task) {
        return this.todoTargets.find((el) => el.dataset.task === task);
    }

    completeTodo(task) {
        const chip = this.findTodo(task);
        if (chip) {
            chip.dataset.completed = "true";
            this.paintChip(chip);
        }
    }

    addTodo(task, ignore = false) {
        let chip = this.findTodo(task);
        if (chip) {
            chip.dataset.completed = "false";
            chip.dataset.ignore = ignore ? "true" : "false";
        } else {
            if (!this.hasTodoTemplateTarget || !this.hasTodoListTarget) {
                return;
            }
            const fragment = this.todoTemplateTarget.content.cloneNode(true);
            chip = fragment.querySelector("[data-task]");
            chip.dataset.task = task;
            chip.dataset.ignore = ignore ? "true" : "false";
            // Server-supplied label map; textContent keeps it inert.
            chip.querySelector("span").textContent = this.labelsValue[task] || task;
            this.todoListTarget.appendChild(fragment);
        }
        this.paintChip(chip);
    }

    paintChip(chip) {
        const icon = chip.querySelector("i");
        const completed = chip.dataset.completed === "true";
        const ignore = chip.dataset.ignore === "true";
        const blink = chip.dataset.blink === "true";

        // Must stay in step with the same branches in _todo_chip.html.erb.
        // Done and ignored both recede to muted and are told apart by glyph;
        // the row's colour belongs to what is still owed, not to what is
        // already behind the operator. text-primary is cleared here and
        // re-applied by paintNextChip, which always runs after this.
        chip.classList.remove("text-primary", "text-stone-muted", "animate-pulse");
        if (ignore) {
            chip.classList.add("text-stone-muted");
            icon.className = "fa-solid fa-ban";
        } else if (completed) {
            chip.classList.add("text-stone-muted");
            icon.className = "fa-solid fa-check";
        } else {
            if (blink) {
                chip.classList.add("animate-pulse");
            }
            icon.className = "fa-regular fa-circle";
        }
    }

    // The chip the "Next:" line is naming takes the same primary as that
    // line's arrow, so the sentence and its place in the checklist are one
    // signal rather than two the operator has to reconcile. Cleared across
    // every chip first: the next action moves on every completion, revival
    // and skip, and a stale second claim is worse than none.
    paintNextChip(openTodos) {
        this.todoTargets.forEach((chip) => chip.classList.remove("text-primary"));
        openTodos[0]?.classList.add("text-primary");
    }

    updateTodoCount() {
        const openTodos = this.todoTargets.filter(
            (el) => el.dataset.completed !== "true" && el.dataset.ignore !== "true"
        );
        const open = openTodos.length;

        this.paintNextChip(openTodos);

        if (this.hasTodoCountTarget) {
            this.todoCountTarget.hidden = open === 0;
            this.todoCountTarget.textContent =
                `${open} suggested ${open === 1 ? "task" : "tasks"}:`;
        }
        if (this.hasAllDoneTarget) {
            this.allDoneTarget.hidden = open > 0;
        }

        // The spelled-out next action tracks the first still-open chip, so it
        // stays true through every completion, revival, and skip.
        if (this.hasNextActionTarget) {
            this.nextActionTarget.hidden = open === 0;
            if (open > 0 && this.hasNextActionLabelTarget) {
                this.nextActionLabelTarget.textContent =
                    openTodos[0].querySelector("span")?.textContent ?? "";
            }
        }
    }

    // --- Leave-page guards -------------------------------------------------

    // Any form submission from this page (check in/out, checkout, verify,
    // pogs...) is a deliberate action — its redirect must not trip the
    // guards. Turbo proposes that redirect after turbo:submit-end, so
    // "leaving" carries past it, until the page it leads to -- or this one,
    // morphed back in place -- starts rendering. A stream answer redirects
    // nowhere and leaves the guards armed. Listened for on the document: the
    // pog and correction dialogs submit from the layout's modal frame,
    // outside this element.
    handleSubmitStart() {
        this.submitting = true;
    }

    handleSubmitEnd({ detail }) {
        this.submitting = false;
        this.leaving = detail.success === true && detail.fetchResponse?.redirected === true;
    }

    handleBeforeRender() {
        this.leaving = false;
    }

    // The unsaved-changes guard: {key, message} for the first one that
    // applies, or null. The unhandled shift is checked before the barcode,
    // matching upstream (port/routes/hq/shift.js aborts on noShiftHandled
    // first) — the reverse order let a stray barcode hide the more important
    // "no shift" warning.
    guard() {
        if (this.submitting || this.leaving) {
            return null;
        }
        if (!this.shiftHandled) {
            return {
                key: "shift",
                message: (this.offDutyValue
                    ? "It looks like a shift was not started."
                    : "It looks like a shift was not ended.") +
                    " Leave this page anyway?"
            };
        }
        if (this.barcodeValue() !== "") {
            return {
                key: "barcode",
                message: "A barcode was entered but not checked out. Check out the asset or " +
                    "clear the barcode field before leaving this page. Navigate away anyway?"
            };
        }
        return null;
    }

    // Ask once per flag, as upstream: navigating away clears it. Only the
    // shift guard clears — confirming a barcode prompt must not suppress the
    // unhandled-shift warning.
    guardConfirmed({ key }) {
        if (key === "shift") {
            this.shiftHandled = true;
        }
    }

    guardDeclined({ key }) {
        if (key === "barcode") {
            this.openAndScroll("hq-assets-section");
            this.focusBarcode();
        }
    }

    barcodeValue() {
        return document.getElementById("checkout-barcode")?.value?.trim() ?? "";
    }

    // --- Choreography ------------------------------------------------------

    // The page scrolls inside the drawer/main container, not the window, and
    // the pinned checklist overlays the top of it — so scroll the container by
    // hand and stop short by the checklist's height, or the section heading
    // lands underneath it. Upstream did the same by passing "todo-list" as
    // scrollToAccordion's offset element. The height as drawn: the checklist
    // is inside the HQ shell's zoom (components/hq-window.css), the drawer
    // outside it.
    openAndScroll(sectionId) {
        const section = document.getElementById(sectionId);
        if (!section) {
            return;
        }

        // Guided flow: the section being scrolled to becomes the one open
        // section. Only choreography and the barcode guard land here — all of
        // them follow an action the operator just took — so nothing collapses
        // under them. A section they open by hand is never touched.
        this.element.querySelectorAll("details[data-hq-section]").forEach((el) => {
            if (el !== section) {
                el.open = false;
            }
        });
        section.open = true;

        const scroller = scrollParent(section);
        const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        const behavior = reduced ? "auto" : "smooth";
        if (!scroller) {
            section.scrollIntoView({ behavior, block: "start" });
            return;
        }

        const pinned = document.getElementById("hq-todo-list")?.getBoundingClientRect().height ?? 0;
        scrollWithin(scroller, section, { offset: pinned, behavior });
    }

    // Focused directly rather than on the next animation frame: streams apply
    // in order, so the replaced section is already in the DOM by the time the
    // signal connects, and a backgrounded tab never runs the frame callback at
    // all. preventScroll keeps the focus from fighting an in-flight smooth
    // scroll when the start-shift choreography calls this.
    focusBarcode() {
        document.getElementById("checkout-barcode")?.focus({ preventScroll: true });
    }
}
