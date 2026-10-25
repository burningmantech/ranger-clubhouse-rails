---
name: design-content
description: Language rules, terminology, ADHD-friendly patterns, and accessibility guidelines for Clubhouse 3. Use when writing UI text, button labels, flash messages, confirm dialogs, validation or error messages, or date and price formats, or when ensuring accessible design patterns.
---




# Design Content

## Terminology Rules

**CRITICAL - Never use these terms:**
- "work" or "working"
- "job" (in the employment sense)
- "employee" or "staff"

**PREFERRED alternatives:**
- "volunteer efforts" / "volunteering"
- "ranger" (as verb or noun)
- "rangering"
- "shift" / "shifts"
- "service" / "service hours"
- "volunteer" / "volunteers"

### Examples

| Never Use | Use Instead |
|-----------|-------------|
| work, working | volunteer, volunteering, rangering |
| job | shift, position, role |
| employee, staff | volunteer, ranger |
| work hours | volunteer hours, service hours |
| work history | volunteer history, service history (except [Work History](#exception-the-work-history-pages)) |

**Examples:**
- ❌ "Your work hours" → ✅ "Your volunteer hours"
- ❌ "Working shifts" → ✅ "Scheduled shifts"
- ❌ "Work history" → ✅ "Volunteer history" or "Service history" (except the Work History pages, below)

### Exception: genuinely paid positions

The ban exists because calling a volunteer an employee is wrong. Where the
relationship **is** employment, the employment word is the accurate one and is
**preferred** — reaching for "volunteer" there would be the error.

This applies to payroll and Paycom surfaces only:

| Context | Use |
|---------|-----|
| A position's paycode (paid positions draw payroll) | "Paycom employee code" |
| A person's Paycom identifier | "Paycom Employee ID" |
| Payroll hour adjustments | "employee", "payroll" as needed |

✅ `label: "Paycom Employee Code"` — the position is paid, and the code is what
Paycom pays against.

The exception is narrow. It does **not** license "work", "working", or "job"
anywhere, and it does not extend to shift, schedule, timesheet, or service-hour
copy — those describe volunteering even on a paid position. If you are not
naming a payroll or Paycom field, the ban above applies unchanged.

### Exception: proper names

A named thing keeps its name. "Staff Credential" and "Staff Credentialing" are
ticket and process names, printed as-is wherever they appear. The ban is on
describing volunteers as staff, not on quoting a product name.

### Exception: the Work History pages

By the owner's ruling (2026-10-06), the page of a person's hours by position and
event year is named **Work History**, on purpose, against the ban above:

- `/me/timesheet/work-history` (`Me::WorkHistoryController`), and its button and
  card on Me › Timesheet
- `/person/:id/work-history` (`Person::WorkHistoryController`) and its Person menu item
- the drill-down pages both share (`app/views/common/work_history/`), whose back
  link reads "Work History"
- the ART Training Session trainee dialog
  (`Training::Sessions::WorkHistoriesController`) and its button on the trainee card

The exception is the name only. It does not license "work" in those pages' body
copy or anywhere else.

## Status Values Are Shown As Stored

**CRITICAL — never `.titleize` a person's status.** `person.status` holds the
words the Clubhouse uses for it: `active`, `inactive extension`, `past
prospective`. Print the value itself, everywhere it appears — a badge, a table
cell, a filter select, a chip, a CSV cell, a preview message.

```erb
<%= t.cell row.status %>                        <%# ✅ reads "inactive extension" %>
<%= t.cell row.status.titleize %>                <%# ❌ %>
<%= ui_badge person.status, :secondary %>        <%# ✅ %>
```

One page that title-cases a status while another prints it raw makes the same
status look like two, and a chip that re-cases what its own select spelled
disagrees with the control that set it. Same rule for a filter chip's value
label: return `value`, not `value.titleize`.

**A status held as a code, not a word, is different.** Badge status is stored
as `in_prep` / `do_not_print`; no reader should ever see that. Those have a
label map — `Bmid::ManageHelper::STATUS_LABELS` — and the map is what to print,
falling back to the raw value:

```ruby
STATUS_LABELS.fetch(bmid.status, bmid.status)   # ✅ "Prep"
bmid.status.to_s.titleize                        # ❌ "In Prep", agreeing with nothing
```

The test that guards the shared select label is
`test/helpers/ui_components/filter_bar_helper_test.rb`.

---

## ADHD-Friendly Design Guidelines

The Clubhouse serves users with varying attention profiles. These guidelines are **CRITICAL** for accessibility.

### Visual Hierarchy

- **CRITICAL:** Use clear, consistent heading hierarchy (h1 > h2 > h3)
- **CRITICAL:** Ensure a single, clear primary action per view
- **PREFERRED:** Highlight the most important action on each screen
- **PREFERRED:** Group related information visually with cards and sections
- **PREFERRED:** Use whitespace to reduce cognitive load

### Content Structure

- **CRITICAL:** Lead with the key information (inverted pyramid style)
- **CRITICAL:** Keep paragraphs to 2-3 sentences maximum
- **PREFERRED:** Use bullet points and short paragraphs
- **PREFERRED:** Break long forms into logical sections with fieldsets
- **PREFERRED:** Provide clear progress indicators for multi-step processes

### Typography for Accessibility

- **CRITICAL:** Use `text-base` (0.9rem in this theme) as the minimum for body text
- **CRITICAL:** Sufficient contrast ratios (WCAG AA minimum)
- **PREFERRED:** Keep the theme's 1.2 body leading; add row padding for grouping instead of loosening line-height (DESIGN.md > Tight Leading Rule)
- **PREFERRED:** Clear visual distinction between headings and body text
- **AVOID:** Justified text alignment
- **AVOID:** `text-sm` for primary content

### Interaction Design

- **CRITICAL:** Minimum 36px touch targets for all interactive elements
- **CRITICAL:** Support keyboard navigation throughout
- **PREFERRED:** Provide immediate feedback for user actions (toasts, inline validation)
- **PREFERRED:** Use clear, descriptive button labels
- **AVOID:** Time-sensitive interactions

### Reducing Distractions

- **CRITICAL:** Motion is functional only. The approved set: `animate-spin` loading spinners, the progress-bar pulse, `animate-pulse` on urgent badges, and the sidebar drill-down slide. All of it must honor `prefers-reduced-motion`
- **AVOID:** Decorative motion — hover lifts, entrance animations, parallax
- **AVOID:** Auto-playing media or carousels
- **AVOID:** Flashing or blinking content
- **PREFERRED:** Use muted colors for secondary information
- **PREFERRED:** Keep navigation consistent across pages
- **Exception:** Login page ambient animations are permitted but must respect `prefers-reduced-motion`

### Color and Contrast

- **CRITICAL:** Never rely on color alone to convey information
- **CRITICAL:** Use icons alongside colored status indicators
- **PREFERRED:** Ensure sufficient contrast in both light and dark modes
- **PREFERRED:** Test with color blindness simulators

---

## Writing Style

### Audience

All interface text should be written for a mixed audience of ADHD users and typical web users. Content must be:
- Concise and scannable
- Clear and unambiguous
- Action-oriented where appropriate

### Style Guidelines

- Use active voice
- Address the user directly ("You have 3 shifts scheduled")
- Be specific over vague ("Save profile" not "Submit")
- Use Title Case for every heading and button label — see [Title Case](#title-case) below
- Avoid jargon unless widely understood by Rangers

### Title Case

**CRITICAL:** Every heading and every button label is Title Case. That covers
`hero_panel` titles, `ui_section` titles, `ui_card` titles, `ui_callout_box`,
`ui_alert_banner` and modal `title:` strings, table column headers, tab labels,
and all `ButtonHelper` labels — every string a reader *scans as a label* rather
than *reads as prose*.

The labels that are not headings follow too: `ui_stat_box` and meter or bar
labels, chip labels (a status chip, a filter chip's name: "Dropped Within: 24
hours"), and form field labels and fieldset legends ("First Name", "Expires On").
A parenthetical hint inside a label stays sentence case ("Notes (optional)"), and
a field label does not end in a colon. Two kinds are left out by the owner's
ruling (2026-10-24): checkbox and radio-option labels read as statements and stay
sentence case ("Applicant is 18 years or older"), and badge text keeps the casing
it has.

Capitalize every word except articles (`a`, `an`, `the`), coordinating
conjunctions (`and`, `but`, `or`, `nor`, `for`, `so`, `yet`) and prepositions of
four letters or fewer (`in`, `on`, `to`, `for`, `with`, `from`) — unless the
word is first or last.

| Wrong — sentence case | Right |
|---|---|
| "Adjust your choices" | "Adjust Your Choices" |
| "Before you save" | "Before You Save" |
| "Asset check in / out history" | "Asset Check In / Out History" |
| "Claim your event ticket first" | "Claim Your Event Ticket First" |
| "All claimed items" | "All Claimed Items" |

**A question is not an exemption.** "All set?" and "Accidentally ended the
shift?" read like prose because they *are* prose — which is the signal that they
belong in the body, not in a heading. Name the thing in the heading and move the
question down:

```erb
<%# WRONG -- the heading is a sentence %>
<%= ui_section "Accidentally ended the shift?" do %>
  <p>Ask HQ to reopen it.</p>
<% end %>

<%# RIGHT -- the heading is a label; the question is body copy %>
<%= ui_section "Reopening a Shift" do %>
  <p>Accidentally ended the shift? Ask HQ to reopen it.</p>
<% end %>
```

**Exceptions — text that keeps the casing it already has:**

- Person statuses, printed exactly as stored (`inactive extension`) — see
  *Status Values Are Shown As Stored* above
- Proper and product names ("Staff Credential", "Motor Vehicle Record")
- Interpolated data — `"#{@training.title} Sessions"`; the interpolated half
  carries its own casing
- Body copy, help text, form hints, error messages, empty-state sentences and
  `panel.description` — these are prose and stay sentence case

The rule is guarded by `test/lib/copy_casing_test.rb`, which reads every literal
heading and button label in `app/views` and `app/helpers`. A title built in a Ruby
constant or passed as a `render … label:` local is out of its reach: case it by hand.

### Content Writing Guidelines

| Guideline | Example |
|-----------|---------|
| Lead with key point in bold | `<strong>Key point.</strong> Details follow.` |
| Use short sentences | Max 15-20 words per sentence |
| Avoid jargon | "Motor Vehicle Record" not "MVR" |
| Be specific | "Used for ticketing and mailings" not "Used for various purposes" |
| Answer "why" | Users with ADHD need to understand purpose to stay engaged |

---

## Touch Targets & Accessibility

### Touch Target Requirements

**CRITICAL:** Minimum 36px touch targets for all interactive elements.

This applies to:
- Buttons
- Links
- Checkboxes
- Radio buttons
- Form inputs
- Navigation items
- Icon buttons

### Keyboard Navigation

- **CRITICAL:** Full keyboard support throughout
- **CRITICAL:** Visible focus states with ring outline
- **PREFERRED:** Logical tab order
- **PREFERRED:** Skip links for main content

### Screen Reader Support

**CRITICAL:** Ensure proper ARIA support:
- Labels properly associated with inputs via `for` attribute
- Required fields announce "(required)" to screen readers
- Help text connected via `aria-describedby`
- Error messages use `role="alert"`
- Interactive elements have appropriate ARIA attributes

---

## Q&A Style Content Pattern

Replace paragraphs with scannable Q&A format using `instruction-list`. On a report or a
log the list goes inside the page's one collapsed card, never visible in the body
(`design-rules` > Where a Rule or a How-To Goes); the visible form below is for forms and
pages the reader operates:

```erb
<dl class="instruction-list mb-3">
  <dt>Why do we need this?</dt>
  <dd>Concise answer in one sentence.</dd>
  <dt>Is this required?</dt>
  <dd>No, this field is optional.</dd>
</dl>
```

**Put no classes on the `<dt>` or `<dd>`.** `accessibility.css` does all of it —
spacing, colour, and the prefixes. 4px between a question and its answer, 8px
before the next question. A `mt-2` on a `<dt>` does nothing: `space-y-1` sets
`margin-block-start: 0` from unlayered CSS, which beats the utility. 111 views
spelled it that way and none rendered.

**It draws a `Q:` and an `A:`** — brand blue on the question, muted on the
answer, in a gutter the `<dt>` and `<dd>` reserve with `ps-5`. Write them in the
copy and you get two: "Q: Q: Why do we need this?".

They are decoration, not content. Both are `content: "Q:" / ""`, the alt-text
form, so a screen reader gets an empty string rather than announcing what the
`<dl>` already told it. Do not "fix" that to a plain string.

**Purpose:** Provides clear visual hierarchy for instructional or informational content in a scannable Q&A format, optimized for users with ADHD.

---

## Button Labels

### CRITICAL: Button Label Rules

**Use specific, action-oriented labels:**
- ✅ "Save Profile"
- ✅ "Send Message"
- ✅ "Delete Shift"
- ❌ "Submit"
- ❌ "Click Here"
- ❌ "OK"

### Common Button Labels

| Action | Label | Variant |
|--------|-------|---------|
| Submit form | "Save [Entity]" | `:primary` |
| Cancel action | "Cancel" | `:secondary` or `:ghost` |
| Delete item | "Delete [Entity]" | `:error` |
| Edit item | "Edit" via `edit_link` | `:secondary` (built in) |
| Add new | "Add [Entity]" | `:primary` |
| Go back | "Back to [Page]" | `:secondary` |

### One Verb per Action

**CRITICAL:** An action gets the same verb on every page (owner's ruling, 2026-10-23).

| Action | Say | Never |
|---|---|---|
| Open the form that creates a record | "Add [Entity]" | "New [Entity]", "Create [Entity]" |
| Submit that form, new or edit | "Save [Entity]" | "Update [Entity]", "Create [Entity]", "Submit" |
| Get rid of a record | "Delete [Entity]" | "Remove", "Trash", "Destroy" |
| Take something out of a group | "Remove from [Group]" | "Delete" |
| Leave the page | "Back to [Page]" | a bare "Back" |

**Delete or Remove?** Ask whether the thing still exists afterwards. A deleted passkey is gone:
"Delete Passkey". A shift you leave is still on the schedule: "Remove from Schedule".

A submit that does more than store the record keeps its own verb: "Send Message", "Claim Ticket",
"Create Account".

---

## Flash Messages

**CRITICAL — the type matches the outcome.** A failure is `error:` (or `alert:`), never `success:`.
A green toast reading "could not" tells the reader two opposite things.

A success message is the thing, then what happened to it: `<Thing> <past participle>.`

| Wrong | Right |
|---|---|
| "The note has been successfully added." | "Note added." |
| "Swag was deleted." | "Swag deleted." |
| "Deleted 3 bug reports." | "3 bug reports deleted." |
| "Agreement has been signed. Thank you!" | "Agreement signed." |

- No "successfully": the green toast already says it. No "has been". No exclamation mark.
- Name the thing as the page names it: "Timesheet entry #123 deleted.", "Firecracker removed from
  the shift."
- Add a second sentence only for what the reader needs next: "Survey copied. It stays switched off
  until you activate it."
- An error flash follows [Error Messages](#error-messages).

---

## Confirm Dialogs

Ask with the action, then say what follows from it: `<Verb> <thing>?` plus a sentence on whether
it can be undone.

| Wrong | Right |
|---|---|
| "Are you sure you want to delete this note?" | "Delete this note? This cannot be undone." |
| "Really remove Firecracker from this session?" | "Remove Firecracker from this session? They can sign up again." |

`delete_button` already makes a destructive confirm button red. A dialog built from
`confirm_modal` passes `variant: :error`.

---

## Error Messages

**CRITICAL:** Error messages must be:
- Specific about what went wrong
- Clear about how to fix it
- Action-oriented
- Not blame the user

### Examples

| Bad | Good |
|-----|------|
| "Invalid input" | "Email must include an @ symbol" |
| "Error" | "Password must be at least 8 characters" |
| "Failed" | "Unable to save. Please check your internet connection." |
| "You entered the wrong date" | "Start date must be before end date" |

### The Message Names Its Field

**CRITICAL:** `config/locales/en.yml` sets `errors.format: "%{message}"`, so Rails never puts the
field name in front of a message. The error summary at the top of a form shows the message on its
own, so a fragment like "must be given" doesn't say which field failed. Write every `errors.add`
and `message:` string as a whole sentence: sentence case, a period at the end, and the field named
in the reader's words, never by its column name.

```ruby
errors.add(:left_on, "must be on or after joined_on date")                         # ❌
errors.add(:left_on, "The left on date must be on or after the joined on date.")  # ✅
```

Rails' own messages already do this: `config/locales/en.yml` rewrites them as
`"%{attribute} can't be blank."` and so on. `%{attribute}` is the model's
`human_attribute_name`, so a column that reads badly ("Street1", "Mi") gets a name under
`activerecord.attributes` in the same file.

- **A page that calls the field something else** builds the message with its own name:
  `ValidationMessage.naming(error, "Email address")`. Putting a name in front says it twice.
- **Joining messages:** every message ends in a period, so join them with a space,
  `errors.full_messages.join(" ")`. `", "` and `to_sentence` print "can't be blank., …".
- **A message that needs `%{attribute}` inside a validator that adds strings as written**
  (phonelib) is a locale key, not a string: `message: :phone_invalid`.

---

## Punctuation and Spelling

- **Ellipsis** is one character, `…`, never three periods. That includes placeholders:
  "Search by callsign…".
- **Noun with a hyphen, verb in two words:** "your sign-up", "sign up for a shift"; "the
  check-in", "check in the radio". Never "signup" or "checkin".
- **"un-submit"**, not "unsubmit".
- **An empty value** prints "—".
- **No exclamation marks** in flash messages or error messages.

---

## Dates, Times and Prices

**CRITICAL:** Format dates with `DateTimeHelper` (`app/helpers/date_time_helper.rb`), never
`strftime` in a view. The helper carries the format, so one change reaches every page.

| Showing | Format |
|---|---|
| Date and time | `Thu Jan 8 @ 14:30` |
| Date and time in another year | `Thu Jan 8, 2026 @ 14:30` |
| Date | `Jan 8, 2026` |
| Day label | `Thu Jan 8` |
| In running copy | `January 8`, `January 8, 2026` |
| Long form | `Thursday, January 8, 2026` |
| A chip with no room | `Thu 1/8 14:30` |
| Admin logs, CSV, form field values | `2026-01-08 14:30:00`, `2026-01-08` |

- Never zero-pad the day: `Jan 8`, not `Jan 08`.
- The year goes after the date and before the time, never after the time.
- 24-hour clock everywhere.
- A timestamp already written into stored text (a record's comments column) keeps its format.
  Rewriting it would switch a record's history to a new format partway down.

**Prices:** `dollars(amount)` prints `$40`, or `$12.50` when there are cents. Never `"%g"`, and never
a `$` glued to `number_with_delimiter`: both print 12.50 as `$12.5`.

---

## Empty State Messages

Empty states should:
- Explain why the state is empty
- Suggest an action (if applicable)
- Use a friendly, helpful tone

```erb
<%# Basic empty state %>
<%= ui_empty_state "No shifts scheduled yet." %>

<%# With suggested action %>
<%= ui_empty_state do %>
  No upcoming shifts found. <%= link_to "Browse available shifts", available_shifts_path %>.
<% end %>

<%# With icon for context %>
<%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>
```

---

## Help Text

Form help text should:
- Be concise (1-2 sentences)
- Explain why the information is needed or how it will be used
- Use inline mode for brief explanations
- Use tooltip mode for longer explanations

```erb
<%# Inline help text (default) %>
<%= f.email_field :email, label: "Email", 
    help_text: "We'll send your confirmation here." %>

<%# Tooltip help text %>
<%= f.text_field :callsign, label: "Callsign", 
    help_text: "Choose a unique name that identifies you on the playa. This can be changed later.",
    help_mode: :tooltip %>
```

---

## Related Skills

- **design-rules**: Critical rules and approval workflows
- **design-foundations**: Typography and contrast requirements
- **design-components**: Component helpers for accessible UI
- **design-forms**: Form labels, help text, and error messaging
- **design-layouts**: Page structure for scannability

## Full Documentation

For complete documentation, see [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - ADHD-Friendly Design Guidelines and Language & Content Guidelines sections.
