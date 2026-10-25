# AGENTS.md

This file provides guidance to LLMs when working with code in this repository.

## Project Overview

Clubhouse 3 is a Ruby on Rails 8.1 volunteer coordination application for the Black Rock Rangers volunteer organization.
Ruby 4.0 is the language target.

The application is being translated from a Laravel/PHP codebase.

## Tech Stack

- ruby 4.0, Rails 8.1
- MariaDB 12.3 (singular table names, not plural)
- Stimulus.js + Turbo Frames/Streams (Hotwire)
- Tailwind CSS 4 + SASS
- DaisyUI 5 component library (check class names against the installed `node_modules/daisyui`; the `daisyui-blueprint` MCP tools, when the session has them, are a second opinion)
- FontAwesome v7.1 free icons

## Development Commands

```bash
# Start development server (runs Rails + Tailwind watcher via foreman)
bin/dev

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/person_test.rb

# Run a specific test by line number
bin/rails test test/models/person_test.rb:42

# Lint with RuboCop
bin/rubocop

# CSS duplication / palette ratchet (see Styles > CSS Rules)
ruby bin/css_lint.rb            # warn only
ruby bin/css_lint.rb --strict   # non-zero exit on any regression

# Security scan
bin/brakeman

# Rails console
bin/rails console

# Database migrations
bin/rails db:migrate
```

## Architecture

Look a feature up in `docs/FEATURES.md` before exploring the code. For every page, it lists the route, controller, owning class, tables and tests, plus traps checked against the code. When you move a route, owner or test, update its entry in the same commit.

### Route Structure
- Root redirects to login (`sessions#new`)
- Main user routes are namespaced under `/me` (dashboard, profile, schedule, timesheet, tickets, vehicles, messages)
- Person Management routes at `/person/:id`

### Key Directories
- `app/lib/` - Business logic modules (dashboard tasks, scheduling, ticketing, reports)
- `app/forms/` - Form objects for complex form handling
- `app/helpers/ui_components/` - Custom UI component helpers (hero_panel, ui_section, ui_card, etc.)
- `app/javascript/controllers/` - Stimulus controllers
- `app/presenters/` - Presenter objects

### Authentication & Authorization
- `ApplicationController` includes `Authentication` concern
- Uses `Current` for request-scoped state (person, session, year, roles)
- Role-based authorization via `RoleManager` and `has_role?`
- Status-based gatekeeper for access control

### UI Component System
The app has extensive custom view helpers in `app/helpers/`:
- `hero_panel` - Page headers: title, one-sentence description, back link, year selector, progress bar (stats only with an approved plan — see `design-rules`)
- `ui_section` - Content sections with titles, badges, icons
- `ui_card` - Card containers
- `ui_form` - Forms built with `AppFormBuilder` (the builder and `form_row` live in `app/helpers/form_helper.rb`)

See `docs/UI-COMPONENTS.md` for complete API reference and `docs/DESIGN-GUIDE.md` for design system.

## Code Standards

### Ruby/Rails
- Use double-quoted strings
- Use ActiveRecord instead of raw SQL
- Use shorthand hash syntax / keyword punning (e.g., instead of func(name: name) use func(name:) )
- ActiveRecord joins/where instead of raw SQL joins
- Singular database table names (not plural)
- Confirm with user before installing new gems or packages
- Start new `.rb` files with `# frozen_string_literal: true` and a blank line (97.8% of files have it; the gap is pre-convention core files)
- Strong params: Rails 8 `params.expect(x: [...])` for a form's scope, `params.expect(:x)` for one required value — no `require`/`required` call remains. A nested list of hashes needs `[[...]]` (single brackets silently drop its rows), and `expect` answers 400 when nothing permitted is left
- Optional scopes (`filter[...]`) read through `ApplicationController#scoped_params`, which returns `{}` for a bare value (`?filter=x`) instead of raising. Never on a form where an empty list clears data — use `expect` there

### Linting Gaps
`bin/rubocop` enforces **layout only** — `.rubocop.yml` disables every department and re-enables ~30 `Layout/*` cops by hand. String quoting, hash syntax, and `frozen_string_literal` are **not machine-checked**; match them by hand.

- `.erb` is excluded entirely (no ERB parser, no `erb_lint`) — never pass `.erb` paths as explicit CLI args, RuboCop lints explicit args past `Exclude` and dies parsing ERB tags
- `standard` is in the Gemfile but unused — no `.standard.yml`, and `bin/rubocop` runs RuboCop

### When Translating Laravel/PHP Code
- Assume Laravel 12 and PHP 8.4
- Source files staged for translation live in `port/` (untracked)
- Do not modify existing ActiveRecord models during translation
- Assume any required model methods will be added later. Flag these.
- Clubhouse 2 (`burningmantech/ranger-clubhouse-api` and `ranger-clubhouse-web`, checked out at `../clubhouse2/`) is a
  retired code base: read it as the source of behavior, but do not update it -- no edits, branches, commits, migrations
  or test runs -- unless explicitly told to. It will not run against this app's database schema.

### When Translating EmberJS code
- Assume EmberJS v5.6
- Source files staged for translation live in `port/` (untracked)

### Testing
- Tests use fixtures from `test/fixtures/*.yml`
- Support files loaded from `test/support/**/*.rb`
- Tests run in 8 worker processes, each on its own database (`clubhouse3_test_<n>`) and storage root
  (`tmp/storage-<n>`); `PARALLEL_WORKERS=1` runs serially. Anything a test writes outside the database
  at a fixed name needs the same per-worker split (`parallelize_setup` in `test/test_helper.rb`)
- Worktrees share those databases: run one `bin/rails test` at a time on this machine
- Cache stores differ by env: test uses `null_store` (cache code silently no-ops in tests), dev uses `memory_store`, prod uses `solid_cache` (no `delete_matched` support)

### The Beta Server
- The beta at `clubhouse3.dev` is live and serves real members. Never touch it: no command of any kind against it,
  read-only included -- no `docker --context remote-server` (not `ps`, `logs` or `inspect` either), no `ssh` to its
  host, no requests to `clubhouse3.dev` to check something
- Deploying, migrating and verifying there are the maintainer's job -- never an agent's, a plan step's or an issue's
- Take deploy facts from the repo (`docker-compose.yml`, `Dockerfile`, `bin/docker-entrypoint`) and call them
  unverified on beta

### Staging and Production on AWS
- Staging and production run on ECS in the `rangers` cluster and are deployed only by the workflows in
  `.github/workflows/`: a merge to `main` rolls staging, and `deploy.yml` promotes staging's image to production
  when an allow-listed person runs it. Never dispatch, re-run or cancel those workflows
- Never change the AWS services, task definitions or databases from a session: the task definition in AWS holds the
  environment, and a deploy swaps only the image. Read-only `aws` inventory is fine

## Skills Reference

Invoke the appropriate skill(s) BEFORE starting work.

### Task → Skill Mapping

| Task Type | Invoke Skills |
|---|---|
| Any coding task | `project-standards` |
| Frontend/view work | See [Frontend Change Protocol](#critical-frontend-change-protocol) below |
| Creating new pages or layouts | `design-layouts` + `design-components` |
| Menu/navigation changes | `menus` |
| Code review before commit | `rails-reviewer` |
| Code simplification/refactoring before commit | `simplify` |
| Visual verification of UI | `proofshot` |

## CRITICAL: Frontend Change Protocol

Before writing or modifying ANY file matching these paths, you MUST invoke the corresponding design skill(s) FIRST. 

Before changing anything, list every file you'll need and read them in one pass. Then make all edits, 
then run the tests once.This is a blocking requirement — do not skip it for "small" changes.

### Skill Dispatch Rules (mandatory)

| File Pattern | MUST Invoke Skills |
|---|---|
| `app/views/**` | `design-components` + `design-content` |
| `app/assets/stylesheets/**` | `design-foundations` |
| `app/helpers/*_helper.rb` | `design-components` + `design-forms` |
| `app/javascript/controllers/` (UI-facing) | `design-foundations` (for tokens/classes) |
| Creating any new UI pattern or component | `design-rules` (approval required before implementing) |
| Any new user-facing text, labels, or messages | `design-content` (terminology + accessibility check) |
| `app/views/layouts/**` or new page templates | `design-layouts` + `design-components` |
| `app/lib/menus.rb`, `app/lib/*menu*.rb` or sidebar/navbar items | `menus` |

## Styles

- **Main stylesheet / Tailwind entry point:** `app/assets/tailwind/application.css`
  — Tailwind directives, `@theme` / design tokens, and global CSS custom properties live here. Check this file first for any `--custom-property` definitions.
- **Base element styles:** `app/assets/stylesheets/base.css`
  — the `link` utility, base rules for `turbo-frame`, `main`, `kbd`, `p`, `a` and `button`, and the site-wide `--tw-ring-offset-color`.
- **Component styles:** `app/assets/stylesheets/components/`
  — One file per component (e.g., `card.css`, `navbar.css`). Look here for component-scoped selectors and custom properties.
- **Login screen:** `app/assets/stylesheets/login.css`
  — All styling specific to the login/sign-in screen. Do not put login styles anywhere else.
- **Accessibility / ADHD audience:** `app/assets/stylesheets/accessibility.css`

### Conventions
- When searching for a CSS custom property or selector, search the locations above only — ignore `app/assets/builds/` (compiled output), `app/assets/stylesheets/vanilla-calendar-pro.css` (third party component), `app/assets/stylesheets/lexxy-{variables,content,editor}.css` (the vendored editor, copied from the Lexxy gem: re-theme it in `components/lexxy.css`, never in place), `app/assets/stylesheets/fontawesome-subset.css` (generated by `bin/rails fontawesome:subset`)
- New component styles go in `app/assets/stylesheets/components/<component>.css`, one component per file.
- Prefer Tailwind utilities in markup; only add custom CSS when utilities can't express it after receiving approval first.

### Hard Rules

- No raw Tailwind color classes (`text-gray-700`, `bg-white`, `dark:bg-gray-800`, etc.) — use DaisyUI semantic colors (`text-base-content`, `bg-base-100`, `text-primary`, etc.) or bridge tokens (`text-body`, `bg-primary`)
- New UI components need the user's explicit approval first (`design-rules`)
- New color styling needs the user's explicit approval first (`design-rules`)
- Buttons come from `ButtonHelper` methods, not raw `<button>` HTML
- Forms use `AppFormBuilder` / `ui_form`, not raw `form_with` without the builder
- Every user-facing element works in dark mode
- Interactive elements have a 36px minimum touch target (see `design-foundations`)

### CSS Rules

Full ladder and rationale: `docs/css-dry-rules.md`. `/css:census` regenerates the report;
`ruby bin/css_lint.rb --strict` is the ratchet, with the ceiling in `.css-baseline.json`. It
measures **`app/views` and `app/helpers`** -- the two places this app keeps class strings -- and
the rules it counts by (palette colour, arbitrary value, `!important`, class-shaped string) live in
`lib/css_matchers.rb`, tested by `test/lib/css_census_matchers_test.rb`. One rule reaches
`app/javascript` too, and fails in any mode: a class name glued to a `${}` placeholder.

`docs/css-refactor/` is the record of the refactor that set those ceilings — unit by unit, with
what each measured and what was deliberately left alone. Read `plan.md` before assuming a rule is
stale: several look like dead weight and are load-bearing, and it says which. Two things it
documents are easy to relearn the hard way — **`@utility` cannot be nested**, so a file declaring
one cannot be wrapped in `@layer` or imported with `layer()`; and **`bin/css_check` cannot see a
CSS-only change**, because no markup moves and every snapshot matches. `bin/css_cascade.js` is
the instrument for that second gap.

- **Check for a daisyUI component class before writing utilities.** A hand-rolled
  `inline-flex items-center justify-center rounded-md px-4 py-2` is a `btn`. Check the class
  exists in daisyUI 5 — v4 names like `card-bordered` silently do nothing.
- **Semantic tokens only in views.** No `bg-white`, `text-gray-*`, `bg-blue-*`. The two
  surviving palette colours (`profile_photos/crop.html.erb`) are a deliberate exception.
- **Never build a class name by interpolation.** `"icon-#{color}"` and `"bg-#{c}-500"` are
  invisible to the scanner and compile to nothing. Use a frozen lookup hash with `fetch`.
  Gluing counts: in JS, `` `chip${…}` `` hides `chip` itself, so write each name whole.
- **Extract on the third occurrence**, not the second: a partial with strict locals, a helper,
  or an `@utility`. Two similar strings are usually a coincidence.
- **No inline `style=`, arbitrary values (`p-[13px]`), or `!important` without a written
  reason.** A genuinely dynamic number goes through a CSS custom property.

Class strings only compile where Tailwind scans: the `@source` list in
`app/assets/tailwind/application.css`, with automatic detection off (`source(none)`). That is
`app/views`, `app/helpers`, `app/javascript`, `app/lib` and `config`. Not `app/models`,
`app/presenters`, `app/controllers` or `app/services`, and never a `.css` file (`@apply` still
works there). A new home for class strings needs its own `@source` line. One file inside the
list is left out with `@source not`: the vendored Lexxy bundle (`app/javascript/vendor/lexxy-*.js`),
whose ordinary words compile into daisyUI classes no page uses.

### Design Documentation Reference

After invoking skills, consult these docs for detailed API signatures:
1. `docs/DESIGN-GUIDE.md` - Complete design system (colors, typography, components)
2. `docs/UI-COMPONENTS.md` - Helper method signatures and usage examples
3. `docs/form_helper.md` - Form builder API reference

### Post-Implementation

| After... | Invoke |
|---|---|
| Writing or modifying code | `rails-reviewer` (convention check) |
| Building/modifying UI | `proofshot` (visual verification) |
| Completing changes | `simplify` (code quality review) |

## Agent skills

### Issue tracker

Issues and PRDs live as local markdown under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` at the repo root; ADRs go in `docs/adr/` (created with first ADR). See `docs/agents/domain.md`.

## For planning agents

When planning new features or architectural changes, use the `layered-rails` skill for analysis:
- `/layered-rails:plan` — plan incremental adoption of layered patterns
- `/layered-rails:analyze` — full codebase architecture analysis
- `/layered-rails:review` — review code from a layered architecture perspective
- `/layered-rails:spec-test` — apply the specification test to evaluate layer placement