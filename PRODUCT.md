# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Every user is a Black Rock Rangers volunteer; the roles differ, not the population. Four usage scenes
were all confirmed as primary — none of them outranks the others, so a design decision that helps one
scene at the cost of another is a real trade to raise, not a settled default.

- **On playa, mobile, harsh conditions.** Rangers and HQ staff on phones in dust and glare, with flaky
  connectivity, doing something time-critical. Contrast, target size, and glanceability are survival
  traits here, not polish.
- **Off-season administration, desktop.** VC, Mentors, Trainers, Quartermaster, Timesheet and Ticketing
  managers doing dense recordkeeping across hundreds of rows — scanning, filtering, correcting, and
  exporting. Table density and bulk action live here.
- **HQ window, shared screen.** Shift managers running the window at speed, repeating the same sign-in,
  sign-out, asset, and radio flows for hours. Repetition tolerance and error recovery matter more than
  first-run legibility.
- **Volunteer self-service (`/me`).** An ordinary Ranger checking schedule, timesheet, tickets, and
  messages a handful of times a season, with no memory of where anything was last time.

Roles are permission-shaped rather than persona-shaped: a single person routinely holds several
(Mentor + Trainer + Timesheet Management), so pages are gated by capability, not by user type.

## Product Purpose

Clubhouse 3 coordinates the volunteer lifecycle for the Black Rock Rangers: recruiting and vetting
applicants, mentoring Alphas into Rangers, training and certification, scheduling shifts, recording
worked hours and credits, issuing tickets and BMIDs, tracking assets and vehicles, and running the HQ
window during the event. Success is that a Ranger can find out what they are supposed to do and get
credit for having done it, and that the volunteers administering all of it can do so without
spreadsheets on the side.

## Positioning

It is the Rangers' system of record, not a generic volunteer-management tool. Its shape comes from
domain rules no off-the-shelf product encodes: a person's status lifecycle, position-derived
permissions, year-scoped everything, parent/child slot capacity, position credits, and a database
inherited from the Laravel application it replaced.

## Operating Context

- The application replaced a Laravel/PHP + EmberJS predecessor (Clubhouse 2), which is now a historical
  reference only: its source is not consulted. Behavior is defined by this codebase, its tests and
  `docs/FEATURES.md`. The MariaDB database came from it, which is why table names are singular.
- **Keep the function, redesign the interface.** Every capability and data rule the application has is
  preserved; the interface is free to be materially better than what it replaces.
- Nearly everything is scoped to an operating year, and the viewed year is independent of the request
  clock. Production can also be pinned to a fixed instant (Groundhog Day mode).
- Work is seasonal and spiky: a long quiet administrative off-season, then an intense on-playa week
  where the same surfaces are used under the worst possible conditions.
- Domain vocabulary is fixed and documented in `CONTEXT.md`; use those terms exactly.

## Capabilities and Constraints

- Roughly twenty functional namespaces: `/me` self-service, people management, mentoring, training,
  scheduling, shift operations, timesheets, ticketing, BMID, HQ, VC, teams/positions, asset management,
  vehicles, quartermaster, certificates, agreements, communication, and admin.
- Rails 8.1 / Ruby 4.0, Hotwire (Turbo + Stimulus), Tailwind CSS 4 with DaisyUI 5, FontAwesome 7.1,
  MariaDB 10.11. Server-rendered; no SPA framework.
- Authorization is role- and status-based (`RoleManager`, `has_role?`, status gatekeeper), with 50+
  permissions including ones composed per training position.
- 15 assignable person statuses plus deprecated ones kept only for historical rows. Status values print
  as stored — they are never titleized.
- New gems, packages, UI components, and new color styling all require explicit user approval before
  they are introduced.

## Brand Commitments

No external brand authority applies. The existing design system — the DaisyUI theme, the semantic
color tokens, and `docs/DESIGN-GUIDE.md` — is the whole of the commitment, and it is documentation of
the incumbent world rather than a fixed identity handed down from outside.

## Evidence on Hand

- `CONTEXT.md` — the domain vocabulary and the in-flight architecture seams.
- `docs/DESIGN-GUIDE.md`, `docs/UI-COMPONENTS.md`, `docs/form_helper.md` — the incumbent design system,
  helper APIs, and form builder, as built.
- `AGENTS.md` and the `design-*` skills — the standing rules the codebase is actually held to.
- `docs/FEATURES.md` — every page's route, owner, tables, tests and traps; with the code and its tests,
  the authority on behavior. Clubhouse 2's source is not evidence: it is history and is not consulted.
- A development database carrying real production data and live third-party credentials. There are no
  invented testimonials, customers, benchmarks, or pricing to draw on; this product has no marketing
  surface and none should be fabricated.

## Product Principles

1. **Four scenes, one interface.** Every surface is reachable in dust on a phone and in a spreadsheet-
   grade admin session. When they conflict, name the trade rather than quietly optimizing for the
   comfortable one.
2. **Function is kept; the interface is not.** The behavior and data rules the application has are
   preserved exactly. A page's current layout is evidence of what it must do, never a target to reproduce.
3. **The domain's words, unaltered.** Statuses, callsigns, positions, and years print as the system
   stores them. Prettifying a domain value is a defect.
4. **Permission-shaped, not persona-shaped.** A page serves whoever holds the capability, often several
   capabilities at once. Design for overlap, not for a tidy single user type.
5. **Accessibility is a requirement, not a preference.** It is never traded for density or expression.

## Accessibility & Inclusion

Binding, by the user's decree — not a soft goal that later work may negotiate away:

- ADHD-friendly patterns as specified in the design guide and `design-content` skill.
- 36px minimum touch targets on every interactive element.
- Dark mode support for every user-facing element.
- DaisyUI semantic color tokens only; raw Tailwind color classes are banned, which is what keeps
  contrast correct across both themes.
