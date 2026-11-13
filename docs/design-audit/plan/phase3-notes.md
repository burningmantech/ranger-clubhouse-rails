# Phase 3 notes for every area agent

Read after `plan.md` ("Rulings", "Rules for every agent"). These say what changed since the audit.

## The guide was rewritten (commits b76d5d8, 6833106)

Guide line numbers quoted in a finding's note are stale. Find the rule by its heading in
`docs/DESIGN-GUIDE.md`; its current text is the target and outranks the note.

## The shared layer changed in Phase 2

A finding the shared layer already fixed is `COMPLIANT` (say "fixed by Phase 2"). Check before editing.

- `delete_button` confirms by default: "Delete this record? This cannot be undone." Pass
  `confirm: "this note"` to name the thing, `confirm_message:` for a full question, `confirm: false`
  only where a confirmation is already given another way. Give every `delete_button` in your views
  that names nothing a proper noun or question.
- Every confirm is the app dialog. A plain-string `turbo_confirm:` now opens the app dialog too, but
  a destructive one must be red: use `confirm_modal(... variant: :error)` or `delete_button`.
- The required marker is the visible "(required)" word. `required_label:` and `help_mode:` no longer
  exist: remove them wherever a view still passes one.
- `ui_label_value` defaults to `text-base`. `submit_button`'s default label is "Save".
- Modals name themselves from `m.title`. A modal with no `m.title` has no accessible name: give it one.
- Sidebar `icon:`, `badge:` and `use_turbo:` options are gone.

## Work handed down from Phase 2 (do it if the file is yours)

- `app/views/profile_photos/crop.html.erb`: inside the form, above the crop tools, add
  `<div class="mb-4" data-photo-cropper-target="error" hidden>` holding
  `ui_callout_box :error, accent: true, role: "alert"` with `<span data-photo-cropper-target="errorMessage">`.
  The controller already uses these targets.
- `app/views/profile_photos/new.html.erb`: the capture button through `ButtonHelper` and `#camera-select`
  as a daisyUI `select`; list in your report which `camera-*` utilities are then unused (do not edit CSS).
- Any view using `data-controller="toggle"` (seven exist, among them `hq/shift_manage/_pog_guideline`,
  `person/provisions/_section`, `common/schedule/_signed_up_row`): convert to `ui_disclosure`.
- `app/views/common/_years_breakdown.html.erb` lines 17 and 34: italic "none" becomes "—".
- `mentoring/alpha_pods/people/edit.html.erb` and `shift_operations/cruise_direction/people/edit.html.erb`:
  the "Take out of …" `delete_button` needs a `confirm_message:` that asks with its action.

## Not yours to decide

Leave these alone and record `NEEDS-APPROVAL` if a finding depends on one: the gold hero and action-box
icons, the year selector's markup, `ui_section border: false`, the date picker's 768px switch.

## You cannot edit the shared layer

`app/helpers/*.rb` at the top level, `app/helpers/ui_components/`, `app/assets/` and `app/javascript/`
are closed. If a fix needs one, record `BLOCKED` with the exact change.
