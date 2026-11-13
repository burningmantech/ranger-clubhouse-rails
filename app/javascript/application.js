// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers";
import { session } from "controllers/storage"
import { reveal } from "controllers/scrolling"

// Some controls build themselves in the page rather than arriving with the HTML
// the server sent: the rich text editor writes its own toolbar and holds the
// text being edited, and the state list is filled in to match the country
// picked. Pages here are updated by morphing, which compares the page against
// that server HTML, so it would throw all of that away — emptying the editor and
// the state list along with whatever had been chosen or typed. Anything marked
// data-morph-skip is left out of the comparison and kept as it stands; the rest
// of the page still morphs normally.
//
// One thing a skipped control still takes from the server is its classes. A
// field that comes back from a rejected form has to show that it is in error,
// and that is a class on the field. The classes the server gave it last time are
// remembered, so that those are what is taken off again; the ones the control
// put on itself are never touched. They are remembered on the element, because
// the page the Back button returns to is a copy, and a copy keeps its
// attributes and nothing else.
document.addEventListener("turbo:before-morph-element", (event) => {
    const element = event.target;
    if (!element.matches?.("[data-morph-skip]")) return;

    event.preventDefault();

    // No new element when the page is taking this one out; it stays as it is.
    const incoming = event.detail.newElement;
    if (!incoming) return;

    const remembered = element.dataset.serverClass;
    if (remembered) element.classList.remove(...remembered.split(" "));
    element.classList.add(...incoming.classList);
    element.dataset.serverClass = [...incoming.classList].join(" ");
});


// A link to a place on this same page (href="#faq") is the browser's to
// follow: it scrolls there and keeps the page as it is. Turbo 8.0.23 has no
// same-page shortcut, so it would fetch the page again and replace it,
// throwing away whatever had been typed into it. Cancelling turbo:click hands
// the click back to the browser, which every such link then gets for free.
document.addEventListener("turbo:click", (event) => {
    const url = new URL(event.detail.url);
    const here = window.location;
    if (url.hash && url.origin === here.origin && url.pathname === here.pathname && url.search === here.search) {
        event.preventDefault();
    }
});

history.scrollRestoration = "manual"; // Disable Chrome maintaining scroll position on page refresh

Turbo.StreamActions.page_redirect = function () {
    Turbo.visit(this.getAttribute("url"), {frame: "_top", action: "advance"});
};

// The address analytics last heard of, without its query
// (application/_google_analytics_code): the referrer of the next page view.
let analyticsLocation = document.referrer.split(/[?#]/)[0];

// Preserve messages list scroll position when opening and returning from a conversation
const MESSAGES_SCROLL_KEY = "messages-list-scroll";
document.addEventListener("turbo:before-visit", (event) => {
    if (/\/me\/messages\/\d+/.test(event.detail.url)) {
        const container = document.querySelector(".drawer-content");
        if (container) session.write(MESSAGES_SCROLL_KEY, container.scrollTop);
    }
});

document.addEventListener("turbo:load", () => {
    if (window.location.pathname === "/me/messages") {
        const saved = session.read(MESSAGES_SCROLL_KEY);
        if (saved !== null) {
            session.remove(MESSAGES_SCROLL_KEY);
            requestAnimationFrame(() => {
                const container = document.querySelector(".drawer-content");
                if (container) container.scrollTop = parseInt(saved, 10);
            });
        }
    }

    // The first page's view too: the config sends none of its own
    // (application/_google_analytics_code). The address goes without its
    // query, as the request log keeps it (RequestLogger#path_for): a query can
    // carry personal data, such as a mailbox search's text and callsigns. Set
    // for every hit after it, not this one alone: the tag's own engagement
    // events take the page from here, and the address otherwise.
    if (typeof gtag === 'function') {
        const page_location = window.location.origin + window.location.pathname;
        gtag('set', {page_location, page_referrer: analyticsLocation});
        gtag('event', 'page_view', {page_location, page_path: window.location.pathname, page_title: document.title});
        analyticsLocation = page_location;
    }
});

// An answer without the frame is a whole page the server sent instead: the
// sign-in page once a session has ended, the dashboard saying this page is not
// allowed, or an error page. Show that page, the way a link that fails shows it.
document.addEventListener("turbo:frame-missing", (event) => {
    // A frame that handles its own missing answer has already said so.
    if (event.defaultPrevented) return;

    event.preventDefault();
    event.detail.visit(event.detail.response);
});

// The message is the dialog itself (ModalHelper#confirm_modal_dialog). It is
// wired and shown in one turn, so a press can never land on a dialog that is not
// listening yet. None of this waits on the modal controller: that is
// lazy-loaded, and on a slow connection it can arrive after the answer.
//
// A controller asking a question of its own passes it as
// {title, message, confirmLabel, cancelLabel, variant} instead, message being
// a sentence or a list of paragraphs; a plain string is the message alone.
// Either way the same dialog is built here (confirmDialog below).
Turbo.config.forms.confirm = (message, element, submitter) => {
    const dialog = confirmDialogFor(message);

    document.getElementById("turbo-confirm-modal").replaceChildren(dialog);

    return new Promise((resolve) => {
        // Every button in the dialog closes it, and only Confirm closes it as a
        // yes. The answer is read when it closes, so Escape counts as a no too
        // instead of leaving the submission hanging.
        dialog.addEventListener("click", (event) => {
            const button = event.target.closest("button");
            if (button) dialog.close(button.id === "turbo-confirm-button" ? "confirm" : "");
        });
        dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true});
        dialog.showModal();
    });
};

function confirmDialogFor(message) {
    if (typeof message === "string") {
        const template = document.createElement("template");
        template.innerHTML = message;
        const dialog = template.content.querySelector("dialog");
        if (dialog) return dialog;

        message = {message};
    }
    return confirmDialog(message);
}

// The dialog ModalHelper#confirm_modal_dialog draws, for a question a
// controller asks: a copy of the one the layout keeps in
// #confirm-dialog-template, filled in. Every text goes in as text, never
// markup: a team or role title in it is a name someone chose.
function confirmDialog({title = "Confirm", message = "Continue?", confirmLabel = "Confirm",
                           cancelLabel = "Cancel", variant = "primary"}) {
    const dialog = document.getElementById("confirm-dialog-template").content.querySelector("dialog").cloneNode(true);
    const paragraphs = [message].flat().map((text) => {
        const paragraph = document.createElement("p");
        paragraph.textContent = text;
        return paragraph;
    });
    const confirm = dialog.querySelector("#turbo-confirm-button");

    dialog.querySelector(".modal-title-text").textContent = title;
    dialog.querySelector(".modal-body-content").replaceChildren(...paragraphs);
    confirm.textContent = confirmLabel;
    if (variant === "error") confirm.classList.replace("btn-primary", "btn-error");
    dialog.querySelector("#turbo-cancel-button").textContent = cancelLabel;
    return dialog;
}

// A dropdown menu is a native <details> (NavigationHelper#dropdown_menu),
// which only its own summary closes. A link in it closes it here, and so does
// a click anywhere outside it. Turbo brings the next page in only once it has
// arrived, so until then the menu hung open over this one; and the copy of
// this page Turbo caches on the way out -- the one Back shows -- was taken
// after the click, with the menu as it was.
document.addEventListener("click", ({target}) => {
    document.querySelectorAll("details.dropdown[open]").forEach((menu) => {
        if (!menu.contains(target) || target.closest("a")) menu.open = false;
    });
});

// Escape closes an open menu too. Focus that was inside it goes back to its
// summary, so the keyboard reader is where the menu was opened from.
document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;

    document.querySelectorAll("details.dropdown[open]").forEach((menu) => {
        const hadFocus = menu.contains(document.activeElement);
        menu.open = false;
        if (hadFocus) menu.querySelector("summary")?.focus();
    });
});

// A live region's lines are heard as they land and have no place in the copy
// of the page Turbo keeps for Back: restored, a line would be stale and
// owned by no one (controllers/live_region.js).
document.addEventListener("turbo:before-cache", () => {
    document.querySelectorAll("#live-region, [data-live-region]").forEach((region) => region.replaceChildren());
});

// The year selector holds the year it was just changed to when Turbo copies
// the page it is leaving, and the copy keeps a select's live choice. Back would
// show that year over the old year's page and export, so put the page's own back.
document.addEventListener("turbo:before-cache", () => {
    document.querySelectorAll("#year-selector, #year-selector-compact").forEach((select) => select.form.reset());
});

// A refused submit comes back as a 422 render, which keeps the scroll where
// the reader pressed the button. A page that reports the refusal in a callout
// of its own (data-refusal, above its form) has that callout brought into
// view and focused, as form_controller does for the builder's error summary.
// Only for the render that answers the refused submit: any later render of
// the page leaves the reader where they are.
let submitRefused = false;
document.addEventListener("turbo:submit-end", ({detail}) => { submitRefused = !detail.success; });
document.addEventListener("turbo:render", () => {
    const refused = submitRefused;
    submitRefused = false;
    const refusal = refused && document.querySelector("[data-refusal]");
    if (!refusal) return;

    refusal.focus({preventScroll: true});
    // After this turn: Turbo puts the scroll back where it was once the render
    // is done. At once, not smoothly: the callout can be a long page away.
    setTimeout(() => reveal(refusal, null, {behavior: "auto"}));
});
