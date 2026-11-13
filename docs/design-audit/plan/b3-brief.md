# B3 brief: failures reported only as a toast

You are fixing a few pages of Clubhouse 3 (Rails 8.1, ERB, Hotwire, Tailwind 4, daisyUI 5) where a refused
or failed action is reported only as a flash toast. The design guide now asks for a report that stays on the
page: an error callout above the form naming what failed, or a field error from the form builder
(`docs/DESIGN-GUIDE.md`: Forms > "Forms without one model" and the validation section; Toasts). The
maintainer asked for these fixes on 2026-11-12.

Work only in `/Users/lion/rangers/src/clubhouse3/.claude/worktrees/ui-design-audit-5712b7`. The tree is
clean and every test passes.

## Read first

- `docs/design-audit/plan.md`: "Rules for every agent". Its hard limits, the skills to load, the lockf test
  command and the ledger format all apply. For this task you may also edit the controllers named in your
  assignment, and nothing else outside your views and tests.
- `docs/design-audit/follow-ups.md` section B3, and each finding's line in `plan/ledger/` and its row in
  the package `.tsv`: they say exactly what the view needs.
- `AGENTS.md` "Code Standards" (strong params, `scoped_params`, time zones) and load `project-standards`
  before touching a controller.

## How to fix one

1. Read the controller action, its view, and its existing tests. Find a sibling in the same area that
   already reports failure on the page and copy its shape (`teams_positions/bulk_lookup` sets an instance
   variable the view draws as `ui_callout_box :error`; model-backed forms re-render with the errors).
2. Change as little as the report needs. The action still refuses the same inputs, saves the same things,
   redirects to the same places and answers with the same status codes on success. On failure it renders
   the page with the report: `status: :unprocessable_content` for a submitted form (a 422 render is a Turbo
   morph: fine), unless the action is a GET.
3. Keep the wording of the existing message unless it breaks the guide (whole sentence, ends in a period,
   no "successfully", no "!"). Never put request input into markup unescaped.
4. A flash that follows a redirect on success stays a flash. Only the failure path changes.
5. Write or update a controller test for each failure path: it asserts the callout or field error is in
   the response and that nothing was saved. Do not delete an existing assertion to get green; change one
   only where it pinned the toast you replaced.
6. No new helpers, components, routes, migrations, gems or model changes. If a fix needs one, stop and
   record why.

Never exercise live services (Twilio, mail, Salesforce, Moodle) outside the test suite's own stubs. Dev
database rows are read-only; `bin/rails runner` and servers are off limits. No git writes.

## Finish

Rewrite each finding's ledger line to `FIXED` (or leave it `BLOCKED` with the exact reason). Run the tests
for the controllers you changed with the lockf command, plus `mise exec -- bin/rubocop <ruby files>` and
`mise exec -- bundle exec herb analyze app/views`.

Report in under 200 words: per finding, what the controller now does on failure and what the page shows;
tests added; anything whose behaviour changed beyond the failure report; anything left blocked.
