# Clubhouse 3

Volunteer coordination for the Black Rock Rangers. This file is the shared vocabulary for the
domain and for the seams being introduced by in-flight architecture work. Use these terms exactly;
prefer them over the listed synonyms.

## Language

### Time & year

**Present year**:
The year the present instant falls in (`Current.year`) — the live operating year.
_Avoid_: current year (ambiguous with viewed year).

**Viewed year**:
A year a user is deliberately looking at (e.g. 2024 records browsed in 2026), sourced from params via
`setup_year`. Independent of the present instant; threaded as a plain Integer, never folded into it.
_Avoid_: selected year, current year.

**Present instant** (`Current.time`):
The instant the app treats as now — Groundhog-Day aware, with `Current.year` and `Current.today` derived
from it so they cannot skew. Read it inline where it is needed; it is not threaded through call chains.
A NON-present instant travels as a plain zone-aware `now:` timestamp, and exactly one method takes one:
`SignInBlocker.check`, so `ShiftManage`'s backdated check-in evaluates slot timing and the training year
against the instant the shift actually started in (the New Year's Eve case).
_Avoid_: EventContext (rejected — it is the present instant, not the viewed year), clock service,
RequestClock (rejected — a passable clock value object; every production caller passed the default).

**Groundhog Day clock** (GHD):
Production mode pinning the app to a fixed instant via `RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME`. It is honoured
inside `Current#time`, which is why the present instant is read there and never from `Time.zone.now`.

**Pseudo-parameterised module**:
A module that accepts a `now`/`relative_to`/`year` argument and then re-reads `Current` internally, so
the parameter does not actually control behaviour. A bug to close, not a pattern to keep — `SignInBlocker`
keeps its `now:` because it genuinely honours it; every parameter that did not was deleted.

### Scheduling

**Slot**:
A single staffable shift opening for a position.

**Parent / child slot**:
Two linked slots whose signups share capacity — combined signups cannot exceed the parent's max.

**Slot capacity rule** (`Scheduling::SlotCapacity`):
The one authoritative implementation of parent/child/trainer-multiplier capacity math.
_Avoid_: re-deriving the count fold inside Management, Query, and Slot separately.

**Display rollup vs write preview**:
The two faces of the capacity rule. Display rollup = how full a linked pair is right now (raw counts, no +1).
Write preview = would adding one seat overflow, and did it just fill the last spot (+1). Same rule, different
numbers — collapsing them changes observed UI counts.

**Signup intake** (`Scheduling::Signup`):
The deep module that adds/removes one person to/from one slot — permission, force, capacity preview, the
locked transactional write, post-commit effects. Bulk per-`person_id` removals live in `Signup::Bulk`.
_Avoid_: Scheduling::Management (the scattered predecessor).

**Shift type** (`ShiftCoverageGroup`):
One kind of shift the Shift Coverage report runs for, such as Command or Green Dot. Its period positions set the
report's rows; its posts are the columns.
_Avoid_: group, coverage group (the table's name, not the word users see).

**Post** (`ShiftCoveragePosition`):
One column of the Shift Coverage report: positions read together, named by callsign or only counted.
_Avoid_: column, coverage position.

### Dashboard

**Milestones**:
The rich per-person fact bundle built once per dashboard request; also the input the task partials read.
_Avoid_: deleting it — the view still needs it.

**Dashboard facts** (`DashboardFacts`):
The small, substitutable fact set a dashboard task is evaluated against (scalars + `now`); deep for scalars,
by-reference for rich objects. These are *task facts*, distinct from the *view facts* (raw Milestones+Person)
the partials read.

**Dashboard task / Verdict**:
A task is a pure rule `facts -> Verdict`, where a Verdict (`DashboardTaskResult`) is one of nine statuses plus
a partial name. _Avoid_: the dead `#process` lifecycle method.

**Path-scoped period gating**:
Period / skip-period filtering applies only on the ranger/echelon path, never applicant/auditor — their
`skip_period` declarations are intentionally inert.

**Gate cascade**:
The applicant/auditor sequencing rule: once an earlier group is incomplete, later actionable steps demote to
not-available. Carried via `prev_completed`.

### Training

**Trainee status** (`TraineeStatus#status`):
The verdict a trainer records for one trainee at one training session: `pending` (not yet scored, the
default), `passed`, `no-show` or `not-passed`. A pending row reads exactly like no row. Only a pass trains
anyone; an entered no-show or not-passed is final at once, and the 72-hour grace period covers only a
session no one has scored. The session roster (`TrainingSession::Trainee`) and the training-history rows
carry it as `training_status`, because their `status` is the person's.
_Avoid_: pass/fail (there are four outcomes).

**Training status** (`Training::EducationInfo#status`):
A person's standing in one training for a year, derived from their trainee statuses, trainer attendance and
sign-ups: `pass`, `fail`, `pending`, `no-show` or `no-shift`. It is what the dashboard and the event-info
pages read. `no-show` is reserved for a trainer who missed teaching; a trainee no-show reads `fail`.
_Avoid_: calling it trainee status, which is the stored verdict it is derived from.

**Report verdict word**:
A word a report derives from trainee statuses for its own column or filter — People Search's
`passed`/`failed`/`pending`/`missing`, Intake's `trained`/`not passed`, Untrained People's `not_passed`
blocker, Graduation's `not-passed` eligibility. Never stored. Several share a spelling with a stored code
yet mean "anything but a pass".
_Avoid_: comparing one to a `TraineeStatus::STATUS_*` constant, or aliasing the two.

### ART mentoring

**Mentoring shift** (`ArtMentoring::Shifts::Group`):
One ART's mentee timesheet entries that started together: those signed in to the same mentee slot, or, with
no slot named, to the slot starting within an hour of the sign-in (the nearer of two). Entries matching no slot
cluster around the earliest of them. A mentor is on the mentoring shift when their own mentor-position entry
starts within that hour. The hour is these pages' own; Alpha Sign-Out and the Mentor Shift Report keep theirs.
Who is on it, needs a mentor or awaits a verdict is counted by entry, not by shift; a sign-in left open for a day
has ended. An entry with no walk needs a mentor, on shift or after.
_Avoid_: "shift" alone, which elsewhere means a slot or one timesheet entry.

**Walk** (`PersonMentor` with a `timesheet_id`):
One mentee's entry on a mentoring shift, paired with the mentors who walked with them: one row per mentor, up to
three, keyed by the mentee's `timesheet_id` and the `mentor_id`, the rows sharing one verdict and notes. A walk
outlives its entry: deleting the entry leaves the rows, shown as "Shift deleted" and still counted for each
mentor; an entry corrected onto another ART's mentee position takes its walk with it. Alpha mentor assignments are `person_mentor` rows too, with no `timesheet_id`.
_Avoid_: "assignment" for the row, which names the Mentor Assignment page and `ArtMentoring::Assignment`, the
object that writes walks.

**Mentoring verdict** (`PersonMentor#status`):
How a walk ended: `pass`, `bonk`, `self-bonk` or `pending`, shown as Passed, Bonked, Self-bonked and Pending
(`MentorHelper::RESULT_LABELS`, the one set Alpha mentoring uses too). Pending is no verdict yet: a mentee paired with
a mentor awaits a verdict, once signed out, until another is recorded. Bonked counts include self-bonks.
_Avoid_: the dashboard's Verdict (`DashboardTaskResult`), a Report verdict word and Trainee status, which are
three other things.

### Authorization

**Role gate** (`Authorization::RoleGate`):
A named, per-controller unit owning one permission's role rule, deny path, and deny message. ADMIN passes
implicitly unless `admin: false`.

**Year gate** (`Authorization::YearGate`):
A role-free current-year write gate — denies everyone, admins included, on a past year. Deliberately not a
Role gate, so the implicit-admin rule can't wrongly grant past-year writes.

**Two-tier deny**:
A deny destination that depends on a weaker permission — an editor-denied user who can still read goes back to
the inventory, otherwise home. Owned by the controller, named by `deny_to:`.

**`can?` affordance**:
The view-side helper that calls the *same* Role gate `permits?` the server guard uses, so the affordance and
the guard can never drift.
