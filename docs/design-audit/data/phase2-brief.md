# Phase 2 brief: classify the inventory against the design guidelines

You are one of ~19 subagents in a read-only UI design audit of Clubhouse 3 (Rails, ERB, Tailwind 4,
daisyUI 5). Phase 1 inventoried what the UI does. Your job now is to compare one area of it with
the written rules and return a verdict for every item on your list.

Worktree root (all paths are relative to it; never read or search outside it):
`/Users/lion/rangers/src/clubhouse3/.claude/worktrees/ui-design-audit-5712b7`

## Hard constraints

- Read-only. Change no application code and no file under `docs/` except your own output file
  `docs/design-audit/data/phase2/<your-group>.txt` (create it with the Write tool).
- No servers, tests, `bin/rails`, database access, network requests or git commands. Never touch the
  beta server (`clubhouse3.dev`): no docker, no ssh, no requests. Do not invoke any skill.
- **Every verdict rests on code you opened.** Open the cited file and read the cited lines (and
  enough around them to understand the page) before you classify. If you cannot tell from the code,
  say so in the note and classify UNCOVERED; do not guess at how it renders.

## The rules

`docs/design-audit/rules.md` lists 111 rules with IDs (BTN-01, TYPE-03, ...), each with the line
range in `docs/DESIGN-GUIDE.md` where it is written. Read `rules.md` in full first. The guide is the
only source of rules: open the cited lines of `docs/DESIGN-GUIDE.md` whenever you need a rule's
exact wording, its exceptions, or its examples. AGENTS.md, the skills and other docs are not rule
sources for this audit, even where they say more.

## The three verdicts

- **COMPLIANT**: a rule covers this and the code follows it. Cite the rule ID.
- **DIVERGENT**: a rule covers this and the code departs from it. Cite the rule ID. The note says
  what the rule says and what the code does instead, in that order, in under 40 words.
- **UNCOVERED**: no rule addresses this pattern. The note says what the pattern is. If a rule
  exists but is too vague to judge this case against, the verdict is UNCOVERED and the note starts
  with `ambiguous <RULE-ID>:` and says what the rule fails to settle. Do not guess at intent.

Only a real departure from a written rule is DIVERGENT. Your own design opinions are welcome, but
they go in `Q` rows, never in a verdict.

**Severity** (DIVERGENT only):
- `high`: a reader can see that the page differs from its siblings (different component, layout,
  colour or placement), or there is an accessibility barrier (no accessible name, status by colour
  alone, text too small to read, target under 36px).
- `medium`: the wrong component, helper or token, but it renders about the same as the right one.
- `low`: cosmetic or internal: copy casing or wording, a class choice with no visible effect, an
  inline style holding a computed number.

## Rulings so the groups agree

These follow from the rule text; apply them the same way everywhere.

- **Empty collection** shown without `ui_empty_state` (a plain `<p>`, a `div`, red text, a bare
  table cell, a hand-made box): DIVERGENT EMPTY-01, which says "always use the helper". `medium`
  when it is a box or coloured text, `low` when it is plain muted text. `ui_empty_state` wrapped in
  a table row or a section is COMPLIANT. A collection with no empty branch at all: UNCOVERED
  (`ambiguous EMPTY-01:` the rule does not say every collection needs one), unless you can see the
  page renders an empty table or list, in which case say so.
- **Empty value** in a cell or field shown as "-", "none", "N/A", a blank, or italic words instead
  of "—": DIVERGENT EMPTY-02 `low`. Words that state a fact ("Never", "Self", "not yet"):
  UNCOVERED, `ambiguous EMPTY-02:`.
- **Hand-made container** (a `div` with its own border, radius, background and padding doing a
  card's, section's or callout's job): DIVERGENT against the component's rule (CARD-01, CARD-02,
  CARD-03, ALERT-01) or STYLE-03, `medium`, unless the guide documents that exact treatment
  (message bubbles and search hits MSG-01, callsign chips, the sub-section divider FORM-10, the
  two-column wrappers LAYOUT-02).
- **Headings**: a raw `<h2>` without `heading-section`, or `<h3>`/`<h4>` without `heading-title`,
  or with its own size or weight utilities: DIVERGENT TYPE-04. A non-heading tag styled to look
  like a heading: DIVERGENT TYPE-04 only if it outweighs the section title; otherwise UNCOVERED.
- **A shared helper called with `class:`**: COMPLIANT (cite the component's rule) where the guide
  documents a `class:` option or shows that use; DIVERGENT only when the override breaks a specific
  rule (BTN-02 colours on a button, TYPE-03 `text-sm` on an empty state, and so on).
- **Status shown by colour**: DIVERGENT A11Y-01 `high` only when colour is the sole carrier (no
  text or icon says the same thing). Coloured text that is emphasis, not status: DIVERGENT COLOR-03
  `medium`. Colour plus text or icon for a real status: COMPLIANT A11Y-01.
- **Confirmation**: a destructive action confirmed by `confirm_modal` without `variant: :error`,
  or by a browser `turbo_confirm:` string or `window.confirm`: DIVERGENT MODAL-02 `medium`.
  "Are you sure…" wording: DIVERGENT MODAL-02 `low`.
- **Forms**: `form_with`/`form_tag` without `AppFormBuilder`, or `select_tag`, `text_field_tag`,
  `check_box_tag` and raw `<input>`/`<select>`/`<label>` standing in for builder fields: DIVERGENT
  FORM-01, `medium` when they borrow the builder's classes and look the same, `high` when they
  visibly differ. A hidden field, a `check_box_tag` that is a table's row selector, and a `button_to`
  that is really a one-button action are not forms in the rule's sense: judge them on their own
  rule or mark them UNCOVERED.
- **Buttons**: raw `<button>`, `button_to`/`button_tag` or `link_to ... class: "btn ..."` in place
  of a `ButtonHelper` method: DIVERGENT BTN-01 (`medium` when built from `button_classes` or the
  `btn` classes, `high` when it looks different). The client-side sort heading is the documented
  exception.
- **CSV export** on a page that has a `filter_bar`, placed anywhere but `filter_bar actions:`:
  DIVERGENT TABLE-05 `high` (placement differs from sibling pages). A second export for a
  different table on the page is allowed by the rule.
- **Breakpoints**: `md:` anywhere, or `sm:` outside a field `width:`: DIVERGENT BP-01 `low`,
  `medium` if it creates a layout tier.
- **Type size**: `text-xs` on anything a reader needs: DIVERGENT TYPE-02 `high`. `text-sm` on body
  text, table content, labels, tab labels, primary card information, an empty state or a paragraph:
  DIVERGENT TYPE-03 `medium`. Both are COMPLIANT in the uses the rules list.
- **Area wrapper helpers** (`photo_status_badge`, `application_link` and the like): open the
  helper. If it builds through the shared helper (`ui_badge`, `button_link`), COMPLIANT with that
  component's rule; otherwise judge the markup it emits.
- **No rule exists** for: plain links and link helpers, pagination, loading and busy states,
  label/value displays, tooltips, bulk selection, photos and avatars, print sheets as components,
  charts. These are UNCOVERED; describe the variant precisely so they can be ranked later.
- **Print sheets, the mail layout and test fixtures**: classify by the rules as written. The guide
  mentions print sheets only for tables (TABLE-02); email HTML is not addressed at all (UNCOVERED).
  Give fixture findings `low`.
- **Copy rules** (COPY-01 to COPY-10) are `low` unless they cause an accessibility problem.

## Task 1: a verdict for every row in your list

`docs/design-audit/data/phase2/<your-group>.review.tsv` (tab-separated: id, source, file, lines,
pattern, variant, impl, rule_hint, note) lists what needs a reader:

- `agent` rows: things the Phase 1 agent for your area recorded (one-off markup, empty states,
  overrides, and so on). The note is that agent's description.
- `census` rows: regex hits whose verdict depends on how they are used.
- `grep:candidate` rows: a rule's banned form might be here; settle it. `grep:definite` rows: the
  banned form is here unless the match is a false positive (a comment, a different meaning);
  confirm or clear it.

`rule_hint` is a suggestion, not a ruling. Return exactly one `V` line per row id.

## Task 2: sweep each page for the page-level rules

Rows cannot show what a page lacks. For every page, fragment and print template in your scope,
check these rules against the whole template (and the partials it renders that are in your scope)
and write an `F` line for each departure not already covered by a row in your list:

HERO-01 (page header is `hero_panel`), HERO-02 (description is one sentence), HERO-03, HERO-04,
HELP-01, HELP-02 (one collapsed card for explanations, placed under the stat row and above the
filter bar; no visible Q&A or reference callout on a report or log), STAT-01, STAT-02, TABLE-02
(`responsive: false` only in the listed cases, with a comment), TABLE-04, TABLE-05, BTN-03, BTN-04
(one primary action per view), BTN-05 (variant fits the role), BTN-07, MODAL-02, FORM-02, FORM-03,
FORM-07 (field widths), FORM-08, TYPE-05 (heading hierarchy), COLOR-02, COLOR-03, A11Y-01, A11Y-02
(icon-only controls with no accessible name), LAYOUT-03 (records-management pages only), COPY-03
(Title Case on every hero title, section title, callout and modal title, table heading, tab label
and button label), COPY-04 (verbs), COPY-10.

Then write one `S` line per rule above saying how many templates you checked it on and how many
departed, so the audit can say what was checked.

## Output format

Plain text, one record per line, fields separated by ` || ` (space, two pipes, space). Never put
`||` inside a field. No header, no prose, no markdown.

```
V || <row id> || <COMPLIANT|DIVERGENT|UNCOVERED> || <rule id or -> || <high|medium|low or -> || <the one line number that best shows it> || <note, under 40 words>
F || <file> || <line> || <pattern> || <short variant key> || DIVERGENT || <rule id> || <high|medium|low> || <note: what the rule says, then what the code does>
S || <rule id> || <templates checked> || <templates that depart> || <optional comment>
Q || <a design opinion or an observation that is not a rule departure>
```

- For a `grep` row (id starting with M) start the note with `pattern=<name>` and a space, where the
  name is one of: buttons, links, forms, validation, modals, tables-lists, navigation, cards,
  toasts-alerts, empty-loading, typography, color, spacing, icons, other.
- `F` pattern is one of those same names.
- One departure, one line. If the same departure repeats on several lines of one file, write one
  line and list the line numbers in the note.

## When you finish

Reply in at most 120 words: rows classified (and the split across the three verdicts), `F` findings
added, and anything you could not judge from code and would need a rendered page to confirm. Do not
paste the data.
