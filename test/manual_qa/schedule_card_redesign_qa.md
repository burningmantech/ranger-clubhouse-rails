# Manual QA Checklist — Schedule Card Redesign

Complete this checklist before merging. Mark each item pass/fail.
Automated system tests cover items marked (automated).

## /me/schedule — Upcoming Cards

- [ ] Card shows position title, Location/Audience label, and description
- [ ] Meta row shows time, duration, and credits (stacked on mobile, 3-col on desktop)
- [ ] "No credits" appears when credits are zero (automated)
- [ ] Decimal credits appear when credits are non-zero (automated)
- [ ] Remove From Schedule button renders for future shifts (automated)
- [ ] Confirm modal appears on Remove button click

## /me/schedule — Past / In-Progress Cards

- [ ] Ended shift shows "Cannot remove after shift start" status text (automated)
- [ ] Started (in-progress) shift shows "Cannot remove after shift start" (automated)
- [ ] No Remove From Schedule button present for started/ended shifts (automated)
- [ ] Status text is non-interactive (not focusable via Tab) (automated)

## /me/schedule — Overlap Cards

- [ ] Overlap alert title reads "Overlapping shift" (automated)
- [ ] Overlap alert body reads "Credit is granted only for the shift you check into." (automated)
- [ ] Conflict list entries show formatted datetime with timezone
- [ ] Signed-up overlap card shows green "Signed up" badge + amber "Overlapping shift" badge (automated)
- [ ] Combined "Signed up & Overlapping Shift" badge text is removed (automated)
- [ ] Overlap callout appears below title/time row, not at top of card
- [ ] Signed-up cards no longer show availability row
- [ ] Non-signed-up cards do not show overlap callout (automated)
- [ ] Dark mode contrast remains legible for warning callout and badges

## /me/schedule — Details Toggle

- [ ] Label reads "Details:" (automated)
- [ ] Toggle starts as "Show details" with aria-expanded="false" (automated)
- [ ] Clicking toggles to "Hide details" with aria-expanded="true" (automated)
- [ ] Clicking again reverts to "Show details" with aria-expanded="false" (automated)
- [ ] Toggle is a `<button>` element (not `<a>`) (automated)
- [ ] Toggle is keyboard-operable via Enter key (automated)

## /me/available_sign_up — Shared Partial Regression

- [ ] Overlap alert title/body copy matches schedule page (automated)
- [ ] Details area uses "Details:" label and "Show details" toggle (automated)
- [ ] Read-more toggle expands/collapses correctly (automated)

## Mobile (< lg breakpoint)

- [ ] Meta data stacks cleanly (single column)
- [ ] Mobile-only labels (Time:, Duration:, Credits:) are visible
- [ ] Desktop-only labels are hidden
- [ ] No critical truncation in header block
- [ ] Buttons remain tap-friendly (minimum 36px touch target)

## Keyboard Navigation

- [ ] Tab traversal reaches Show Sign-Ups button (automated — true tab-key traversal)
- [ ] Tab traversal reaches Remove From Schedule link on future cards (automated — true tab-key traversal)
- [ ] Tab traversal skips non-interactive status text on started/ended cards (automated — true tab-key traversal)
- [ ] Details toggle button reachable via Tab and operable via Enter (automated — true tab-key traversal)
- [ ] Visible focus indicators on all interactive elements
- [ ] Logical tab order within card (toggle → action buttons)

## Dark Mode

- [ ] Card background contrast is correct (stone-800)
- [ ] Text remains legible in all sections
- [ ] Status text muted color is readable
- [ ] Toggle button hover state visible

## Browser Compatibility

- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
