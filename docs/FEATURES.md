# Feature Map

Where each feature lives, traced along the path of its request: route → controller → the class that owns the logic → the tables it reads and writes → the tests that cover it. Look a feature up here before opening files. For conventions and step-by-step "where to change X" recipes see [codebase-map.md](codebase-map.md); the domain vocabulary is in [CONTEXT.md](../CONTEXT.md).

## Reading an entry

| Field | Meaning |
|---|---|
| `### Heading` | The menu item or page title. Generic names carry their area (`Person › Messages`); a code name that differs follows in parentheses. |
| Reach it | `VERB /path` as `bin/rails routes` prints it, then the menu path (Category › Section › Item, from `app/lib/menus.rb`) or the page that links to it. |
| Gate | Who gets in: `Role` constants without the `Role::` prefix, or a status, setting or `authorize_*` check. `(menu: …)` marks a menu whose visibility differs from the controller's gate. |
| Controller | Controller file(s) and the actions they handle. |
| Owner | Where the business logic lives. `(not X)` names a look-alike that is the wrong place. |
| Touches | Table names as in `db/schema.rb` — each model's `self.table_name`, mostly singular, some irregular. `(w)` means the feature writes it. |
| Verify | Tests that exercise the feature, most direct first. `none` means nothing does. |
| Trap | Behaviour, checked against the code, that bites anyone who reads only the obvious path. |

[Shared engines](#shared-engines) replace Reach it, Gate and Controller with `Used by:`. [Background jobs & mail](#background-jobs--mail) use `Runs:` and `Job:`.

Paths are relative to the repository root. To find a feature, grep this file for its URL, menu title, controller, class or table. When you move a route, owner or test, update its entry in the same commit.

## Contents

- [Shared engines](#shared-engines) (44)
- [Sign-in, accounts & site chrome](#sign-in-accounts--site-chrome) (16)
- [My Clubhouse: dashboard & profile](#my-clubhouse-dashboard--profile) (11)
- [My Clubhouse: messages, announcements & info](#my-clubhouse-messages-announcements--info) (9)
- [My Clubhouse: schedule, tickets, timesheet & vehicles](#my-clubhouse-schedule-tickets-timesheet--vehicles) (9)
- [Person Manage: account & identity](#person-manage-account--identity) (15)
- [Person Manage: communication, membership & training](#person-manage-communication-membership--training) (13)
- [Person Manage: event records](#person-manage-event-records) (15)
- [HQ Window](#hq-window) (12)
- [Training: sessions](#training-sessions) (9)
- [Training: reports & follow-up](#training-reports--follow-up) (11)
- [Mentoring: prospectives & alphas](#mentoring-prospectives--alphas) (8)
- [Mentoring: the alpha shift](#mentoring-the-alpha-shift) (6)
- [Scheduling: slots & position credits](#scheduling-slots--position-credits) (6)
- [Scheduling: reports](#scheduling-reports) (12)
- [Shift Operations](#shift-operations) (7)
- [Timesheets](#timesheets) (13)
- [People, Certificates & Agreements](#people-certificates--agreements) (13)
- [Teams & Positions](#teams--positions) (12)
- [Volunteer Coordinators](#volunteer-coordinators) (14)
- [Ticketing](#ticketing) (14)
- [BMID](#bmid) (7)
- [Assets & Vehicles](#assets--vehicles) (9)
- [Pogs](#pogs) (2)
- [Quartermaster](#quartermaster) (7)
- [Communication](#communication) (10)
- [Admin](#admin) (17)
- [Background jobs & mail](#background-jobs--mail) (19)

## Shared engines

Engines that page entries name as Owner. Every controller except `Sso::ApiController` (an `ActionController::API`) inherits `ApplicationController`, whose before_actions (sign-in, status gate, role gate, menu context) run before any concern's. A page picks its viewed year with `setup_year`; `Current.year` is always the present year.

### Request lifecycle & authorization gates
Used by: every controller (`ApplicationController` before_actions `require_authentication`, `set_current_user`, `confine_past_prospective`, `authorization_status_gatekeeper`, `authorization_role_gatekeeper`, `build_menu_items`, after_action `track_page_visit`); `authorize_role` / `authorize_status` / `deny_status` in every area; `authorize_ability` + `can?` on Person › Overview (Delete Account, Mark On Site / Off Site), Edit Callsign (release), Edit Permissions, Agreements, Assets, Awards, Certifications, Pogs, Timesheets (and its missing requests), Training, Vehicles, Administration › Event Dates, Permissions, RBS Alerts, Communication Management › Ranger Broadcast history, Mentoring › Alpha Sign-Out, VC › Reserved Handles, Vehicles › Vehicle Registry and Vehicle Paperwork, and the Asset Management pages; `require_current_year_for` on Person › Agreements, Assets, Training and Vehicles; `scoped_params` for optional `filter[...]` scopes
Owner: `ApplicationController` + `Authentication` (`app/controllers/application_controller.rb`, `app/controllers/concerns/authentication.rb`), `AuthorizeHelper` (`app/helpers/authorize_helper.rb`), `Authorization::RoleGate` / `YearGate` / `Context` (`app/lib/authorization/`)
Touches: `sessions` (w), `person` (w), `person_page_visit` (w), `action_logs` (w)
Verify: `test/lib/authorization/gates_test.rb`, `test/controllers/concerns/person_concern_test.rb`, `test/controllers/admin/error_logs_controller_test.rb`, `test/controllers/bmid/badges_controller_test.rb`, `test/controllers/sessions_controller_test.rb`
Trap: `authorize_role` only sets a class_attribute, so a later call (concern or subclass) replaces the list rather than narrowing it, and it takes no `only:`/`except:` — gate per action with `authorize_ability` or a before_action calling `not_authorized_redirect`.
Trap: `ApplicationController` never runs `setup_year`: without `before_action :setup_year` (`self.year_floor` before 1998, `self.allow_all_years` for "All") `@year` stays nil; `require_current_year_for` needs `current_year_selected?`, only in `PersonConcern`.

### Present instant & Groundhog Day server (Current, GroundHogDay)
Used by: everything reading `Current.time` / `Current.year` / `Current.today` / `Current.person`; `prevent_if_ghd_server` in Communication Management › Ranger Broadcast (send and retry), Administration › Clubhouse 1 Log, Me/Person › Alerts SMS number and verification, Me › Online Course account setup; `Current.is_ghd_server?` in Administration › Online Courses LMS lookups (`Admin::OnlineCoursesController#moodle_lookup`); `ApplicationMailer#hold_mail_on_training_server`; `RoleManager` (NDA exemption); `RegisterController` (registration closed); `bin/rails clubhouse:groundhog_day` and the recurring `GroundHogDay.reload_training_database!` (`config/recurring.yml`)
Owner: `Current` (`app/models/current.rb`), `GroundHogDay` (`app/lib/ground_hog_day.rb`)
Touches: `timesheet` (w), `timesheet_note` (w), `timesheet_log` (w), `timesheet_missing` (w), `person` (w), `person_on_site` (w), `person_slot` (w), `slot` (w), `position` (w), `position_credit` (w), `person_event` (w), `person_role` (w), `trainee_status` (w), `asset` (w), `person_asset` (w), `motd` (w), `setting` (w)
Verify: `test/models/current_test.rb`, `test/lib/ground_hog_day_test.rb`, `test/mailers/application_mailer_test.rb`, `test/lib/role_manager_test.rb`, `test/controllers/register_controller_test.rb`
Trap: `Time.zone.now` / `Date.today` ignore `RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME` — use `Current.time` / `Current.year` / `Current.today`; setting that variable at all (even unparseable) makes `Current.is_ghd_server?` true, which holds every email.
Trap: `Current.reset` does not clear `Current.person`, `session` or `roles_manager` (plain `attr_accessor`s) — a "nobody signed in" test sets `Current.person = nil`.

### Role resolution (RoleManager)
Used by: every request (`ApplicationController#set_current_user` → `Current.roles_manager`, read by `Current.has_role?`, menus and every gate); `Person#has_role?` for anyone but the viewer; Person › Overview (`PersonController`); Admin › Permissions (`RoleManager.purge_all`); cache purges from `PersonRole`, `PersonTeam`, `Timesheet`, `TraineeStatus`, `TrainerStatus`, `Slot`, `Document`, `Setting`, `RosterAction`
Owner: `RoleManager` (`app/lib/role_manager.rb`), `PersonPermissionPresenter` (`app/presenters/person_permission_presenter.rb`)
Touches: `person_role`, `person_position`, `position`, `position_role`, `person_team`, `team_role`, `timesheet`, `trainee_status`, `trainer_status`, `person_event`, `document`, `setting`
Verify: `test/lib/role_manager_test.rb`, `test/models/role_cache_invalidation_test.rb`, `test/presenters/person_permission_presenter_test.rb`, `test/controllers/person/permissions_controller_test.rb`
Trap: Role sets are cached per person and present year (`RoleManager.cache_key`) with no expiry, and the test cache is `:null_store` — a new grant/revoke path must call `RoleManager.purge_person`, tested inside `CacheTestHelper#with_cache_store`.
Trap: An Event Management holder without Tech Ninja or a signed NDA gets an empty role set while the dept NDA document exists (not on the Groundhog Day server) — ask `has_raw_role?`, as `Agreements.can_sign_document?` does, for the pre-wipe set.

### Settings (feature switches)
Used by: Administration › Admin Menu › Settings (`Admin::SettingsController`); menu items with `visible_if: { setting: }`; `HqConcern` (`HQ_WINDOW_INTERFACE_ENABLED`); `RoleManager` (setting-gated and conferred roles); `Milestones`; `Rbs` sandboxes; most reports and dashboards
Owner: `Setting` (`app/models/setting.rb`)
Touches: `setting` (w)
Verify: `test/models/setting_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: `Setting.get_value` raises `ArgumentError` for a name missing from `Setting::DESCRIPTIONS` — add the entry (type, default) before any code reads a new switch.
Trap: Saving a setting in `RoleManager::ROLE_SETTINGS` runs `RoleManager.purge_all`, which is `Rails.cache.clear` — the whole cache, not just role sets.
Trap: `Setting.fresh_value` reads past the cache; `Rbs.email_mode` uses it for `BROADCAST_MAIL_SANDBOX` and `BROADCAST_MAIL_TEST_ADDRESS`, because a cached copy can lag a save (a reader between the save and its commit caches the old row again) and a send must see the switch as it is.
Trap: the cached value is cleared `after_commit`, never `after_save`: a reader between a delete and the commit would cache the old row again in production's shared `solid_cache`, with no expiry (a broadcast sandbox turned on would not take). Inside an open transaction, a read can still return the old value; the test cache is `:null_store`, so test it inside `CacheTestHelper#with_cache_store`.
Trap: `BROADCAST_MAIL_TEST_ADDRESS` is a string setting with its own validation (`Setting#check_test_address_pattern` → `Rbs.test_address`): one address with exactly one `?` before the @ that, with an id in its place, passes the address rule, `EmailAddresses.sendable?`, which `Rbs.sendable_address?` calls (AWS's documented form: a dot in the domain and a last label of 2+ letters or `xn--` punycode, so `rbs-?@invalid` is refused). Saving anything else is refused, so `Rbs.email_mode` only sees `:misconfigured` after a direct database write.
Trap: An integer setting cleared on the edit page stores `""`, which reads as 0, not its `:default` — a reader that needs the default must treat a non-positive value as unset (`Rbs.ses_batch_size` for `SES_MAX_SEND_RATE`).

### Navigation menus & mega menu
Used by: every layout sidebar (`sidebar_render_menu(Menus::X, @menu_context)` in `app/views/layouts/`), the navbar Account menu (`Menus::USER`), the mega menu and favorites of links and categories (`Me::MenuController`, `Me::FavoritesController` via `MegaMenuConcern`), per-position training categories (`TrainingMenu`), visit tracking (`ApplicationController#track_page_visit`, extended by `Training::BaseController#tracked_page?`)
Owner: `Menus` (`app/lib/menus.rb`), `MenuBuilder` (`app/lib/menu_builder.rb`), `MegaMenu` + `MegaMenuConcern` (`app/lib/mega_menu.rb`, `app/controllers/concerns/mega_menu_concern.rb`)
Touches: `person_favorite` (w), `person_page_visit` (w), `team_manager`, `setting`
Verify: `test/lib/menu_category_gate_test.rb`, `test/controllers/me/menu_controller_test.rb`, `test/helpers/menu_helper_test.rb`, `test/models/person_favorite_test.rb`, `test/lib/people_menu_test.rb`
Trap: `visible_if` only hides a link, never gates the page — change the controller gate with it; a category's `visible_if` is ANDed with its items', and `MegaMenuConcern#build_mega_menu` hard-deletes (`PersonFavorite.prune_stale!`) favorites no longer visible; a category's star is keyed `category:` + its `title.parameterize`, so renaming a category drops everyone's star for it.
Trap: `MenuBuilder.visible?` checks `roles:` against the viewer (`Current.has_role?`), and a `use_person: true` menu (PERSON, HQ) resolves routes with `@person`, raising `ArgumentError` if the page never set it.

### Person pages & HQ Window shell (PersonConcern, HqConcern)
Used by: every Person › page (`PersonConcern`: subject person + `VIEW_ROLES` gate), every HQ › page (`HqConcern`: `ADMIN`/`SHIFT_MANAGEMENT`, setting `HQ_WINDOW_INTERFACE_ENABLED`, shell data), callsign links to person pages in reports and logs across most areas (`LinkHelper#person_display_link` → `can_view_person_page?`, which reads `PersonConcern::VIEW_ROLES`)
Owner: `PersonConcern` (`app/controllers/concerns/person_concern.rb`), `HqConcern` (`app/controllers/concerns/hq_concern.rb`)
Touches: `person`, `person_event`, `person_banner`, `email_suppression`, `person_message`, `person_photo`, `timesheet`, `setting`
Verify: `test/controllers/concerns/person_concern_test.rb`, `test/controllers/hq/index_controller_test.rb`, `test/controllers/teams_positions/roster_management_controller_test.rb`
Trap: Re-calling `authorize_role` on a person page replaces `VIEW_ROLES`, often with other roles (`EDIT_ACCESS_DOCS`, `EDIT_BMIDS`, `INTAKE`, `REGIONAL_MANAGEMENT`, `TIMESHEET_MANAGEMENT`, `VIEW_PII`); `LinkHelper#can_view_person_page?` still reads `VIEW_ROLES`.
Trap: the email banner in `person/_banners` (person page and HQ shell) reads the `email_suppression` row for the person's current address (`@email_suppression` from `PersonController#show`, `@hq_email_suppression` from `HqConcern#load_hq_shell`, looked up once), never `person.is_bouncing`; it names no address, since not every page role may see contact details, and offers the clear button only to `Current.has_role?([ADMIN, TECH_NINJA])` (`Person::EmailSuppressionHelper`) — `PersonConcern#can_edit_permissions?` does not exist on HQ controllers. A row stays when the address changes, so the banner goes with the old address and comes back if the person returns to it.
Trap: `HqConcern#load_hq_shell` consumes `session[:hq_warned_person_id]` — turbo-stream, redirect and download actions must `skip_before_action :load_hq_shell`; prefix new shell ivars `hq_`, since shared-concern pages assign `@summary` and friends.

### Person event info (PersonEventInfo)
Used by: every HQ › page shell (`HqConcern#load_hq_shell` → `@event_info`, read by HQ › Shift Check In/Out, On-Site Registration and Training / ARTs), Me › Operational Summary (`Me::OperationalSummaryController`), Person › Training / ARTs (`Person::TrainingController`)
Owner: `PersonEventInfo` (`app/lib/person_event_info.rb`), `Training.retrieve_education` (`app/lib/training.rb`), `VehicleEligibility` (`app/lib/vehicle_eligibility.rb`)
Touches: `person_position`, `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `provision`, `bmid`, `event_dates`, `timesheet`, `person_online_course`, `vehicle`, `person_event`, `person_team`, `setting`
Verify: `test/controllers/hq/training_controller_test.rb`, `test/controllers/person/training_controller_test.rb`, `test/controllers/hq/site_registration_controller_test.rb`, `test/controllers/hq/shift_manage_controller_test.rb`
Trap: `PersonEventInfo.find_for_person_year` assumes In-Person Training (`Position::TRAINING`) is among the person's training positions: with none it `Position.find`s that id (no fixture; tests create it), with only an ART one `delete_at(nil)` raises TypeError.
Trap: Radio eligibility (`Provision.retrieve_usable_for_person_ids`), `event_period` (`EventDate.retrieve_event_ops_period`) and `is_binary` (`Timesheet.person_binary?`) ignore the year — a past-year caller (only `Person::TrainingController`) must not read them.

### Dashboard tasks (Milestones → DashboardFacts → Dashboard)
Used by: Me › Clubhouse Dashboard (`Me::DashboardController`), Person › Dashboard (`Person::DashboardController`)
Owner: `Dashboard` (`app/lib/dashboard.rb`), `DashboardTask` + `DashboardTasks::*` (`app/lib/dashboard_task.rb`, `app/lib/dashboard_tasks.rb`, `app/lib/dashboard_tasks/`), `Milestones` → `DashboardFacts` (`app/lib/milestones.rb`, `app/lib/dashboard_facts.rb`)
Touches: `person_event`, `person_slot`, `slot`, `position`, `person_position`, `timesheet`, `person_photo`, `survey`, `trainee_status`, `person_online_course`, `access_document`, `provision`, `bmid`, `vehicle`, `document`, `event_dates`, `setting`
Verify: `test/lib/dashboard_test.rb`, `test/lib/dashboard_tasks/partial_coverage_test.rb`, `test/controllers/me/dashboard_controller_test.rb`, `test/controllers/person/dashboard_controller_test.rb`, `test/lib/dashboard_facts_test.rb`
Trap: A task's `partial:` (`app/views/dashboard_tasks/_<name>.html.erb`) is checked only by `test/lib/dashboard_tasks/partial_coverage_test.rb`; unit tests never render — render-test with a `DashboardFactsFactory` archetype (bonked, past-prospective: no groups).
Trap: `period` / `skip_period` apply only on the ranger/echelon path (`Dashboard#process_step_group`), inert on applicant and auditor groups; a new task runs only once listed in `RANGER_STEPS`, `ECHELON_STEPS`, `APPLICANT_TASK_GROUPS` or the auditor step lists.

### Signup intake (Scheduling::Signup)
Used by: Me/Person/HQ › Schedule / Sign-Ups (`AvailableSignUpsConcern#create`/`#destroy`, `ScheduleConcern#destroy`), Training › Sessions roster (`Training::Sessions::RostersController`), Mentoring › Alpha Schedule roster (`Mentoring::AlphaSchedule::RostersController`); bulk future-signup removal on status change (`PersonStatusManagement`) and position revocation (`PersonPosition`) via `Signup::Bulk`
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`; `Signup::Bulk`, `ActiveRecordSlotStore`, `Verdict`, `EmailNotification` also in `app/lib/scheduling/`), `Scheduling::SlotCapacity` (`app/lib/scheduling/slot_capacity.rb`) (not `Scheduling::Management`, a forwarding shim for old tests)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `person` (w), `person_position`, `position`, `person_event`, `person_online_course`, `document`, `setting`
Verify: `test/lib/scheduling/signup_characterization_test.rb`, `test/lib/scheduling/capacity_characterization_test.rb`, `test/lib/scheduling/signup_bulk_characterization_test.rb`, `test/lib/scheduling/verdict_test.rb`, `test/controllers/me/available_sign_ups_controller_test.rb`
Trap: `slot.signed_up` is a counter only `Scheduling::ActiveRecordSlotStore` maintains — a direct `PersonSlot.create!` (tests too) leaves it stale; reports count `person_slot` rows instead.
Trap: `can_force_schedule_change` reads the actor's roles (`Current.has_role?`), not the subject's: Admin anywhere, Mentor on Alpha slots, the composed ART trainer role on ART slots; In-Person Training: Trainer force-adds, Trainer or Training Seasonal force-removes.

### Schedule queries (Scheduling::Query, Permission, Summaries)
Used by: `ScheduleConcern` and `AvailableSignUpsConcern` (Me/Person/HQ › Schedule / Sign-Ups), `Me::ScheduleController`, `Milestones`, `ShiftManageConcern` and `Hq::ShiftManageController` (starting slots), `Infrastructure::SmsController` (next shift), `Timesheet`, `TicketsAndProvisionsProgress`, `BurnWeekendShiftRecommendation`
Owner: `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Scheduling::Permission` (`app/lib/scheduling/permission.rb`; requirement codes and labels in `app/lib/scheduling.rb`), `Scheduling::Summaries` (`app/lib/scheduling/summaries.rb`)
Touches: `slot`, `person_slot`, `position`, `person_position`, `position_credit`, `timesheet`, `event_dates`, `person_online_course`, `person_photo`, `setting`
Verify: `test/lib/scheduling/query_test.rb`, `test/lib/scheduling/permission_test.rb`, `test/controllers/me/schedule_controller_test.rb`
Trap: `Scheduling::Query.find_for_query` can return a slot whose position the person no longer holds while the sign-up remains — a listed sign-up does not prove the position is held.
Trap: `Scheduling::Query.multiple_enrollments?` is true after one sign-up for the position and year; `prevent_multiple_enrollments` training slots go through `can_join_training_slot?`: at most two sessions, in one session group (`Slot.part_of_session_group?`).

### Schedule / Sign-Ups pages (ScheduleConcern, AvailableSignUpsConcern)
Used by: Me › Schedule / Sign-Ups (`Me::ScheduleController`, `Me::AvailableSignUpsController`), Person › Schedule / Sign-Ups (`Person::SchedulingController`, `Person::AvailableSignUpsController`), HQ › Schedule / Sign Ups (`Hq::SchedulingController`, `Hq::AvailableSignUpsController`)
Owner: `ScheduleConcern` (`app/controllers/concerns/schedule_concern.rb`), `AvailableSignUpsConcern` (`app/controllers/concerns/available_sign_ups_concern.rb`)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `position`, `person_position`, `position_credit`
Verify: `test/controllers/me/schedule_controller_test.rb`, `test/controllers/me/available_sign_ups_controller_test.rb`, `test/controllers/person/scheduling_controller_test.rb`, `test/controllers/hq/scheduling_controller_test.rb`, `test/controllers/hq/available_sign_ups_controller_test.rb`
Trap: Both concerns set `@person ||= current_user` — Person and HQ controllers must include `PersonConcern` / `HqConcern` first, or the operator is scheduled instead of the subject.
Trap: `ScheduleConcern#destroy` reports a failed removal under the `success:` flash ("The shift could not removed.") — a failure test must not expect `flash[:error]`.

### Event qualifications (TicketsAndProvisionsProgress)
Used by: Me › Schedule and Me › Timesheet qualifications (`Me::ScheduleController`, `Me::TimesheetController`), Person › Schedule qualifications (`Person::SchedulingController`) and HQ › schedule qualifications (`Hq::SchedulingController`), all through `QualificationsConcern#qualifications`; HQ › Tickets & Provisions progress (`Hq::TicketsProvisionsController`)
Owner: `TicketsAndProvisionsProgress` (`app/lib/tickets_and_provisions_progress.rb`), `QualificationsPresenter` (`app/presenters/qualifications_presenter.rb`), `QualificationsConcern` (`app/controllers/concerns/qualifications_concern.rb`)
Touches: `timesheet`, `position_credit`, `person_slot`, `slot`, `position`, `event_dates`, `setting`
Verify: `test/controllers/me/qualifications_controller_test.rb`, `test/presenters/qualifications_presenter_test.rb`, `test/controllers/person/scheduling_controller_test.rb`, `test/controllers/hq/tickets_provisions_controller_test.rb`
Trap: `TicketsAndProvisionsProgress` always computes the present year (`Current.year`), whatever year the schedule or timesheet page shows.

### Ticketing package & window (TicketAndProvisionsPackage, TicketingInfo)
Used by: Me › Tickets & Stuff (`Me::TicketsController`), Person › Tickets & Provisions (`Person::TicketsProvisionsController`), dashboard ticketing tasks (`Milestones` → `ticketing_package`); `TicketingInfo` alone on Person › New / Edit Access Document (`Person::AccessDocumentsController`), Person › BMID (`Person::BmidsController`), BMID › Manage BMIDs edit mode and the badge editor (`Bmid::ManageController`, `Bmid::BadgesController`)
Owner: `TicketAndProvisionsPackage` (`app/lib/ticket_and_provisions_package.rb`), `TicketingInfo` (`app/lib/ticketing_info.rb`), `Provision.build_package` (`app/models/provision.rb`)
Touches: `access_document`, `provision`, `timesheet`, `position_credit`, `person_event`, `setting`
Verify: `test/controllers/me/tickets_controller_test.rb`, `test/controllers/person/tickets_provisions_controller_test.rb`, `test/lib/dashboard_tasks/ticketing_open_test.rb`, `test/lib/dashboard_tasks/ticketing_closed_test.rb`, `test/controllers/me/dashboard_controller_test.rb`
Trap: `TicketAndProvisionsPackage.new` always describes the present year (credits from last year's timesheets, `@year_earned = Current.year - 1`; this year's `person_event` dates; all current access documents and usable provisions) — never hand it a viewed year.
Trap: `TicketingInfo#sap_selectable_dates` silently returns no dates, rather than raising, unless setting `TAS_SAP_DATE_RANGE` is a valid "DD-DD" span of August days.

### Shift check in/out (ShiftManage, SignInBlocker)
Used by: Me › Self Check In/Out (`Me::ShiftManageController`), HQ › Shift Check In/Out (`Hq::ShiftManageController`), Person › Timesheets (`Person::TimesheetsController`), all through `ShiftManageConcern`; Shift Operations › Roll Call, Mass Sign-Out, Bulk Sign In/Out (`BulkSignInOut`); Mentoring › Alpha Sign-Out (`AlphaSignOut`); `PersonPosition` eligibility (`SignInBlocker`)
Owner: `ShiftManage` (`app/lib/shift_manage.rb`), `SignInBlocker` (`app/lib/sign_in_blocker.rb`), `ShiftManageConcern` (`app/controllers/concerns/shift_manage_concern.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_event` (w), `person` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_pod` (w), `pod` (w), `action_logs` (w), `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `setting`
Verify: `test/lib/shift_manage_test.rb`, `test/lib/sign_in_blocker_test.rb`, `test/controllers/me/shift_manage_controller_test.rb`, `test/controllers/hq/shift_manage_controller_test.rb`, `test/controllers/person/timesheets_controller_test.rb`
Trap: `ShiftManage.sign_in` passes the backdated check-in time to `SignInBlocker.check(now:)` so slot timing and training year are judged at the real start (the New Year's Eve case) — do not swap in `Current.time`.
Trap: `ShiftManage.sign_off` ends with `convert_inactive_to_active` (Inactive → Active plus an email, unless the shift is training or Cheetah Cub) — a new shift-closing path must call it too, as `BulkSignInOut` does.

### Timesheet review & corrections (TimesheetManagement)
Used by: Me › Timesheet (`Me::TimesheetController`, `Me::MissingRequestsController`, `Me::EventSummaryController` via `TimesheetConcern` and `TimesheetDashboardConcern`), HQ › Timesheet / Corrections (`Hq::TimesheetsController`, `Hq::MissingRequestsController` via `HqTimesheetConcern`), Person › Timesheets (`Person::TimesheetsController`, `Person::MissingRequestsController` via `PersonTimesheetConcern`); `ShiftManage` and `TimesheetMissingReview` (`TimesheetManagement`)
Owner: `TimesheetManagement` (`app/lib/timesheet_management.rb`), `TimesheetCorrectionsConcern` (`app/controllers/concerns/timesheet_corrections_concern.rb`), `MissingRequestsConcern` (`app/controllers/concerns/missing_requests_concern.rb`)
Touches: `timesheet` (w), `timesheet_note` (w), `timesheet_missing` (w), `timesheet_missing_note` (w), `timesheet_log` (w), `person_event` (w), `position`, `person_position`
Verify: `test/controllers/me/timesheet_controller_test.rb`, `test/controllers/hq/timesheets_controller_test.rb`, `test/controllers/me/missing_requests_controller_test.rb`, `test/controllers/hq/missing_requests_controller_test.rb`, `test/controllers/person/timesheets_controller_test.rb`
Trap: `TimesheetManagement.unconfirm_timesheet` does nothing unless the entry's `on_duty` year is the present year — changing a past-year entry never clears that year's `timesheet_confirmed` flag.
Trap: `HqTimesheetConcern` pins `@year` to `Current.year`, ignores `TIMESHEET_CORRECTION_ENABLE`, gates on the subject's status (`require_subject_can_use_timesheets`), and must include `HqConcern` before `TimesheetConcern` or /me defaults shadow its overrides.

### Event-period hours & credits (EventSummaryReport, EventSummary)
Used by: Me › Event Summary (`Me::EventSummaryController`), the HQ shell's earned column and HQ › Timesheet (`HqConcern#build_timesheet_summary`, `Hq::TimesheetsController`), Person › Timesheets and Person › Swag (`Person::TimesheetsController`, `Person::SwagController`), event qualifications (`TicketsAndProvisionsProgress`); `EventSummary` directly in schedule summaries (`Scheduling::Summaries`) and Timesheets › Hours & Credits (`HoursCreditsReport`)
Owner: `EventSummaryReport` (`app/lib/reports/event_summary_report.rb`), `EventSummary` (`app/lib/event_summary.rb`)
Touches: `timesheet`, `position`, `position_credit`, `event_dates`
Verify: `test/lib/reports/event_summary_report_test.rb`, `test/lib/reports/hours_credits_report_test.rb`, `test/controllers/me/event_summary_controller_test.rb`, `test/controllers/hq/timesheets_controller_test.rb`, `test/controllers/person/timesheets_controller_test.rb`
Trap: With no `event_dates` row for the year, `EventSummaryReport.execute` (`build_no_event_dates_response`) books every hour and credit to the event period with `counted_duration: 0`, so the HQ shell's earned hours read 0 until Admin › Event Dates has that year.
Trap: An entry still on duty counts up to `Current.time` (`row.off_duty || Current.time`), so totals grow between page loads while a shift is open.

### Position credit rates (PositionCredit)
Used by: every credit figure — `Timesheet#credits` and `TimesheetMissing#credits` (Me/Person/HQ timesheets, ticketing package), `Slot` and `Scheduling::Query` (Me/Person/HQ schedule and sign-ups), `EventSummary` (event summaries, Timesheets › Hours & Credits), Timesheets reports through `TimesheetCredits` (Timesheet Totals, Timesheets by Callsign / Position, Correction Requests, Sanity Checker, Mass Sign-Out), Scheduling › Credit Timeline (`Scheduling::CreditTimeline`); written by Scheduling › Position Credits and Copy Position Credits
Owner: `PositionCredit` (`app/models/position_credit.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`)
Touches: `position_credit` (w), `position`
Verify: `test/models/position_credit_test.rb`, `test/lib/scheduling/credit_timeline_test.rb`, `test/lib/reports/hours_credits_report_test.rb`, `test/lib/reports/timesheet_totals_report_test.rb`, `test/controllers/scheduling/position_credits_controller_test.rb`
Trap: `PositionCredit.compute_credits` (behind `Timesheet#credits`, `TimesheetMissing#credits`, `Slot`) copies the year's whole cache entry per call, even after `warm_year_cache` — price large row sets via `TimesheetCredits` or `PositionCredit.bulk_compute_credits`.
Trap: The year's cache entry fills one position at a time (missing ones price 0.0) — read the whole year with `PositionCredit.year_credits`; only `after_commit :flush_year_caches` clears it, so `update_all` / `insert_all` on `position_credit` leave stale rates.

### Work history (WorkHistoryConcern)
Used by: Me › Work History (`Me::WorkHistoryController`, `/me/timesheet/work-history`), Person › Work History (`Person::WorkHistoryController`), Training Session › Work History (`Training::Sessions::WorkHistoriesController`, which calls `WorkHistoryReport` without the concern)
Owner: `WorkHistoryReport` (`app/lib/reports/work_history_report.rb`), `WorkHistoryConcern` (`app/controllers/concerns/work_history_concern.rb`)
Touches: `timesheet`, `position`
Verify: `test/controllers/me/work_history_controller_test.rb`, `test/controllers/person/work_history_controller_test.rb`
Trap: The concern declares no gate and needs `@person` set before its `load_work_history` before_action; /me relies on `TimesheetDashboardConcern`'s `authorize_status`, /person on `Person::WorkHistoryController`'s own `authorize_role`.
Trap: Both index pages draw the hours matrix, or its empty state when no entry counts, from `app/views/common/work_history/_matrix.html.erb`, which links with `url_for(action:)` like the drill-downs' back links, so it only renders under a controller that includes the concern. The training dialog keeps its own copy, whose links load into its `wh-detail` frame.

### Clubhouse messages mailbox (MessagesConcern)
Used by: Me › Messages (`Me::MessagesController`), Person › Messages (`Person::MessagesController`), HQ › Messages (`Hq::MessagesController`); the last two add `MessageDirectionConcern` (compose to or from the person)
Owner: `MessagesConcern` (`app/controllers/concerns/messages_concern.rb`), `MessageDirectionConcern` (`app/controllers/concerns/message_direction_concern.rb`), `PersonMessage` (`app/models/person_message.rb`), `PersonMessageMember` (`app/models/person_message_member.rb`, every thread's members), `GroupMessageAnnounceJob` (`app/jobs/group_message_announce_job.rb`, a group message's texts and emails), `MessageForm`, `MessageTextValidator` (`app/validators/message_text_validator.rb`); templates in `app/views/common/messages/` -- `index` and `show` both render `_workspace` (the Mail Desk, design A of the 2026-10-18 messaging rework: the search field, the folder tabs and `_list_frame` beside `_pane`, whose `messages-pane` frame holds `_messages_panel`: the header, `_thread` (the expiry notice and the `_message_card`s), the reply form)
Touches: `person_message` (w), `person_message_member` (w), `broadcast` (w), `broadcast_message` (w), `person_alert`, `email_suppression`, `person`, `team`, `person_team`
Verify: `test/controllers/me/messages_controller_test.rb`, `test/controllers/person/messages_controller_test.rb`, `test/controllers/hq/messages_controller_test.rb`, `test/helpers/messages_helper_test.rb`, `test/models/person_message_test.rb`, `test/system/me/messages_workspace_test.rb`, `test/system/me/messages_recipient_autocomplete_test.rb`, `test/system/me/live_message_arrival_test.rb`, `test/system/hq/messages_next_unread_test.rb`, `test/system/person/live_message_list_test.rb`, `test/jobs/group_message_announce_job_test.rb`, `test/models/person_message_member_test.rb`
Trap: Search (`?q=`, slice 2) is `PersonMessage.search_for_person`: `MATCH(subject, body_text) AGAINST (... IN BOOLEAN MODE)` on the FULLTEXT index `index_person_message_on_subject_and_body_text`, every word required as a prefix (`+word*`), OR another member's callsign starting with the whole query (`callsign_normalized` against `WordUtils.normalize_word`, as the compose lookup compares them; skipped when nothing is left), OR a team thread whose team's title holds the query (`LIKE`, team ids plucked first: a team thread lists under its team's name), over every row of every thread the owner is a member of, in every folder, mapped to thread tops by `COALESCE(reply_to_id, id)`. The member thread ids and the hits are plucked (below). InnoDB indexes no word under 3 characters and no stopword, and a required word it never indexed matches nothing, so `search_words` drops both (`SEARCH_STOPWORDS` is MariaDB's default list); a query left with no word falls back to `LIKE '%q%'` on subject and body_text. InnoDB counts `_` as a letter, so `search_words` keeps it in a word, and the marks (`search_pattern`) do too: "dirt_shift" finds "dirt_shift_lead" by its start, where splitting it made `+shift*` a word no row holds; "shift" alone does not find it, as it finds no "midshift" (review finding V21). InnoDB full-text sees committed rows only: a row a transactional test creates is never found, so search tests read `test/fixtures/person_message.yml` (InactiveRanger's mail, every row read on both sides so no unread count moves).
Trap: A body is the rich text editor's HTML (slice 4: compose and reply are `f.rich_text_area`) when it opens with one of the editor's blocks (`PersonMessage::RICH_TEXT_START`, `#rich_text?`), never merely when it holds a `<`: "I <3 Outpost" and the 17 tag-like legacy bodies on dev (`<eom>`, `<name@example.org>`) are plain. `_message_card` renders the HTML through `rich_text` (the sanitizing allow-list) inside `.lexxy-content`, and anything else through `hyperlink_text`, as every row before slice 4, the RBS's copies and walk-ups always were. Neither keeps a class but Lexxy's own (review finding 8): with the app's utilities a sender's `<p class="fixed inset-0 z-50 bg-base-100">` and a link covered the reader's screen. `rich_text` keeps only the `lexxy-content__*` and `horizontal-divider` tokens (`ApplicationHelper::RICH_TEXT_CLASS`, a `RichTextScrubber`; the table wrapper's scroll and the header cell need them) and `hyperlink_text` none (`PLAIN_TEXT_ATTRIBUTES`). Both are shared: announcements and survey texts render through `rich_text`, timesheet notes, camp locations and slot info through `hyperlink_text`; none of them on dev held a class (read 2026-10-18).
Trap: `PersonMessage#body=` writes `body_text` too: the body's words alone (`PersonMessage.plain_text`: a line per block, tags gone, entities decoded; plain text as it is). The FULLTEXT index and the LIKE fallback read `body_text`, never `body`, because the editor's tag and attribute words would make "strong" or "href" find every formatted message; the list row's snippet reads it, and so does `Rbs.message_notify` (`#notify_recipients` hands it the saved row's text: the new-message email's template escapes every value, so tags would print). A raw insert skips `body=` and must set `body_text` itself, as `test/fixtures/person_message.yml` does: the column defaults to empty, so one that leaves it out saves a message that search and the snippet never see. The default is for the release serving while `20261018000005` migrates (review finding 4): it knows no `body_text`, and a NOT NULL column with no default failed every message it saved, RBS copies included. `20261018000007` (deploy 2) copies the body into every empty `body_text` that release left (its bodies are plain text), and `20261018000010` gives dev, which ran `20261018000005` without it, the same default. The 4000-character limit is the text's, not the markup's (`MessageTextValidator`, on `PersonMessage`, `MessageForm` and `MessageReplyForm`; `PersonMessage::MAX_TEXT`), and the editor has no counter, so the error says how long the message is (the reply box starts about four lines tall, `messages-reply-editor`, owner-approved; compose keeps the 16rem every editor starts at; its label is hidden, and Lexxy names its text box from `<label>`s alone, so `aria-label: "Reply"` names it, which Lexxy copies from its host: review finding 12); the markup itself is capped at `PersonMessage::MAX_HTML_BYTES` (64KB, the column holds 16MB), checked before any parse, and markup nested deeper than Nokogiri parses (400 levels) is refused with the same error: `plain_text` returns nil for it, since `Nokogiri::HTML5.fragment` raises `ArgumentError` there, and `body=` raising it was a 500. The text is one line per block of `PersonMessage::RICH_TEXT_BLOCKS`, the list `RICH_TEXT_START` is built from too.
Trap: `q` is carried like `folder`, through the `search_query` helper (`params[:q]`, stripped, 100 characters): the search form (`_workspace`, a GET that loads the list frame and advances the address), a hit's link, the thread page's lazy list `src` and back link, and the tab row frame's fields that the pane's Mark Read/Archive forms post (below), so `#retrieve_list_messages` streams the hits back where a folder would be. While a search shows, `_folder_selector` renders no tabs and `_conversation_list` opens with the count line and Clear Search (a `_top` visit, which empties the field); so the list frame's answer to the search field (which always sends `q`, blank or not) carries the selector's stream inside it (`#index`, `streams:` on `_list_frame`), taking the tabs away and bringing them back on a blank search. The search form (`#messages-search`) sends the folder too, from a hidden field in `_folder_selector`'s frame that joins it by its `form` attribute, as the pane's toggles' fields do: Clear Search and a blank search return to the folder the search started from, where a bare `q` always landed on Inbox (review finding V14). The marks are `MessagesHelper#message_search_marks` and `#message_list_snippet`, from `PersonMessage.search_pattern` (`safe_join` around `<mark class="search-hit">`, the owner-approved `bg-warning/30` utility in `components/messages.css`; a bare `<mark>` shows nothing, `components/lexxy.css` strips it). The pane does not mark the match. A row's link has no `aria-label`: its text is its name, the party, the chip, the time, the subject and the snippet with its marks, where a fixed label hid the snippet and the New Reply chip from a screen reader (review sweep); an archived unread row, whose chip says Archived, adds an `sr-only` Unread.
Trap: A row's link names the pane's frame (`data-turbo-frame="messages-pane"`), so `MessagesConcern#show` answers a `Turbo-Frame: messages-pane` request with `_pane` alone (`#pane_request?`) and the full page otherwise. The frame is rendered `disabled`, and `review_pane_controller` (`park=false`) enables it from `lg` up only: below `lg`, and before the controller loads, a row's link is an ordinary visit to the thread page, where the list column is hidden. A refused thread (`set_message`) is answered inside the pane at 200 on that request (`#refuse_message`), never by a redirect, which Turbo would follow inside the frame and lose the notice.
Trap: Opening an unread thread in the pane on Me marks it read, so its answer carries turbo-streams inside the frame (`#read_state_streams`): the navbar envelope, the Unread count, and the row morphed in place (`dom_id(message, :conversation)`), which keeps the link node and its focus. The count is replaced alone, by its id (`#messages-unread-count`, `MessagesHelper#messages_unread_badge`, on the tab even at zero, hidden), never the tab row, whose active tab would come from the folder the pane was opened with, which a row a live reply replaced does not carry (below). Mark Read/Unread and Archive post the folder and search the list shows (`params[:folder]`, `params[:q]`) and stream that list back as a folder switch would, and Mark Read/Unread morph `_thread` too (`#render_message_flags`). The two fields are not in the header's forms but in the tab row's frame (`_folder_selector`: hidden fields whose `form` attribute names `#messages-toggle-read` and `#messages-toggle-archive`), which a folder switch, a search and every toggle render anew, so a toggle after a tab switch or a search streams back what is on screen, not the folder the thread was opened from. Neither form may carry its own: the browser posts both, the tab row's first, and the later wins. Next Unread, Back to Messages and the /me mark-read URL (`thread_live_controller`) still carry the folder and search the pane was opened with.
Trap: On Person and HQ, where opening a thread never marks it read (`mark_read_on_view?` false), the pane header has Next Unread (slice 6; the HQ window's hand over, mark read, next): `MessagesHelper#next_unread_id` reads the Unread folder's ids in the folder's own order (`PersonMessage.unread_thread_ids`: the `unread_for_person` tops sorted by their newest reply, two queries and no thread loaded, which a model test holds equal to `retrieve_for_person(..., FOLDER_UNREAD)`; both, and `#replies`, order by id, never `created_at`, which holds whole seconds: a same-second tie put Next Unread out of step with the list, and ids run in date order, all 26,045 rows on dev, 2026-10-19) and takes the thread after this one, round to the first past the end, or the first when this one is no longer unread (just marked read). It is a `button_link` naming the pane's frame (`data-turbo-frame=messages-pane`), so it loads like a row (a page visit below lg, the frame being disabled there) and `review_pane_controller` moves the row's mark; with none left it is Back to Messages to the list, naming `_top`, since the header's own `messages-panel-header` frame would otherwise capture it. It is asked each time the header renders (the pane, and every Mark Read/Archive answer). Inside the HQ shell, beside the 191px summary column, the list column is under 20rem from lg to about 1210px (245px at 1024, 308px at 1180, the window tablet's landscape width; 2026-10-18), so there the pane drops under the list (review finding 15): `components/hq-window.css` makes `.messages-workspace` (a wrapper in `_workspace`, a hook only) a container and stacks the columns while it is under 50rem, the 20rem list. The pane stays where it is (park=false) and its frame stays enabled, so a row loads it there. From about 1230px (20.5rem) the split holds: 348px at 1280, 412px at 1440.
Trap: `Hq::MessagesController` guards the shell once per action, on what that action renders: `index` skips it for a turbo-stream or the list frame (`#list_request?`), `show` for the pane request only. A guard on the request's Accept alone 500s the thread page that follows create's redirect, because Turbo's form submission accepts turbo-stream first and the redirected GET keeps that Accept.
Trap: The thread page renders no list: `_list_frame` is a lazy frame whose src is the index (`?selected=` marks the open row), which `MessagesConcern#index` answers with the frame alone. A lazy frame in a `display: none` column never loads, so a phone opening a thread never pays for the folder. `refresh: :morph` reloads it after a morphing page refresh.
Trap: `_message_card` and `_conversation_summary` take the owner as a strict local (`owner:`), not through the `message_owner` helper, and the row its namespace (`namespace:`, `MessagesConcern#messages_route_prefix`, whose path its link builds through `MessagesHelper#mailbox_message_path`) and search (`q:`) too, so a broadcast render (the live reply, below) needs no controller. `_messages_panel_header` still reads the helpers, so a live reply leaves the open thread's header as it was.
Trap: A reply lands live (slice 5): `PersonMessage#announce_reply` (from `#announce_to_recipient`) appends `_message_card` to `#messages-thread` on the stream `[participant, thread top]` of every participant (`PersonMessage#participants`: both parties of a one-to-one thread, every member of a group thread, the author included), rendered with that participant as `owner:`. `_messages_panel` subscribes with `turbo_stream_from message_owner, message` on a thread that `accepts_replies?` (a broadcast, team message or walk-up never gets one, so it listens for none), so the owner's own page and the Person and HQ pages viewing that mailbox all get the owner's view (New or not). A new thread top appends nothing: it is open nowhere yet, and an RBS broadcast to thousands would otherwise render a card each. The author's form appends the same card; Turbo's append replaces a direct child with the same id (`dom_id(message, :card)`), so the two never double (`test/system/me/live_message_arrival_test.rb`). Before the card, every participant's mailbox lists get `_list_reply` on `[participant, :messages, namespace]`, one stream for each of `PersonMessage::MAILBOX_NAMESPACES` (me, person, hq), since a row's link is the namespace's path; `_workspace` subscribes with `turbo_stream_from message_owner, :messages, messages_route_prefix`, because the layout streams only the viewer's own `current_user`. Both mailbox streams, the list's and the open thread's `[owner, thread]`, subscribe through `MailboxStreamsChannel` (`app/channels/mailbox_streams_channel.rb`, `test/channels/mailbox_streams_channel_test.rb`): a signed name never expires, so it asks again on every subscribe, the owner for `me` or a thread, a viewer while Person's gate (Event Management) or HQ's (Admin or Shift Management, the window on) still passes, by the name's namespace (owner's ruling 2026-10-19). A subscription already open lasts until the cable reconnects; a new mailbox stream needs `channel: MailboxStreamsChannel`, or Turbo's own channel takes any name the app ever signed. It morphs the thread's row in place (`method: :morph`), rendered as that participant sees it, and replaces the Unread count: morphed, the row's link stays the same node, so the reader's keyboard focus stays on it (a plain replace dropped it, review finding 14). A page that does not list the thread has no target, which Turbo skips; nothing is moved or added, and the row's link carries no folder or search, since the broadcast cannot know which one each page shows (opened from that row, a thread's pane and phone back link take the Inbox, and a search hit loses its marks). Its avatar is a path (`photo_tag`): rendered outside a request, a URL's host is the renderer's example.org, which development's proxy URL printed. The broadcast knows no selection, so `review_pane_controller#keepMark` refuses the morph's removal of the open row's `aria-current` (`turbo:before-morph-attribute`, mutation `remove`), and a row that is replaced anew takes it on connect. Row before card, so on /me the read that the card's arrival posts answers after it. A group reply marks its author read inside the reply's transaction (`#create_reply`), so the row the broadcast renders for them is read (`test/system/person/live_message_list_test.rb`). A new thread top sends neither, so an Unread count on screen misses a new message until the next folder switch; the envelope has it.
Trap: On /me only (`mark_read_on_view?`), `thread_live_controller` (a MutationObserver on `#messages-thread`) posts `MessagesConcern#mark_read` (`POST /me/messages/:id/mark-read`, routed on /me alone; idempotent, unlike `toggle_read`) when a card marked `data-unread` is added while `document.visibilityState` is `visible` (ruling D6). Its answer is `#read_state_streams` (envelope, Unread count, row) plus the cards morphed one by one (`#card_streams`, also Mark Read/Unread's), so the arrival's New chip goes. A card that lands in a hidden tab stays New. Never morph `#messages-thread` whole from a request: the posts are not coalesced, and an answer loaded before a later reply committed, applied after that reply's card landed, would remove the card (review finding V10, `test/system/me/live_message_arrival_test.rb`); card by card, a stale answer touches only the cards it loaded. Person and HQ never mark on view, live or not.
Trap: A message to two or more callsigns, or to a Cadre or Delegation (`Team#messageable_members`, named in `recipient_team_id`; a team outside `Team.messageable`, the active Cadres and Delegations, is refused; the compose form's select sits in the "Send to a Cadre or Delegation" `ui_disclosure` (stacked under Find Recipient at every width: beside it, on a tablet or a phone over about 415px, the section was indented from the fields; the To field's hint says several callsigns and a team may go together), open when a team is chosen, and is sent only while it is open, `disclosure_fields_controller`: folded, a chosen team used to make the message a group send to the whole team with nothing on the form showing it, review finding 6), is one shared group thread (ruling D2, slice 3): `MessagesConcern#send_group_message` saves the top (`PersonMessage.new_group_thread`) with a `person_message_member` row per person, the sender included and read, in one save; its members' pages are told at once and their texts and emails by `GroupMessageAnnounceJob` (below), never in the request. One callsign is still a one-to-one row, unless the message is sent as a team (below). Every callsign goes through `validate_person_for_messaging`, and one refused stops the whole send; with several, the refusal names it ("Heron: You can't message that callsign."). `MessageForm::MAX_CALLSIGNS` (25) caps a crafted form before any lookup. Every compose form posts `message_form[callsigns][]` from the chips (`AppFormBuilder#callsign_chips_field`, suggestions from `#suggest_callsigns`, the same five `#callsign_matches` the Find Recipient modal lists), and Find Recipient, the phone's way in, appends its choice to them. The visible To/From label names the lookup input (`label for` its id; `shared/_callsign_chips` passes `aria_label: nil` and `shared/_autocomplete` then writes none, since an aria-label outranked the label: review finding 13). The lookup input itself has no name, so `callsign_chips_controller` never lets typed text go unseen (review finding 5): the form's `submit` makes whatever is still typed a chip first, and an Enter the autocomplete held for the search in flight (`pendingEnter`, which commits only a sole suggestion) makes the text a chip on `autocomplete.loadend` unless that suggestion was taken; the server then takes or refuses the callsign like any other. The HQ/Person relay TO the person stays one-to-one (`group_send_allowed?` false: the single looked-up sender, several refused) with the same field labelled From and capped at one chip (`max: 1`): a second choice replaces the first, in `callsign_chips_controller`, and Find Sender's choice replaces it by an `update` of the chip list (`#select_callsign`). Find Recipient's choice is an `append` the controller's `addChip` never sees, so `chipTargetConnected` drops a chip whose callsign is already there, as `addChip` does (no case); one chosen twice was chipped twice and counted twice toward `MessageForm::MAX_CALLSIGNS`. A suggestion for someone who last signed in over two years ago says so under the callsign (`MessagesConcern::AWAY_TOO_LONG`), the warning the relay's old one-person lookup (`_recipient_callsign`, deleted) showed.
Trap: Every row of a group thread has `group` set (top and replies), and `person_id` = `sender_person_id` = its author; the thread top's members are who it is between. A reply (`#build_reply`) is the author's row, and its job texts and emails every other member.
Trap: A team is a party to a group thread (`.scratch/team-messaging/PRD.md`, 2026-10-19): the top names the team it was sent to (`recipient_team_id`) or as (`sender_team_id`, `sender_type` "team", the author kept in `sender_person_id`), `PersonMessage#team_ids`. `person_message_member.team_id` marks a member the team put there: `#sync_team_members!` runs on the top after it and after every reply in the thread (an `after_create` lambda handing it the row just saved), marking each still-messageable team's (`Team#messageable?`) eligible members (`Team#messageable_members`) and whoever just wrote as the team, eligible or not (a manager writing for someone who never signed in), inserting one who joined the team since, unread, and removing nobody; a leaver keeps their row and its mark. A deactivated or retyped team stops growing its threads and is not offered in Reply As. Compose offers a From select to a member of an active Cadre or Delegation (`Team.cadres_and_delegations_of`, `MessagesHelper#message_sender_team_options`; never on the relay, `group_send_allowed?`), `MessageForm#sender_team_id`, checked again by `MessagesConcern#message_sender_team`; a message sent as a team is always a group thread the team is in, so with nobody else named it is an internal team thread (ruling R7). The reply form offers "Reply As" (`MessageReplyForm#as_team_id`, `collection_radio_buttons`, the owner's callsign first; a form first drawn, and the one after a reply is sent, has the first team checked, `MessagesConcern#new_reply_form`, the owner's ruling of 2026-10-19 replacing R1; a refused reply keeps its choice) only for the thread's teams still messageable that the owner is on now (`#reply_teams_for`, from `PersonTeam`, never the mark: a leaver cannot speak for the team), checked again by `#reply_team`; the row is written as the team (`PersonMessage.new_group_reply`, `#as_team=`). On the card a row written as a team names the team; to a current member of that team alone it names the author's callsign, as an individual row would, chipped "Sent as <team>" on the top or "Replied as <team>" on a reply (owner's request 2026-10-19; `#reveals_author_to?`, from `#current_team_memberships`, one pluck per thread render memoized on the top, so the broadcast card each participant gets is right for them); an individual row by someone marked a team member who has since left wears a "Former <team> Member" chip (`#former_team`); on Person and HQ both follow the owner's membership, as the manager sees the mailbox as the owner does (ruling R2). The pane header and the list row collapse marked members into the team's title (`#group_party_names`: "Khaki Delegation, Quill") and, to anyone who neither wrote a team-sent thread nor is on the team it was sent as now, read "From:" that team alone (`#addressed_from_team?`, from the roster as the reveal reads it, so a joiner and a leaver see one story; `thread_list` plucks the rosters of a whole list once and hands them to every row, `#current_team_memberships=`); a team-sent thread's author sees it in their Sent folder. A team deleted since (`TeamManagement.destroy` leaves the ids) is named "Deleted Team #id" (`PersonMessage.deleted_team_name`, `#team_name`, `#sender_name`), its marked members still collapse under it, and the callout's team email is skipped. `thread_list` and `set_message` include `recipient_team`, `sender_team` and the replies' `sender_team` for the titles; `set_message` and `#announce_reply` pass every association in one hash (`sender_team: {}`), because `includes` gives each argument its own Preloader (an array is flattened into arguments) and only one Preloader loads a class once (thread open: 7 queries against 5). The rosters are read by team on every render and reply, through `index_person_team_on_team_id_and_person_id` (covering; before it, each read scanned all of `person_team`, 2,543 rows on dev on 2026-10-19). Clubhouse 2's team messages (`sender_type` "team" with no author and no `group`) are untouched: no replies, the callout with the team's email.
Trap: Every thread is between its members (`person_message_member`, the member model, `.scratch/messaging-rework/member-model-plan.md`): a one-to-one thread its recipient and sender, a note to self one member, a broadcast, walk-up or import its recipient, a group thread everyone in it. Each member row holds that person's state, and every read takes it from there: `PersonMessage#member` (from the members `thread_list` and `set_message` load, so a list costs no query per row), `#participant?` (who `set_message` lets open a thread, on every namespace), `#participants`, `#archived?`, `#read?`, `#thread_read?`. A thread is unread for a member who never read it (`last_read_message_id` NULL) or when a row by someone else is newer than the newest one they read (its id above `last_read_message_id`, ruling D2: ids run in date order and never tie, so a reply in the same second, or on the training server's frozen clock, still reads unread); a member's own row is always read. `#mark_thread_read!` marks the member read through the rows shown (`PersonMessageMember#mark_read!`: a row written since stays New); Mark Unread puts it just before the newest row by someone else, so that row alone reads New, or NULL when there is none (`#mark_unread_from!`). A reply marks its thread read for its author on Me alone (ruling D3, `MessagesConcern#create_reply` asks `mark_read_on_view?`): written on Person or HQ as the Ranger, it leaves their unread alone. It marks only through the newest message the page showed (`MessageReplyForm#shown_through`, a hidden field `_reply_form` draws from the thread it renders, kept on the form drawn after a send; `#mark_thread_read!(through:)`), never through replies loaded after the save: one from someone else that landed unseen, such as a live card a cable drop missed, stays New (review finding 10). `PersonMessageMember#mark_read!` never moves a watermark back, because the page may be older than a live mark-read (`thread_live_controller`). Deleting a person deletes their member rows (`Person has_many :person_message_member, dependent: :delete_all`; no foreign key); one left by an earlier deletion names nobody, and `#other_members` and `#participants` skip it, or every other member's list, pane, reply and job failed on it (review finding 7). A row the deleted person wrote, or one sent to them, names them "Deleted #id" (`PersonMessage.deleted_name`, the wording of `LinkHelper#person_display_name`; owner's ruling 2026-10-19), and shows no photo.
Trap: A group message, top or reply, updates its members' pages in the request like any other message (owner's ruling 2026-10-18, "Pages live, texts queued"): `PersonMessage#announce_to_recipient` sends every member but the author the envelope, then for a reply every member's row, Unread count and card (`#announce_reply`), each member rescued apart (`#announcing`), and the loads before them too: the recipients and `#announce_reply`'s fresh thread run inside a rescue of their own, so nothing raises out of `after_create_commit` past a reply's commit, where it skipped the request's notify and answered 500 (review finding 11). Its texts and emails wait for one `GroupMessageAnnounceJob` per message, which the callback enqueues after them: `Rbs.message_notify` for every member but the author and anyone whose status bars messages (below), in person id order. A group reply to 100 members (2026-10-18, test DB, sandboxed): all of it inline, 1,320 queries and 504 broadcasts in the request, besides a text per member through `notify_by_text`, one at a time; now the request makes 220 queries and the 504 broadcasts in 150-200 ms, and the job 1,104 queries. The job is a continuation (`ActiveJob::Continuable`): the cursor moves past each member once their notify is done, so a worker that stops mid-loop (a deploy) re-enqueues it from the next member, as an error once the first is done does, and nobody is texted or emailed twice; each member's notify is rescued and logged, so one failure stops neither the rest nor the job. A worker killed outright leaves its job failed by Solid Queue's pruning, never re-run; only a notify that hangs past the 30-second shutdown timeout gets its job released and run again from its last saved cursor. The workers poll every 30 seconds (`config/queue.yml`, raised from 0.1 on 2026-09-13), so a group message's texts and emails go out up to 30 seconds after it is sent. One-to-one messages notify in the request: the RBS job saves thousands of them, which would each enqueue a job.
Trap: `unread_for_person` is ONE semi-join, `id IN (member rows joined to their threads' rows)` (`PersonMessage.unread_member_threads`), with nothing OR'd around it, and the Inbox and Archived folders are `id IN (the member rows by person and archived)` (`index_person_message_member_on_person_id_and_archived`). Never put a UNION inside the subquery or an OR around it: slice 3 measured a dependent subquery over the whole table (4.2 million reads against 154) and a materialized full scan (171,000). On a copy of dev (2026-10-18, Handler_read) the heaviest mailbox's unread count costs 1,237 reads and a typical one 30. Search plucks the member thread ids and then the hits (`id IN ids OR reply_to_id IN ids` with the text, as `COALESCE(reply_to_id, id)`): as a subquery under the callsign's OR the hits made MariaDB scan the table for the short-word fallback (73,903 reads against 1,656). The member query walks a thread's replies by `index_person_message_on_reply_to_id`. A folder scope must never JOIN `person_message_member` with a where-hash on it: `thread_list`'s `includes(members: :person)` would turn into an `eager_load` holding only the owner's member row, and a group thread would lose its other members.
Trap: A thread's member rows are written by the model alone: a new top's by `PersonMessage#add_members` (`after_create`, one `insert_all`, so the RBS job's `save(validate: false)` gets them too: the recipient never read, the sender when someone else read through it, a note to self one member, read; a group top only stamps its author's `last_read_message_id`, unknown before the insert), Mark Read and Mark Unread by `PersonMessageMember#mark_read!` and `#mark_unread_from!` from `#mark_thread_read!` and `#toggle_thread_read!`, Archive by `PersonMessage#toggle_archived!`; a reply adds no one, except in a team thread, where `#sync_team_members!` marks rows and inserts the team's newcomers (above). A raw insert skips `add_members`, so a fixture thread needs its `person_message_member.yml` rows. The sender/recipient read and archive flags, `delivered` and the member row's `last_read_at` are dropped by `20261018000009`, one deploy after the release that stopped reading and writing them and left them out of its models (`self.ignored_columns`): a release that still names them, slice 2's included, fails every message INSERT and flag write the moment they go while it serves, since `partial_inserts` is false (load_defaults 8.0) and an INSERT names every column the release cached. `20261018000008` drops only `person_message_person_id_reply_to_id_index` (it dropped the columns too until review finding 3; dev ran that version, so `20261018000009` skips each column already gone, `if_exists`). `20261018000009`'s `down` puts them back where they were, derived from the member rows, for slice 2's code, which writes them. `20261018000006`'s `down` deletes the one-to-one member rows, and must run before code from before it does: that code reads every member row a person has as a group thread's. `20261018000007` (deploy 2) makes every one-to-one member row again from the flags and derives every group member's `last_read_message_id` from its `last_read_at` once more (the newest row of the thread written by then, a top's author read through it at least, NULL for never read), because the release serving while deploy 1 migrated wrote only `last_read_at` for a group member: the author's first row, Mark Read and Mark Unread.
Trap: Deploying the member model to beta or amazon (neither has run `20261018000003` or later; unverified there) takes four deploys, in order and by commit (all on main: `ebd379e7` and `9cbeb46b` through the merge `a16aff4f`), because each deploy migrates while the release before it still serves, that release's INSERTs name every column it cached, and it queries the tables by the names it knew: (1) `ebd379e7` (slice 1's code, 054ff7f2, with the fixed `000005` and `000006`, `20261018000001` and `000002` adding `person_asset` and `person_alert` as views over the old tables, and `ViewBackedTable` on `PersonAsset` and `PersonAlert`), then `bin/rails messages:member_parity`; (2) `9cbeb46b` (slice 2's code, 4afb83c4, with the fixed `000005`–`000007`, a `group_unread` line in the parity check, and `20261019000001`, which swaps each view for its table), then the parity check again, every line 0; (3) `6002a51d` (slice 3's code, the six columns in `ignored_columns`; migrates `000008`, an index); (4) `5f1f7ef1` or any later commit (migrates `000009`, the drop, and `000010`). Never deploy 054ff7f2, 4afb83c4, a3fa8118, 161a2dc4 or 2bec58e4, whose migrations are the broken ones (the last two still rename the tables under the old release), and never step 4 straight over step 2. Rolling back: each step to the one before it needs no data step, except step 4 to step 2 (run `000009`'s `down` first) and anything past step 2 once step 3 served (unsupported: step 3 writes no flags); step 2 back to step 1 is safe as it stands, since step 1's models read a table as well as a view. `.scratch/messaging-rework/member-model-plan.md` §9–§10 has the table.
Trap: `person_message_member` keeps the `person_message` prefix on purpose: `RedactDatabase#empty_message_archives` empties every table matching `/\Aperson_message/` and `clubhouse.rake`'s `skipped_logs` dumps no rows of `person_message%` (`test/lib/redact_database_test.rb` pins it).
Trap: `MessageDirectionConcern`'s overrides (direction, `mark_read_on_view?` false so managers never clear unread) win only by inclusion order — include it after `MessagesConcern`.
Trap: Every one-to-one send and reply calls `Rbs.message_notify` in the request (a group message's job calls it for each other member, with `group: true` and `PersonMessage#sender_name` as the sender, so a row written as a team is announced from the team, never its author: ruling R5), which may text or email the recipient (setting `BROADCAST_CLUBHOUSE_NOTIFY` plus their alert preferences) and writes `broadcast` / `broadcast_message` rows. The text reads "group msg" for a group message, and the email's seed template (`db/mail_templates/clubhouse_new_message_mailer/notify.yml`) branches on `message_group`, "[Clubhouse Group Message]" in the subject, which the mailer takes from `.with(group:)`, never a `notify` keyword: a mail job one release enqueues is run by the other while an AWS rollout overlaps them (start-first, Solid Queue in every Puma), and a keyword the older `notify` does not know raised and lost the email. The wording reaches a deployed database only when someone runs `bin/rails mail_templates:load` (no deploy step does; the mail-templates entry below), and a row edited in the Clubhouse is skipped by it and keeps the old wording until edited. A row written as a team is notified `anonymous: true`: its email's mail log row names no sender (Person › Mail Log is open to VCs), while the `broadcast` row, which requires one, keeps the author on pages only Admin and Tech Ninja open. The job notifies only the member rows written by the time the message was (`perform(message_id, through_member_id)`, from `#announce_to_recipient`), so a newcomer a later reply brings in is told of that reply alone; a job enqueued with that argument fails on a worker of the release before it (one argument) instead of naming an anonymous author the old way, so retry such failures from Admin › Background Jobs after an overlapping rollout.
Trap: Which messages take a reply is `PersonMessage#accepts_replies?` (a person's message, and every row of a group thread, one written as a team included: `group? || from_person?`, by kind, never by whether `sender_person_id` happens to be set), asked by `validate_reply`, by the guard in `MessagesConcern#create_reply` and by `common/messages/_messages_panel.html.erb`, which shows the others a callout instead of the reply form. The guard runs before the recipient lookup, because broadcasts, walk-ups and Clubhouse 2's team messages have no `sender_person_id`, and `Person.find(nil)` 404s. A reply the model still refuses, such as a one-to-one reply to a person whose status is now in `Person::NO_MESSAGES_STATUSES` (`Person#messages_barred?`), comes back on the form with the model's errors, and so does a refused group send (`#send_group_message`, the generic "An error occurred" only when the model gave none); `errors.format` is `%{message}`, so each must be a whole sentence. A group row's `person_id` is its author, and `validate_recipient` does not ask the author's status, as it never asks a one-to-one sender's (owner's ruling 2026-10-19, review finding 9): a suspended Ranger's group reply or send relayed on Person or HQ goes through, as their one-to-one ones did. A group reply still goes to the shared thread when a member's status has since come to bar messages; that member is skipped (`PersonMessage#read_for_barred_members`, an `after_create` on a group reply: their member row is read through it, so their Unread count and HQ's unread-message prompt and Deliver Messages todo leave it out), their envelope is not told (`#announce_to_recipient`) and `GroupMessageAnnounceJob` does not notify them (`Rbs.message_notify` skipped such people already). Marked read through the reply, any older row of the thread still unread for them reads as read too.
Trap: Unread is per thread, by the owner's member row (above). `PersonMessage.unread_for_person` (the Unread folder and its badge, HQ's unread-message prompt and Deliver Messages todo) and `#thread_read?` (the "New"/"New Reply" chip, the Mark Read/Unread button) apply that rule twice, in SQL and in Ruby, so change both together. Write read state only through `#mark_thread_read!` and `#toggle_thread_read!` (archive through `#toggle_archived!`): the toggle clears replies too, because /person and HQ never mark a thread read on view.
Trap: `PersonMessage.unread_for_person` keeps NULL `sender_person_id` (broadcasts, walk-ups, imports: a row by someone else) and NULL `expires_at` explicitly, because a bare `where.not` drops NULL rows. An expired message reads as read everywhere (`#read?` and `#thread_read?` return true once it has expired), so its row, card and the Unread count agree; its pane shows no Mark Read/Unread, which could change nothing, and opening it writes nothing.
Trap: Every message from before 2025 came from Clubhouse 2's per-year archive tables (`MergePersonMessageArchives`, which kept their ids, so ids still run in date order). Each is `rbs` or `other` with a NULL `sender_person_id`, imported with every flag set (read, delivered, archived on both sides), which `20261018000006` made an archived, read member row for its recipient, and those threads appear only in the recipient's Archived folder, never in a Sent folder. One its recipient moved back to the Inbox keeps `sender_archived` set with no sender person, so `20261018000006` and `20261018000007` compare the sender NULL-safe (`sender_person_id <=> person_id`): a plain `=` made its `archived` NULL, which the NOT NULL column refused after the migration's DDL had committed (MariaDB DDL is not transactional), and a re-run then died on the duplicate column; `20261018000006` now skips each column and index already there. A Clubhouse 2 reply addressed to someone outside its thread's two parties made no member of them (ruling D4).

### Ranger Broadcast System (Rbs)
Used by: Communication Management › Ranger Broadcast (`Communication::RbsController`, `RbsBroadcastsController`, `RbsHistoryController`, `RbsBroadcastForm`, `RbsTransmitSmsJob`, `RbsTransmitEmailJob`, `RbsTransmitClubhouseMessageJob`, `RbsRetryEmailJob`), Me/Person/HQ › Messages (`Rbs.message_notify`, from the request or `GroupMessageAnnounceJob`), inbound SMS replies (`Infrastructure::SmsController`)
Owner: `Rbs` (`app/lib/rbs.rb`)
Touches: `broadcast` (w), `broadcast_message` (w), `person_message` (w), `mail_log` (w), `error_logs` (w), `alert`, `person_alert`, `person`, `person_slot`, `slot`, `position`, `timesheet`, `person_event`, `email_suppression`, `setting`
Verify: `test/lib/rbs_test.rb`, `test/lib/rbs_sandbox_test.rb`, `test/controllers/communication/rbs_broadcasts_controller_test.rb`, `test/controllers/communication/rbs_controller_test.rb`, `test/controllers/communication/rbs_history_controller_test.rb`
Trap: The sandbox settings (`BROADCAST_SMS_SANDBOX`, `BROADCAST_MAIL_SANDBOX`, `BROADCAST_CLUBHOUSE_SANDBOX`) are checked inside Rbs's `deliver_queued_sms` (with `sms_held?` passed from the click), `broadcast_message`, `notify_by_text`, and for broadcast email by `Rbs.email_mode` — send through them, not `SmsService`, `RbsMailer` or SES directly.
Trap: Broadcast email goes to Rangers only when `Rails.configuration.x.rbs_email_rangers == true` — set in `config/application.rb` (false), `test.rb` (true) and `production.rb` (`RANGER_CLUBHOUSE_RBS_EMAIL_LIVE=true`). An unset `config.x` key reads as a truthy empty `OrderedOptions`, so never test it for truthiness. Anywhere else, with no `BROADCAST_MAIL_TEST_ADDRESS` set, `email_mode` is `:held` and email is recorded as sent with no SES call (`invalid-parameter` with no address); `RbsSandbox` then lists "emails".
Trap: setting `BROADCAST_MAIL_TEST_ADDRESS` (a pattern such as `test+?@example.com`) makes `email_mode` `:test`: every broadcast email goes through SES to the pattern with the person's id in place of the `?` (`Rbs.test_address`), in any environment, and that address is what `broadcast_message.address` and `mail_log.to_email` record. The sandbox and the training server still win (`:held`). A pattern that can't be used is `:misconfigured`: nothing is sent, rows are `service-fail` with address `""`, and one `rbs-email-not-sent` log is written. `message_notify` follows it too: a new-message alert's email goes (still by ActionMailer) to `destination` for the same `email_mode`, which is the address its row and `mail_log` record; `:misconfigured` queues nothing and records the row `service-fail` with address `""` and the alert's `email_failed` 1, with no error log; a suppressed address keeps its skip row with the person's own address. The sandbox notice (`common/rbs/_sandbox_notice`, fed by `RbsSandbox.notice`, which reads the email settings once for both the held channels and the test address; `RbsSandbox.anything_live?` decides the "goes out for real" line) names the pattern.
Trap: Send and Retry pass the mode at that moment (`email_mode.to_s`) as the last argument of `RbsTransmitEmailJob` / `RbsRetryEmailJob`, and every batch sends by `Rbs.effective_email_mode(queued, now)`: never less safe than queued. A job queued without the argument, or in the mode there is now, goes by the mode now. Otherwise either one held is held, then `:test` now is used, and any other change is `:misconfigured` and sends nothing (`service-fail`, `rbs-email-not-sent` with `queued:` and `now:`) -- queued `:test` or `:misconfigured` meeting `:live` included, so a broadcast queued for the test inbox never reaches Rangers. The SES client is built by the first batch that sends, so a run held at its start and let go part-way still sends.
Trap: a broadcast never reads "Delivered" with nothing sent (short of a killed worker, see the RbsTransmitEmailJob entry): `email_failed` is recounted from the rows after every recorded batch and again however the run ends (`Rbs.wind_up`, in an `ensure` that never hides the error or deploy stop already under way), in both `Rbs.broadcast_email` and `Rbs.deliver_retried_emails`. If recording a batch SES has answered fails, `rbs-email-unrecorded` logs its person ids and SES ids and the error goes on (`Rbs.recording`). A run stopped by any error part-way leaves no one without a row and nothing SES may have taken retryable: on a send, the people of the call in flight whom SES may have taken (`EmailRun#in_flight`, narrowed to those it gave an id or left in doubt once it answers) are recorded `send-unconfirmed`, and everyone not yet reached `service-fail` at the address the mode would use -- or held (`sent`, or `invalid-parameter` with no address), when email is held, never a failure a later live Retry would send to the Ranger (`Rbs.record_stopped`); on a retry, the in-flight call's rows become `send-unconfirmed` (`Rbs.mark_unconfirmed`). Logs written once SES has answered, or as a run winds up, go through `Rbs.note`, which never lets a failed log write stop the rows or hide the error.
Trap: `Rbs.transmit` texts inline but queues email and Clubhouse messages, so it counts emails queued, not delivered (failures land later in `broadcast.email_failed`); a new email path must queue too — inline sends time out (see `Rbs.retry_broadcast`).
Trap: a send never emails an address `email_suppression` holds, for either reason (a bounce or a spam report). `Rbs.retrieve_recipients` asks `EmailSuppression.suppressed` once, for every plucked address as stored, so a Clubhouse 2-era mixed-case `person.email` still matches; RBS compares and normalizes nothing itself. `email_block_reason` returns `Rbs::EMAIL_STATUS_SUPPRESSED` (`suppressed`) after the blank-address check and before the alert preference, so an emergency doesn't override it either (it still texts them where their number allows). `use_email` is false, and in a non-emergency broadcast without Clubhouse ticked, someone left with no usable channel drops out, as with no address. An emergency keeps anyone no channel reaches (no usable number, and a blank or suppressed address) listed, with `use_sms` and `use_email` both false: `Rbs.unreachable(people, send_clubhouse:)` names them (`[]` with Clubhouse ticked, and for every other type by construction). `receiver_estimate`, the review callout and button, the table note and the sent page's headline leave them out; `recipient_count` keeps them (see RBS › Send a broadcast). The email job records the reason from the person it loads (see RbsTransmitEmailJob). A Retry doesn't ask it (`BroadcastMessage.sendable` has no suppression condition), and resends the address on its row. `message_notify` asks `EmailSuppression.suppressed?(person.email)` once per alert whose email is on, before the `BROADCAST_MAIL_SANDBOX` check, and for a suppressed address queues nothing and records its email row `suppressed`, with the person's own address, in every mode and with no action log; the alert's `Broadcast` keeps `sent_email` (the preference) and `email_failed` 0. `SuppressedRecipientsInterceptor` is the backstop for an address suppressed after the alert was queued, which it drops under a `sent` row (#31's accepted race).

### Text messaging & alert preferences (SmsService)
Used by: Communication Management › Ranger Broadcast (`Rbs`), Me › Alerts and Person › alerts (`Me::AlertsController`, `Person::AlertsController` via `Alerts::EditingConcern` → `Alerts::SmsPreferencesService`), Twilio webhooks (`Infrastructure::SmsController`: `POST /infrastructure/sms/inbound`, and the delivery receipts at `POST /infrastructure/sms/status`)
Owner: `SmsService` (`app/lib/sms_service.rb`), `Alerts::SmsPreferencesService` (`app/services/alerts/sms_preferences_service.rb`), `Alerts::EditingConcern` (`app/controllers/concerns/alerts/editing_concern.rb`)
Touches: `person` (w), `person_alert` (w), `broadcast_message` (w), `action_logs` (w), `error_logs` (w), `alert`, `setting`
Verify: `test/lib/sms_service_test.rb`, `test/services/alerts/sms_preferences_service_test.rb`, `test/controllers/infrastructure/sms_controller_test.rb`, `test/controllers/me/alerts_controller_test.rb`, `test/controllers/person/alerts_controller_test.rb`, `test/lib/rbs_test.rb`
Trap: `SmsService` checks no sandbox, so `Alerts::SmsPreferencesService` verification codes go out for real even with `BROADCAST_SMS_SANDBOX` on (Clubhouse 2's did too); only `prevent_if_ghd_server` in `Alerts::EditingConcern` holds them back.
Trap: a single text, a verification code or a new-message alert (`Rbs.notify_by_text`), goes through `SmsService.send_text` (since 2026-10-26, SMS Management issue 06): one Messages API request through the Messaging Service in `TwilioMessagingServiceId`, `validity_period` 2 hours (`SmsService::VALIDITY_PERIOD`), answering the text's SID, which its `broadcast_message` row keeps in `message_id`. A refusal raises `SmsException` (the row is `service-fail` for an alert; a code gets no row, only `error_logs`, as before); an unanswered call (`TwilioAccount.unanswered?`: a timeout, an unreadable answer) raises `SmsException::Unconfirmed` and the row is `send-unconfirmed`, never sent again. With the setting empty every single text fails before Twilio is asked, so the setting must be in place on a server before this code reaches it. Broadcasts and retries go out through `SmsService.text_through` too, from `RbsTransmitSmsJob` (issue 07, see its entry), so nothing calls `SmsService.broadcast` (Notify) any more; issue 10 removes it.
Trap: `SmsService` reads its settings through `TwilioAccount.settings` and builds its client with `TwilioAccount.build_client` (5-second timeout), which tests swap for `FakeTwilioClient` (`with_fake_twilio`). `broadcast` sends one Notify notification per service in TwilioServiceId, the numbers shared out in order (one number goes through the first service only), and raises a `TwilioError` as `SmsException` naming the service, the refusal kept as its `cause`; the services before it have already sent, so a refusal partway is not all or nothing.

### Mail templates (Liquid in the database)
Used by: every mailer through `ApplicationMailer` (`MailTemplateResolver` plus the `:liquid` handler in `config/initializers/liquid.rb`, `liquid_subject`), Communication Management › Email Templates (`Communication::MailTemplatesController`)
Owner: `MailTemplateRenderer` (`app/lib/mail_template_renderer.rb`), `MailTemplateResolver` (`app/lib/mail_template_resolver.rb`), `ApplicationMailer` (`app/mailers/application_mailer.rb`)
Touches: `mail_template`
Verify: `test/lib/mail_template_renderer_test.rb`, `test/mailers/mail_template_coverage_test.rb`, `test/lib/mail_template_seeds_test.rb`, `test/models/mail_template_test.rb`, `test/controllers/communication/mail_templates_controller_test.rb`
Trap: A template reads only `liquid_assigns`, by string key (`MailTemplateRenderer.prepare` stringifies) — a mailer's instance variables never reach the message.
Trap: There is no `mail_template` fixture — `test/test_helper.rb` runs `MailTemplateSeeds.load!` from the YAML under `db/mail_templates/`, so change wording in those seed files.

### Mail delivery log (MailLog)
Used by: every email ActionMailer delivers (`ApplicationMailer#record_mail_log`, an `after_deliver` callback, through `MailLog.record_delivery`), Communication Management › Ranger Broadcast email (`Rbs.broadcast_email` and `Rbs.deliver_retried_emails` through `MailLog.record_ses_sends`, one row per email SES took), SES delivery/bounce/complaint webhook (`Infrastructure::AwsSnsController`); read by Person › Mail Log, Admin › Mail Log and the VC application's Mail Log section, pruned by `CleanupMailLogJob`
Owner: `MailLog` (`app/models/mail_log.rb`), `ApplicationMailer` (`app/mailers/application_mailer.rb`)
Touches: `mail_log` (w), `person` (w), `action_logs` (w), `error_logs` (w)
Verify: `test/models/mail_log_test.rb`, `test/mailers/application_mailer_test.rb`, `test/mailers/prospective_application_mailer_test.rb`, `test/lib/rbs_test.rb`, `test/controllers/infrastructure/aws_sns_controller_test.rb`, `test/lib/prospective_application_status_mail_test.rb`, `test/controllers/vc/applications_controller_test.rb`, `test/controllers/person/mail_log_controller_test.rb`, `test/controllers/admin/mail_log_controller_test.rb`, `test/jobs/cleanup_mail_log_job_test.rb`
Trap: every email ActionMailer delivers, by `deliver_now` or from a `deliver_later` job, gets its rows from `ApplicationMailer#record_mail_log`, a private `after_deliver` callback (private: Action Mailer takes any public method for an action); no sender calls `record_delivery` itself. RBS broadcast email never reaches it (`RbsMailer` is only rendered with `.message`) and keeps only its `record_ses_sends` rows. Only sent and held mail is logged: a delivery that raises never runs the callback, and its failure shows in Solid Queue, `error_logs` and the daily report. That holds while `raise_delivery_errors` keeps its default of true (`config/environments/production.rb` leaves it commented out); were it false, the mail gem would swallow the error and the failed email would be logged as sent. A row that cannot be written is rescued into one `mail-log-exception` error log naming the mailer and action, never re-raised, so the email stays sent and the request or job still succeeds; every To row of that message is lost, since they are written in one transaction. A bounce or complaint stamps only a row whose `message_id` is the id SES assigned — the rows `Rbs.record_email_batch` and `Rbs.record_retried_batch` write, and `record_delivery` rows for mail sent through SES by the `:ses_mail` delivery method (`SesMailDelivery`) — so for any other mail (today everything production sends by SMTP, until `RANGER_CLUBHOUSE_SES_MAIL_LIVE` turns on `config.x.ses_mail_live`) a bounce reaches only an `email-bouncing` action log and, if permanent, `person.is_bouncing` (`Infrastructure::AwsSnsController#record_bounces`), and a complaint only an `email-complaint` action log. Whether or not a row is stamped, a Permanent bounce and a Complaint also write `email_suppression` for the address (see SES Mail Events). A bounce that does stamp an RBS broadcast row also moves that email's `broadcast_message` to `bounced` (see SES Mail Events).
Trap: a subject over 255 characters (`MailLog::SUBJECT_LIMIT`, the width of `mail_log.subject`) is stored cut to 255, ending in "...", by `normalizes :subject`, because the email has gone by the time its row is written and the database refuses a longer value outright. The cut counts characters, as the utf8mb4 column does. The email carries the whole subject, and applicant mail keeps it whole in the application's "emailed" audit entry (`ProspectiveApplicationLog`, on the application's Audit Log); Person › Mail Log, Admin › Mail Log and the application's Mail Log show it cut. Nothing caps a subject before sending: VC › Applications › Send Email takes any length, and a template subject (up to 500 characters, longer once Liquid fills it) can outgrow the column too. The normalizer lives in the attribute type, so it covers every writer, `insert_all` included.
Trap: `record_delivery` writes one row per To address, each holding that one bare address (none for a message with no To), as Clubhouse 2 did, so a message to a list shows once per address. It reads the message after the interceptors ran, so an address `SuppressedRecipientsInterceptor` dropped has no row, and an email it left with nobody to send to has none at all (see Transactional mail). The rows carry SES's id when the mail went through the `:ses_mail` delivery method (`SesMailDelivery`, a subclass of aws-actionmailer-ses's `:ses_v2` mailer, which sets the `ses_message_id` header during `deliver_now`), otherwise the mail gem's own Message-ID, which SES overwrites. Production sends this mail by SMTP (`config/environments/production.rb`) until the opt-in `RANGER_CLUBHOUSE_SES_MAIL_LIVE` (`config.x.ses_mail_live`) has `config/initializers/mail_delivery.rb` choose `:ses_mail`, so until then its rows never match a report; the broadcast rows carry the id SES returned (`Rbs.record_email_batch` and `Rbs.record_retried_batch` → `MailLog.record_ses_sends`).
Trap: under the all-mail test address (`RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS`, `MailTestAddressInterceptor`) the callback reads the message after the interceptor replaced its recipients, so it writes one row naming the test inbox, under SES's id, with any `prospective_application_id`; the person lookup by address finds nobody. SES's reports name the test inbox too, so they stamp that row.
Trap: each row's `person_id` is whoever holds its To address, as Clubhouse 2 set it (`MailSentListener`): `record_delivery` looks every To address up in one `person` query and matches the answers back ignoring case — `person.email` is unique under `utf8mb4_unicode_ci`, but a Clubhouse 2-era address can be stored in mixed case, since `normalizes :email` downcases only what is written now. A team or cadre list address (`MailLog::LIST_ADDRESS`, Clubhouse 2's pattern) is never looked up and gets no person; it shows on Admin › Mail Log and is found by address. No mailer names a person, since Mail Log means mail sent to or from someone: `AutomaticActiveConversionMailer` writes about a person to the VC list and is not on their log. So applicant mail sent to an address an account holds (a returning applicant, or mail after the account was made) also shows on that person's Person › Mail Log, and status mail redirected by `PROSPECTIVE_APPLICATION_MAIL_SANDBOX` shows on the Mail Log of whoever holds the sandbox address. The one association a mailer passes is `prospective_application_id`, from the `@prospective_application_id` that `ProspectiveApplicationMailer#build_mail`, `ProspectiveApplication::SendEmailMailer#send_message` and `ProspectiveApplication::RrnCheckMailer#check` set.
Trap: `sender_id` is `ApplicationMailer#set_sender_id`'s: `params[:sender_id]` when the call passed `.with(sender_id:)`, otherwise `Current.person`, read when the action runs. Inside a `deliver_later` job nobody is signed in, so a queued email without the param logs no sender (see Transactional mail). A `deliver_now` reads whoever is signed in: nobody for a password reset or a scheduled job's mail, the VC for status mail and photo review.
Trap: five mailers keep no body — `PasswordResetMailer`, `WelcomeMailer` and `OnlineCourseResetPasswordMailer` (a live sign-in secret) and `ClubhouseNewMessageMailer` and `ContactMailer` (someone's private message) — because any VC can open any person's Mail Log, and a logged reset or invite link would let a VC take over any account. Each sets `self.withhold_body_from_mail_log = true`, a `class_attribute` on `ApplicationMailer` with no instance reader or predicate, so a subclass or a new caller inherits it. Their rows keep sender, person, addresses, subject, message id and outcome — the subject stays visible to every VC, an alert's "[Clubhouse Message] " plus the message's own subject included — and `record_delivery(withhold_body: true)` leaves `body` out, so the column keeps its NULL. The marker is no `broadcast_id` and a NULL body (`MailLog#body_withheld?`, which like `#body` raises on a `LIST_COLUMNS` row): RBS rows are NULL too but read the broadcast's text, and every other writer stores a string, `""` for an empty body (the `body=` setter). No notice text is written into the row; the body view says it (see Person › Mail Log).
Trap: held mail on the training server (`ApplicationMailer#hold_mail_on_training_server` sets `perform_deliveries` false) still runs the deliver callbacks — mail 2.9.1's `do_delivery` skips only the delivery method — so it gets rows with `was_sent` false. No page reads `was_sent` (it is not in `LIST_COLUMNS` and no view shows it), so on both Mail Log pages a held email looks sent. RBS's `:held` mode writes no row at all.
Trap: retention is six months for all mail (`MailLog::RETENTION`, `CleanupMailLogJob`), as Clubhouse 2 kept it. Most rows are new-message alerts (one per recipient per message) and the daily report (one row per `DAILY_REPORT_EMAIL` address each day, each with the full body).

### Person search & autocomplete
Used by: the navbar search bar (`AutocompleteController#search`, `GET /autocomplete/search`, gated for display by `SearchBarPolicy`), message recipient lookup (`MessagesConcern` → `PersonSearch.search_callsigns_for_messaging`), Training › session roster Add dialog, Mentoring › Alpha Schedule roster Add dialog
Owner: `PersonSearch` (`app/lib/person_search.rb`), `Autocomplete::PersonAdapter` / `VehicleAdapter` / `AssetAdapter` / `ResponseBuilder` (`app/services/autocomplete/`), `SearchBarPolicy` (`app/lib/search_bar_policy.rb`)
Touches: `person`, `person_fka`, `email_history`, `person_photo`, `person_slot`, `slot`, `vehicle`, `asset`
Verify: `test/lib/person_search_test.rb`, `test/services/autocomplete/person_adapter_test.rb`, `test/controllers/autocomplete_controller_test.rb`, `test/lib/search_bar_policy_test.rb`, `test/services/autocomplete/vehicle_adapter_test.rb`
Trap: `AutocompleteController#search` is gated by `authorize_role` (`EVENT_MANAGEMENT`/`EVENT_MANAGEMENT_ON_PLAYA`); on top of that HQ mode (`SearchBarPolicy.hq_mode_available?`) and email/phone matching (`Current.can_view_email?`, `Current.can_view_pii?`) have their own gates.
Trap: The message recipient search (`search_callsigns_for_messaging`, `messageable_only`) lists only `Person.messageable`, the SQL twin of `Person#messaging_permitted?` (status and a first sign-in): change both together, or the search lists people a send refuses.
Trap: For a viewer who may see email, a query containing "@" runs only `search_email` / `search_old_email`, ignoring `search_fields` and `statuses` (`exclude_statuses` still applies) — a status-restricted caller still gets other statuses.

### Person record side effects (Person callbacks)
Used by: every page that saves a `person` row — Person › Edit Status and Edit Callsign (`Person::StatusesController`, `Person::CallsignsController`), Mark On Site / Off Site (`PersonController#toggle_onsite`), Me/Person › Profile (`ProfileSubjectConcern`), Me/Person › Change Password, HQ › On-Site Registration, Create Account and `/register`, bulk status and person-flag uploads (`BulkUpload::StatusHandler`, `BulkUpload::PersonFlagHandler`), SES bounces (`Infrastructure::AwsSnsController`); read back by Person › Site Log and Status History
Owner: `Person` (`app/models/person.rb`), `PersonOnSite` (`app/models/person_on_site.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `action_logs` (w), `person_status` (w), `email_history` (w), `person_on_site` (w), `person_fka` (w)
Verify: `test/models/person_test.rb`, `test/models/person_on_site_test.rb`, `test/controllers/person_controller_test.rb`, `test/controllers/person/site_log_controller_test.rb`, `test/models/application_record_audit_test.rb`
Trap: For an existing person, `Person` save callbacks write the `person_status`, `email_history`, `person_on_site` and `person_fka` rows — `update_columns` / `update_all` write no history; bulk `on_site` writers must call `PersonOnSite.reconcile`.
Trap: A save changing `sms_number` blanks `sms_code` and clears `sms_verified` / `sms_stopped` (`before_update :clear_sms_flags`) unless it assigns them — set a new verification code in the same save as the number.
Trap: the deliverable-address check (`EmailAddresses.sendable?`, said as `Person::EMAIL_MESSAGE`; refuses `name@gmailcom`, `a@b.c`, `a..b@example.com`) runs only when the email changes beyond case and surrounding spaces (`Person#email_changed_beyond_case?`), because `normalizes :email` applies on assignment and in queries, never to a value loaded from the database: Clubhouse 2 stored addresses as typed, and the identity form sends a stored `Name@GmailCom` back on every save, which `email_changed?` reads as a change. A stored address the rule refuses never blocks saving something else; the `URI::MailTo::EMAIL_REGEXP` format check still runs on every save. Test a legacy row with string-form `update_all("email = ...")` — `update_columns` runs the normalizer.

### Status change consequences (PersonStatusManagement)
Used by: every saved status change through `Person#log_status_change` (after_save) — Person › Edit Status (`Person::StatusesController`), People › Bulk Change Status (`BulkUpload::StatusHandler`), Mentoring › Convert Prospectives / Convert Alphas (`ProspectiveConversion`, `AlphaConversion`), `ShiftManage.convert_inactive_to_active`; explicit calls for new accounts in People › Create Account (`CreateAccountForm`) and `/register` (`RegisterForm`)
Owner: `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_team` (w), `person_team_log` (w), `person_slot` (w), `slot` (w), `person_event` (w), `handle_reservation` (w), `action_logs` (w)
Verify: `test/lib/person_status_management_test.rb`, `test/controllers/people/bulk_status_controller_test.rb`, `test/models/person_test.rb`, `test/controllers/mentoring/convert_prospectives_controller_test.rb`, `test/controllers/mentoring/alphas_convert_controller_test.rb`
Trap: `Person`'s after_save `log_status_change` already calls `PersonStatusManagement.change` for an existing person, so calling it again applies every grant, strip and history row twice; only brand-new accounts (which the callback skips) call it explicitly.
Trap: `person.audit_reason` becomes the `person_status` reason (otherwise "Status changed") — set it before saving a new status.

### Position & team grants (PersonPosition, PersonTeam, Membership)
Used by: Person › Manage Teams & Positions (`PersonMembershipForm` → `Membership.update_*_for_person`), Person › Overview and Me › Operational Summary (`Membership.retrieve_for_person`), Teams & Positions › Team Records / Position Records (`Membership.update_team_roles` / `update_position_roles`), Roster Management (`RosterAction`), Bulk Team / Bulk Position Grant / Revoke (`TeamManagement::BulkTeamChange`, `TeamManagement::BulkPositionChange`), Position Sanity Checker repairs (`PositionSanityCheck::*`), Training › Graduate Trainees and Current Mentees (`TrainingSession::Graduation`, `Training::MenteesController`), status-change defaults (`PersonStatusManagement`)
Owner: `PersonPosition.add_ids_to_person` / `remove_ids_from_person` (`app/models/person_position.rb`), `PersonTeam.add_person` / `remove_person` (`app/models/person_team.rb`), `Membership` (`app/lib/membership.rb`)
Touches: `person_position` (w), `person_position_log` (w), `person_team` (w), `person_team_log` (w), `team_manager` (w), `position_role` (w), `team_role` (w), `person_slot` (w), `slot` (w), `action_logs` (w), `position`, `team`
Verify: `test/controllers/person/memberships_controller_test.rb`, `test/lib/team_management/bulk_position_change_test.rb`, `test/lib/team_management/bulk_team_change_test.rb`, `test/models/role_cache_invalidation_test.rb`, `test/controllers/person_controller_test.rb`
Trap: `PersonPosition.add_ids_to_person` / `PersonTeam.add_person` raise `AuthorizationError` for a Tech Ninja or Admin position/team `Current.person` lacks, even with `Membership`'s `is_admin:` — rescue it in a transaction as `PersonMembershipForm#save` does.
Trap: `PersonPosition.remove_ids_from_person` `delete_all`s the rows, logs `person-position-remove` itself, and cancels future sign-ups per revoked position (`Scheduling::Signup::Bulk.remove_future_sign_ups_for_position`) — a revoke is never schedule-neutral.

### Service years (YearsManagement, AwardManagement)
Used by: model callbacks on every sign-up add or remove (`PersonSlot`), every timesheet save with a sign-out or delete (`Timesheet#rebuild_awards_and_years`) and every award save or delete (`PersonAward`), plus Person › Awards (`AwardManagement.rebuild_for_person_id`); the `person.years_*` columns feed the timesheet and schedule year selectors (`TimesheetConcern`, `ScheduleConcern`), Me › Clubhouse Dashboard stats, Quartermaster › Events Rangered / Freaking Years / Potential Swag, People › Retention / Status Change Recommendations / Bulk Lookup, Ticketing › SAP Candidates, Training › Graduate Trainees
Owner: `YearsManagement` (`app/lib/years_management.rb`), `AwardManagement` (`app/lib/award_management.rb`)
Touches: `person` (w), `action_logs` (w), `person_slot`, `slot`, `timesheet`, `position`, `person_award`
Verify: `test/lib/award_management_test.rb`, `test/controllers/person/awards_controller_test.rb`, `test/lib/reports/retention_report_test.rb`, `test/controllers/quartermaster/freaking_years_controller_test.rb`
Trap: `test/test_helper.rb` makes `update_signup_years`, `update_timesheet_years` and `update_years_of_awards` no-ops, so a test's `years_*` columns never follow the rows it creates — set them with `update_columns`.
Trap: `AwardManagement.rebuild_all` and `rebuild_for_person_id` are deliberate no-ops (matching upstream), so calls from `Timesheet`, `PersonTeam` (`TeamManagement.destroy` reaches it through the memberships `team.destroy!` destroys), `TrainerStatus` and Person › Awards grant no award; only `PersonAward` saves move `years_of_awards`.

### Bulk upload pages (BulkUpload)
Used by: Agreements › Bulk Record a Signature, People › Bulk Change Status, Certificates › Bulk Record Certifications, Ticketing › Bulk Access Documents and Bulk Provisions, BMID › Bulk BMID Actions, Vehicles › Bulk Vehicle Paperwork, Teams & Positions › Bulk Membership History (each controller includes `BulkUploadPage`; Bulk Team Grant / Revoke and Bulk Position Grant / Revoke do not)
Owner: `BulkUploadPage` (`app/controllers/concerns/bulk_upload_page.rb`), `BulkUpload::Batch` + `Entry` + `Action` (`app/lib/bulk_upload/`), a `BulkUpload::*Handler` per action family (`app/lib/bulk_upload/`)
Touches: `person` (w), `person_event` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_slot` (w), `provision` (w), `access_document` (w), `access_document_changes` (w), `bmid` (w), `person_certification` (w), `person_team_log` (w), `certification`, `action_logs` (w)
Verify: `test/controllers/people/bulk_status_controller_test.rb`, `test/controllers/ticketing/bulk_provisions_controller_test.rb`, `test/controllers/agreements/bulk_signature_controller_test.rb`, `test/controllers/teams_positions/bulk_membership_history_controller_test.rb`, `test/controllers/vehicles/bulk_paperwork_controller_test.rb`
Trap: Every POST (preview, apply, edit) answers 422 because Turbo drops a 200 to a form submission — tests assert `:unprocessable_entity` on success too; apply rebuilds the batch from its own params, not the preview.
Trap: The action arrives as `params[:bulk_action]` (Rails owns `params[:action]`); `BulkUpload::Batch` blocks `Person::LOCKED_STATUSES` rows before any handler runs, unless the handler's `refuses_locked_statuses?` is false (`BulkUpload::StatusHandler`).

### CSV export (CsvExportConcern)
Used by: about 60 report controllers across Timesheets, Scheduling, Training, Quartermaster, Shift Operations, VC, People, Asset Management, BMID, Vehicles, Ticketing, Teams & Positions and Certificates (`send_csv`), `SurveyReportingConcern`, and non-controller producers such as `TrsExport` (`CsvExportConcern.build`)
Owner: `CsvExportConcern` (`app/controllers/concerns/csv_export_concern.rb`)
Touches: none
Verify: `test/lib/trs_export_test.rb`, `test/controllers/vc/thank_you_cards_controller_test.rb`, `test/controllers/people/bulk_lookup_controller_test.rb`
Trap: The stdlib CSV library is deliberately unused — pass row arrays to `send_csv` (or `CsvExportConcern.build`) so cells opening with `= + - @` get the apostrophe guard; spell yes/no with `csv_yes_no`.

### Multi-year spans (EventYearSpan)
Used by: Timesheets › Top Hour Earners (`TopHourEarnersReport`), Teams & Positions › Special Teams Hours (`SpecialTeamsHoursReport`, `SpecialTeamsHoursForm`), People › Retention (`RetentionReport`) and Status Change Recommendations (`RecommendStatusChangeReport`), Ticketing › SAP Candidates (`SapCandidatesReport`), VC › Applications (`Vc::ApplicationsController`, `ProspectiveApplication` attendance window), and every year selector built with `skip_pandemic: true` (57 views across Scheduling, Timesheets, Training, Mentoring, VC, People, Quartermaster, Shift Operations and Communication, via `PageLayoutHelper#year_options`)
Owner: `EventYearSpan` (`app/lib/event_year_span.rb`)
Touches: `timesheet`
Verify: `test/lib/event_year_span_test.rb`, `test/lib/reports/top_hour_earners_report_test.rb`, `test/lib/reports/special_teams_hours_report_test.rb`, `test/lib/reports/retention_report_test.rb`, `test/models/prospective_application_test.rb`
Trap: `EventYearSpan.last_years(n, through:)` counts events, not calendar years (five through 2025 begins at 2019) — a `year - n` cutoff reaches into 2020/2021 and covers fewer events than meant.
Trap: `skip_pandemic:` only hides 2020 and 2021 in the selector; `ApplicationController#setup_year` still honours `?year=2020` — a page cannot assume `@year` had an event.

### Submitted id lists (IdList)
Used by: about 35 forms and controllers that take id lists — Person › Manage Teams & Positions and Edit Permissions, Teams & Positions › Team Records / Position Records / Position Lineups / Roster Management, Scheduling › Slots / Copy Slots / Bulk Edit Slots / Position Credits, Mentoring conversions, pods, acceptance sheets, mentor assignments and sign-out, People › Status Change Recommendations, Shift Operations › Mass Sign-Out / Cruise Direction / Payroll Export, Communication › RBS broadcast, Training › Mentees / Graduate Trainees, Ticketing › TRS Export / Un-Submit Provisions, BMID › Export, HQ › Shift Check In/Out; `IdList::Type` in `SpecialTeamsHoursForm`, `RbsBroadcastForm`, `PayrollExportForm`
Owner: `IdList` (`app/lib/id_list.rb`)
Touches: none
Verify: `test/lib/id_list_test.rb`, `test/controllers/person/memberships_controller_test.rb`, `test/controllers/person/permissions_controller_test.rb`, `test/controllers/teams_positions/team_records_controller_test.rb`, `test/controllers/shift_operations/mass_signout_controller_test.rb`
Trap: `IdList.parse` silently drops all but whole positive numbers, so in a set-replace editor "abc" revokes — first refuse junk with `IdList.clean?` (400) like `Person::MembershipsController#membership_params` and `Person::PermissionsController#permission_params`.
Trap: `scoped_params` answers `{}` for a malformed scope, which a set-replace editor reads as an empty list and revokes everything — use `params.expect`.

### Agreements (signature flags)
Used by: Me › Agreements (`Me::AgreementsController`), Person › Agreements (`Person::AgreementsController`), Agreements › Bulk Record a Signature (`BulkUpload::AgreementSignatureHandler`), signup intake Sandman affidavit check (`Scheduling::Signup`), Me › Vehicle Dashboard (`VehicleDashboard`)
Owner: `Agreements` (`app/lib/agreements.rb`)
Touches: `person` (w), `person_event` (w), `action_logs` (w), `document`, `slot`, `setting`
Verify: `test/lib/agreements_test.rb`, `test/controllers/me/agreements_controller_test.rb`, `test/controllers/person/agreements_controller_test.rb`, `test/controllers/agreements/bulk_signature_controller_test.rb`
Trap: Lifetime agreements are `person` flags, annual ones present-year `person_event` (`Agreements::DOCUMENTS[:term]`); `sign_agreement` always writes `Current.year`, and Person › Agreements' admin corrections are present-year only (`require_current_year_for`).
Trap: The dept NDA is offered by `has_raw_role?(EVENT_MANAGEMENT)` (the pre-wipe set); its writers (`sign_agreement`, `admin_set_signature`) call `PersonRole.clear_cache` after changing it so roles recompute — a new NDA writer must too.

### Vehicle eligibility (VehicleEligibility)
Used by: every request (`ApplicationController#build_menu_items` → `@me_show_vehicles`, which shows the Vehicle Dashboard menu item), Me › Vehicle Dashboard (`VehicleDashboard`), Person › Vehicles (`Person::VehiclesController`), dashboard vehicle tasks (`Milestones`), `PersonEventInfo` (Operational Summary, HQ shell, Person › Training), signup intake MVR notice (`Scheduling::Signup`), personal vehicle agreement offer (`Agreements`)
Owner: `VehicleEligibility` (`app/lib/vehicle_eligibility.rb`), `VehicleDashboard` (`app/models/vehicle_dashboard.rb`)
Touches: `person_event`, `person_team`, `team`, `person_slot`, `slot`, `position`, `setting`
Verify: `test/lib/vehicle_eligibility_test.rb`, `test/controllers/person/vehicles_controller_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`
Trap: `VehicleEligibility.is_person_eligible?` (menu flag) is cached per person and year, purged only by `PersonEvent` after_save and `Scheduling::ActiveRecordSlotStore` — MVR/PVR team changes leave it stale; `is_mvr_eligible?` / `is_pvr_eligible?` are uncached.
Trap: `retrieve_mvr_deadline` reads setting `MVR_DEADLINE` as a present-year "MM-DD" and answers `[nil, false]` when blank or unreadable, so the MVR sign-up notice and Vehicle Dashboard then never say the deadline has passed.

### Training status (Training)
Used by: Training › every per-position page (`Training::BaseController`, `Training::*Report`, `TrainingMenu`, `TrainingSession`), `Milestones` (dashboard), `Scheduling::Permission`, `SignInBlocker` / `ShiftManage`, `RoleManager` (`require_training_for_roles`), `Intake` (unified flagging), Mentoring (`AlphaShiftRoster`, `AlphaAcceptanceSheets`, `ProspectiveConversion`), `PersonEventInfo`
Owner: `Training` (`app/lib/training.rb`), `TraineeStatus` (`app/models/trainee_status.rb`), `TrainerStatus` (`app/models/trainer_status.rb`)
Touches: `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `person_position`, `timesheet`
Verify: `test/lib/training_test.rb`, `test/lib/training_menu_test.rb`, `test/models/trainee_status_test.rb`, `test/lib/training/completed_report_test.rb`
Trap: `Training.did_person_pass_for_year?` counts a trainer who attended a session (`TrainerStatus.taught?`) as passed — querying `TraineeStatus` alone undercounts.
Trap: `Training::EducationInfo#status` is the training status (`Training::PASS`/`FAIL`/`PENDING`/`NO_SHOW`/`NO_SHIFT`), not the stored `TraineeStatus::STATUS_*`; its `NO_SHOW` means a trainer missed teaching, and a trainee no-show reads `FAIL`.

### Online course LMS (Moodle)
Used by: Administration › Admin Menu › Online Courses (`Admin::OnlineCoursesController`), Person › Training / ARTs Moodle account tools (`Person::TrainingController`), Me › Online Course account setup and enrollment (`Me::OnlineCourseController`), the recurring completion scan (`MoodleCompletionJob`)
Owner: `Moodle` (`app/lib/moodle.rb`)
Touches: `person` (w), `person_online_course` (w), `action_logs` (w), `error_logs` (w), `online_course`
Verify: `test/lib/moodle_test.rb`, `test/jobs/moodle_completion_job_test.rb`, `test/controllers/admin/online_courses_controller_test.rb`, `test/controllers/person/training_controller_test.rb`, `test/controllers/me/online_course_controller_test.rb`
Trap: Moodle failures raise (`Moodle::DownForMaintenanceError`, `Moodle::ConnectFailureError`), unlike `Salesforce`'s false — rescue as `Admin::OnlineCoursesController#rescue_moodle_errors`, `Person::TrainingController#with_moodle_rescue`, `Me::OnlineCourseController#create`, `MoodleCompletionJob` do.
Trap: `process_course_completion` converts Moodle completion timestamps to America/Phoenix and skips any completion outside the course's year.

### Asset check-out / check-in (AssetManagementConcern)
Used by: Person › Assets (`Person::AssetsController`), HQ › Asset Check In/Out (`Hq::AssetsController`), HQ › On-Site Registration (`Hq::SiteRegistrationController`), HQ › Shift Check In/Out (`Hq::ShiftManageController`)
Owner: `AssetManagementConcern` (`app/controllers/concerns/asset_management_concern.rb`), `PersonAsset` (`app/models/person_asset.rb`), `Asset` (`app/models/asset.rb`)
Touches: `asset`, `person_asset` (w), `asset_attachment`, `action_logs` (w)
Verify: `test/controllers/person/assets_controller_test.rb`, `test/controllers/hq/assets_controller_test.rb`, `test/controllers/hq/site_registration_controller_test.rb`, `test/controllers/hq/shift_manage_controller_test.rb`
Trap: Checkout finds the barcode among the present year's assets only (`Asset.find_by_barcode_year(barcode, Current.year)`) and refuses an entity-assigned asset even with force — force overrides expiry only.
Trap: `locate_person_asset` reads `request.path_parameters` (`:person_asset_id` on HQ routes, `:id` on person routes) — a new route must name the row one of those two ways.
Trap: The table was `asset_person` until 2026-10-18 (`person_alert` was `alert_person`), and beta and amazon rename both in two deploys, because the release serving while a deploy migrates queries the old names: `20261018000001` and `000002` add `person_asset` and `person_alert` as views over the old tables, which the old release keeps using; the code that ships with them reads through the views with `ViewBackedTable` (on that deploy's branch only: Rails reads no primary key or auto-increment off a view, a view reports `id` DEFAULT 0, which Rails would insert as the id under `NO_AUTO_VALUE_ON_ZERO`, and with timestamp defaults an INSERT through the view does not return the id); `20261019000001` swaps each view for its table in one `RENAME TABLE`, renames the index and turns the `asset-person-*` audit events into `person-asset-*`. Dev ran the earlier versions of `000001` and `000002`, which renamed the tables, so `20261019000001` finds tables there and leaves them. The deploy order is the mailbox's (Clubhouse messages mailbox, the deploy Trap).

### Profile (ProfileSubjectConcern)
Used by: Me › Profile (`Me::ProfileController`), Person › Profile (`Person::ProfilesController`)
Owner: `ProfileSubjectConcern` (`app/controllers/concerns/profile_subject_concern.rb`), `ProfilePolicyConcern` (`app/controllers/concerns/profile_policy_concern.rb`)
Touches: `person` (w), `email_history` (w), `person_event`, `person_alert`, `swag`, `action_logs` (w)
Verify: `test/controllers/me/profile_controller_test.rb`, `test/controllers/person/profiles_controller_test.rb`
Trap: `Person::ProfilesController#set_is_me` sets `@is_me = false` even on your own record, so on /person/:id/profile every `can_view_*?` and `can_edit_profile?` answer comes from roles alone.

### BMID photo upload & crop (PhotoUploadConcern)
Used by: Me photo upload (`Me::PhotosController`), Person › Upload BMID Photo (`Person::PhotosController`), VC › Photo Review re-crop (`Vc::PhotosReviewController`)
Owner: `PhotoUploadConcern` (`app/controllers/concerns/photo_upload_concern.rb`), `PersonPhoto` (`app/models/person_photo.rb`)
Touches: `person_photo` (w), `active_storage_blobs` (w), `active_storage_attachments` (w), `person`
Verify: `test/controllers/me/photos_controller_test.rb`, `test/controllers/person/photos_controller_test.rb`, `test/controllers/vc/photos_review_controller_test.rb`, `test/models/person_photo_crop_test.rb`, `test/models/attachment_key_test.rb`, `test/models/person_photo_purge_test.rb`
Trap: the three files are stored at `photos/<filename>` (`staging/photos/<filename>` when `Current.is_staging?`), not under Rails' random token (`PersonPhoto#photo_key`, `AttachmentKey`). The filename is the key, and the key column is unique, so filenames take `Time.current`, never `Current.time`, which stands still on the training server; `original` is attached before the record saves, so no `id` can go in a key.
Trap: `convert_to_jpeg` bakes EXIF orientation in with `.autorot`, whose quarter turns need random access — never open the file with `access: :sequential`.
Trap: `create` takes JPEG, PNG and HEIC by the libvips decoder the file's bytes select, never the browser's `Content-Type`: any client sets that, and Chrome sends HEIC as `application/octet-stream`. `config/initializers/vips.rb` blocks every other decoder in every process, so `accepted_photo?` sees no loader for the rest, and it adds HEVC compression for HEIF, which rules out AVIF. The upload page's `accept` list is what `photo_upload_controller` checks a dropped file against, so keep it in step.
Trap: `crop`, `crop_save` and `destroy` act only on a pending photo (`is_pending?`), and `crop_save` deletes the subject's other pending uploads (`PersonPhoto.delete_pending`).
Trap: superseded and deleted photo files leave storage only through `ActiveStorage::PurgeJob` — the attachments take the `purge_later` default (never `dependent: :destroy`, which strands the blob), a re-crop calls `profile.purge_later` / `avatar.purge_later` (never `detach`), and `delete_pending` uses `destroy_all` so the attachment callbacks run.

### Passkeys (PasskeyRegistrationConcern)
Used by: passkey sign-in (`SessionsController#passkey_options`, `#passkey`), Account › Passkeys (`Me::PasskeysController`, `Me::ProfileController`), Person › Passkeys (`Person::PasskeysController`), the `:passkeys_enabled` menu flag (`ApplicationController#build_menu_items`)
Owner: `Passkeys` + `Passkeys::Registration` / `Authentication` / `Ceremony` (`app/lib/passkeys.rb`, `app/lib/passkeys/`), `PasskeyRegistrationConcern` (`app/controllers/concerns/passkey_registration_concern.rb`)
Touches: `person_passkey` (w), `sessions` (w), `action_logs` (w)
Verify: `test/lib/passkeys_test.rb`, `test/lib/passkeys/registration_test.rb`, `test/lib/passkeys/authentication_test.rb`, `test/controllers/me/passkeys_controller_test.rb`, `test/controllers/person/passkeys_controller_test.rb`
Trap: `Passkeys.enabled?` needs `RANGER_CLUBHOUSE_PASSKEY_ORIGIN` (dev/test: non-IP host) and no `Sso.client?`, else sign-in and Account › Passkeys 404 and the menu hides; Person › Passkeys still removes keys (`Person::PasskeysController#require_passkeys_enabled`).

### Provision CRUD (ProvisionCrudConcern)
Used by: Person › Tickets & Provisions and Person › BMID (`Person::ProvisionsController`, `Person::TicketsProvisionsController`, `Person::BmidsController`), BMID provisions (`Bmid::ProvisionsController`), Ticketing › Provisions (`Ticketing::ProvisionsController`)
Owner: `ProvisionCrudConcern` (`app/controllers/concerns/provision_crud_concern.rb`), `ProvisionManagementConcern` (`app/controllers/concerns/provision_management_concern.rb`), `Provision` (`app/models/provision.rb`)
Touches: `provision` (w), `action_logs` (w)
Verify: `test/controllers/person/provisions_controller_test.rb`, `test/controllers/person/tickets_provisions_controller_test.rb`, `test/controllers/bmid/provisions_controller_test.rb`, `test/controllers/ticketing/provisions_controller_test.rb`
Trap: `Person::ProvisionsController` returns to the `origin` param only if it is in `ProvisionManagementConcern::PROVISION_ORIGINS`, else silently to Tickets & Provisions — add a new person-side entry page there.

### Unified flagging (UnifiedFlaggingConcern, Intake)
Used by: VC › Unified Flagging (`Vc::UnifiedFlaggingController`), Training › In-Person Unified Flagging, read-only (`Training::UnifiedFlaggingController`), People › Unified Flagging, read-only, any status (`People::UnifiedFlaggingController`), Mentoring › Potential Alphas, Convert Prospectives, Alpha Status, Post Season Summary; `Intake` without the concern on Person › Unified Flagging (`Person::UnifiedFlaggingController`), Person › Add Note / Rank (`Person::IntakeNotesController`, `IntakeNoteForm`), Mentoring › Acceptance Sheets and Alpha Schedule (`AlphaAcceptanceSheets`, `AlphaShiftRoster` via `Intake.build_intake_team`)
Owner: `Intake` (`app/lib/intake.rb`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`)
Touches: `person`, `person_intake` (w), `person_intake_note` (w), `person_mentor`, `person_status`, `person_fka`, `person_slot`, `slot`, `position`, `timesheet`, `trainee_status`, `trainee_note`, `trainer_status`
Verify: `test/lib/intake_test.rb`, `test/helpers/intake_helper_test.rb` (the row's lead signal and team order), `test/controllers/vc/unified_flagging_controller_test.rb`, `test/controllers/training/unified_flagging_controller_test.rb`, `test/controllers/mentoring/potential_alphas_controller_test.rb`, `test/controllers/mentoring/convert_prospectives_controller_test.rb`, `test/controllers/people/unified_flagging_controller_test.rb`
Trap: `unified_flagging_read_only?` only hides the note controls — notes are written by `Person::IntakeNotesController`, which re-checks the team write roles itself.
Trap: A consumer must define `unified_flagging_path`, `unified_flagging_read_only?` and `unified_flagging_origin`, plus `unified_flagging_detail_path` when it renders `_detail_frame` (Convert Prospectives), or the views in `app/views/common/unified_flagging/` fail. The year selector's first year is the controller's `year_floor`, which `setup_year` also holds `?year=` to.
Trap: `?section=` as Intake's display group is read and applied only inside `unified_flagging_index_summaries(section_filter: true)`, never in the overridable `apply_unified_flagging_filters` — Post Season Summary's own `section` facet (the Mentors' verdict) uses the same key, and applying both hid people its tile counted. Its tokens are `unified_flagging_group_meta`'s keys (Intake's groups) whatever titles a page gives them; the shared tiles (`_group_tiles`), Section select and chips read the same hook.
Trap: A review line loads only the pane's frame (`Turbo-Frame: uf-pane`, HTML only — an export URL with the header gets its file), which `render_review_pane` answers with `_review_pane` alone. A consumer with its own `#index` must call `review_selection` and then `return render_review_pane(**extras) if review_pane_request?` before building its list, or every click renders the whole page and layout for Turbo to discard.
Trap: `Intake#display_group` counts a current UBERBONKED status as `:flagged`, as `IntakeHelper#intake_lead_kind` chips it — change one and the red chip lands in "Other potential Alphas".

### Survey feedback reports (SurveyReportingConcern)
Used by: Training › Surveys (`Training::SurveysController`), Mentoring › Alpha Surveys (`Mentoring::SurveysController`)
Owner: `SurveyBuilder` (`app/lib/survey_builder.rb`), `SurveyReportingConcern` (`app/controllers/concerns/survey_reporting_concern.rb`)
Touches: `survey`, `survey_group`, `survey_question`, `survey_answer`, `slot`, `trainer_status`, `person`
Verify: `test/controllers/training/surveys_controller_test.rb`, `test/controllers/mentoring/surveys_controller_test.rb`
Trap: The host must define `load_survey` and `authorize_survey_report`, which the concern registers, in that order, as before_actions on `report`/`trainer` — a class-level `authorize_role` alone does not authorize one survey's feedback.

### Model audit trail & year scoping (ApplicationRecord)
Used by: every model with `self.audit_model = true` (`Person`, `PersonSlot`, `Provision`, `Bmid`, `Asset`, `PersonAsset`, `Document`, `MailTemplate`, `Role`, `Survey` and others), read back by Administration › System Logs › Action Logs; `where_year` / `where_years` behind the datetime `for_year` scopes (`Timesheet`, `TimesheetMissing`, `EventDate`, `BroadcastMessage`, `BmidExport`, `PersonOnlineCourse`); `BLANK_WHEN_EMPTY_RICH_TEXT` for rich-text columns
Owner: `ApplicationRecord` (`app/models/application_record.rb`), `ActionLog` (`app/models/action_log.rb`), `GlobalRelationExtensions` (`config/initializers/active_record_extensions.rb`)
Touches: `action_logs` (w)
Verify: `test/models/application_record_audit_test.rb`, `test/models/action_log_test.rb`, `test/lib/where_year_test.rb`
Trap: Audit rows (`<table-name-dasherized>-create|update|delete`, e.g. `person-slot-delete`) come only from AR callbacks — `update_columns`, `update_all`, `insert_all` write none; `audit_reason` labels one; reports key on `person-slot-add` / `person-slot-remove`.
Trap: Rows are stored machine-local (`default_timezone = :local`) while `Time.zone` is Phoenix, so `Time.zone` bounds land an hour off and `YEAR(col)` cannot use an index — scope with `where_year(column, year)` (a `Time.local` range).

## Sign-in, accounts & site chrome

All controllers here but `Sso::ApiController` (`ActionController::API`) and Rails' `/up` inherit `ApplicationController`, whose `Authentication` concern demands a `sessions` row unless a controller skips `require_authentication`; none calls `authorize_role`. Every sign-in path refuses a `Person#locked?` account (`Person::LOCKED_STATUSES`: deceased, dismissed, resigned, suspended, uberbonked) through `Authentication#sign_in_refused?`, which writes an `auth-failed` `action_logs` row (Login Failures) and shows `locked_account_message` (403); a person locked while signed in is signed out on their next request (`Authentication#end_locked_session`, a before_action after `set_current_user`), as Clubhouse 2's `AccountGuard` did. A signed-in past prospective is sent to `/me` from every controller that does not skip `ApplicationController#confine_past_prospective`: the dashboard, the profile pages (profile, languages, password, passkeys, photos, alerts) and `SessionsController`. A locked person's open Action Cable connection is not dropped. `rate_limit` counts in `Rails.cache`, `null_store` in tests, so it never trips there. `app/controllers/me_controller.rb` is unrouted dead code — `/me` is `Me::DashboardController`.

### Sign In (password)
Reach it: `GET /` → site root, where `Authentication#request_authentication` sends every signed-out visitor; submit `POST /`
Gate: public; signed-in → /me (`redirect_if_authenticated`); `POST /` routed only while `!Sso.client?`; rate limit 10/45s on the one per-IP counter all `SessionsController` limits share (none passes `name:`)
Controller: `app/controllers/sessions_controller.rb` (`new`, `create`), `app/controllers/concerns/authentication.rb` (`start_new_session_for`, `after_authentication_url`)
Owner: `Person#authenticate` (`app/models/person.rb`), `Authentication#start_new_session_for` (`app/controllers/concerns/authentication.rb`), `LoginForm` (`app/forms/login_form.rb`)
Touches: `person` (w), `sessions` (w), `action_logs` (w)
Verify: `test/controllers/sessions_controller_test.rb`, `test/forms/dead_submit_removed_test.rb`
Trap: `Authentication#request_authentication` remembers the address to return to only for a page load (`returnable_request?`): a form post, frame, fetch or stream request goes back to /me after signing in, since its own address may be POST-only, a fragment or raw JSON.
Trap: `Person#authenticate` is not a pure check — a matching legacy SHA1 `salt:hash` password is rewritten to Argon2 with `save(validate: false)`, writing the `person` row.
Trap: `AuthenticationTestHelper` prepends a `find_session_by_cookie` override on `ApplicationController` that is never removed; it falls back to the real cookie only while no `sign_in_as` session is set, so a test mixing the two follows the helper's session.

### Sign In with a Passkey
Reach it: `POST /passkey/options` → sign-in page "Sign In with a Passkey" button (`sessions/_passkey_door`); device answer `POST /passkey`
Gate: public; routed only while `Passkeys.enabled?(request)` (`RANGER_CLUBHOUSE_PASSKEY_ORIGIN` set or a local env reached by host name, and not an SSO client), else 404; rate limit 10/45s on the per-IP counter shared with sign-in and `reset_password`
Controller: `app/controllers/sessions_controller.rb` (`passkey_options`, `passkey`)
Owner: `Passkeys::Authentication` (`app/lib/passkeys/authentication.rb`), `Passkeys` (`app/lib/passkeys.rb`), `PersonPasskey` (`app/models/person_passkey.rb`)
Touches: `person_passkey` (w), `person`, `sessions` (w), `action_logs` (w), `error_logs` (w)
Verify: `test/controllers/sessions_controller_test.rb`, `test/lib/passkeys/authentication_test.rb`, `test/lib/passkeys_test.rb`, `test/system/passkeys_test.rb`, `test/models/person_passkey_test.rb`
Trap: `Passkeys::Ceremony#keep_pending`/`take_pending` time the 5-minute challenge with real `Time.now` on purpose — the Groundhog Day clock is not a security clock; don't "fix" it to `Current.time`.
Trap: every passkey refusal must return the same `Passkeys::Authentication::UNRECOGNIZED` sentence, and the WebAuthn call stays inside `Ceremony#checked`'s wide `rescue StandardError` — the gem raises parser errors on forged input.

### Logout
Reach it: `DELETE /logout` → Account › Logout or the navbar "Hello <callsign>" menu, behind a confirm dialog
Gate: any signed-in person
Controller: `app/controllers/sessions_controller.rb` (`logout`)
Owner: `Authentication#terminate_session` (`app/controllers/concerns/authentication.rb`)
Touches: `sessions` (w)
Verify: `test/models/session_test.rb` covers the cable disconnect only — no test drives `DELETE /logout`
Trap: `terminate_session` destroys only this browser's `sessions` row and writes no `action_logs` row — other devices stay signed in until an Admin removes them at `/person/:person_id/login-sessions`.
Trap: destroying any `sessions` row closes every cable connection of its person (`Session`'s `after_destroy_commit`). A socket is identified only when it opens, so without it a tab left on Request Log › Live went on receiving after sign-out; the person's other devices reconnect at once under their own sessions.

### Reset Your Password (forgot password)
Reach it: `GET /forgot` → sign-in page "Forgot it?" link beside the Password label; request `POST /reset-password`; emailed link `GET /reset-token`; set `POST /update-password`; the welcome email's link `GET /reset-token?token=…&welcome=1`, worded as a welcome ("Welcome to the Ranger Secret Clubhouse", Set Password)
Gate: public; signed-in → /me; `reset-password` rate limit 5/60s on the per-IP counter shared with sign-in and passkey
Controller: `app/controllers/sessions_controller.rb` (`forgot`, `reset_password`, `reset_token`, `update_password`)
Owner: `Person#create_temporary_login_token` and `Person#password=` (`app/models/person.rb`), `PasswordResetMailer` (`app/mailers/password_reset_mailer.rb`), `WelcomeMailer` (`app/mailers/welcome_mailer.rb`), `PasswordResetForm`/`PasswordUpdateForm` (`app/forms/password_reset_form.rb`, `app/forms/password_update_form.rb`)
Touches: `person` (w), `sessions` (w), `action_logs` (w), `mail_template`, `setting`
Verify: `test/controllers/sessions_controller_test.rb`, `test/mailers/password_reset_mailer_test.rb`, `test/mailers/welcome_mailer_test.rb`, `test/models/person_test.rb`
Trap: a locked account (`Person#locked?`) is refused at both ends: `reset_password` mails no link and `update_password` sets no password, each 403 with `locked_account_message` — so Forgot tells anyone who types the address that the account is locked, as Clubhouse 2's `resetPassword` did.
Trap: `reset_password` answers an unknown address with "Email address not found." and 422, untested — "…with non-existent email still renders neutral confirmation" posts `no one@example.com`, which fails `PasswordResetForm`'s format check first.
Trap: `PasswordResetMailer.notify(...).deliver_now` is unrescued, so a mail failure is a 500 — "reset_password renders confirmation even when mailer raises" asserts `:internal_server_error`.
Trap: `welcome=1` changes words only: the tab title, heading, lede and button, the notice after the password is set, and the message on Forgot when the link fails (`SessionsController#link_failed_message`; `alert` from `GET /reset-token`, `error` from `POST /update-password`). `PasswordUpdateForm#welcome` carries it through a failed submit as a hidden field. The token check is the same, so a reset link given `welcome=1` by hand reads as a welcome.

### Sign In as Callsign & Clear Cache (development only)
Reach it: `GET /sign-in-as` → sign-in page footer callsign buttons and "Sign In as Callsign" form; `POST /clear-cache` → Account › Clear Cache
Gate: routes drawn only `if Rails.env.development?` (`config/routes.rb`), re-checked per action; `sign-in-as` public, `clear-cache` needs sign-in (menu: computed `is_development`)
Controller: `app/controllers/sessions_controller.rb` (`sign_in_as`, `clear_cache`)
Owner: inline in controller — `Person.retrieve_by_callsign` (`app/models/person.rb`), `Rails.cache.clear`
Touches: `person`, `sessions` (w), `action_logs` (w)
Verify: none — no test exercises this feature
Trap: `SessionsController` runs `redirect_if_authenticated` before every action but `logout`, so signed-in `GET /sign-in-as?callsign=X` lands on /me still as the first person and `POST /clear-cache` never runs — sign out before using sign-in-as.

### Auditor Registration
Reach it: `GET /register` → sign-in page "Auditing a training? Create an account" link; submit `POST /register`
Gate: public; signed-in → /me; closed (503, `closed` step) when setting: `AUDITOR_REGISTRATION_DISABLED` is on or on the Groundhog Day clock (`Current.is_ghd_server?`); `create` rate limit 5/60s
Controller: `app/controllers/register_controller.rb` (`show`, `create`)
Owner: `RegisterForm` (`app/forms/register_form.rb`), `PersonStatusManagement.change` (`app/lib/person_status_management.rb`), `AccountCreationMailer` (`app/mailers/account_creation_mailer.rb`)
Touches: `person` (w), `person_status` (w), `person_role` (w), `person_position` (w), `person_position_log` (w), `action_logs` (w), `setting`
Verify: `test/controllers/register_controller_test.rb`, `test/forms/register_form_test.rb`
Trap: the intent answer is stored nowhere (no column), despite the `INTENT_OPTIONS` comment's "the stored value" — `RegisterForm#announce_new_account` only puts it in the `AccountCreationMailer` note (`deliver_later`).
Trap: the new auditor is not signed in, and the success step reads then deletes `session[:registered_callsign]`, so reloading `?step=success` sends the reader back to the intent step.

### Single Sign-On Server (sign-in for other websites)
Reach it: `GET /sso/authorize` → from a registered OAuth client site (learning site, HQ ticket desk) with `client_id`/`redirect_uri`; `POST /sso/token`; `GET /sso/userinfo`; `GET /.well-known/openid-configuration`
Gate: `authorize`: any signed-in person not `Person#locked?` nor a past prospective (signed out → sign in, then back; locked → signed out by `end_locked_session`, no code; past prospective → `/me` by `confine_past_prospective`); `token`: client id + secret as form fields or HTTP Basic, rate limit 600/min; both need `redirect_uri` equal to the client's recorded one, any address when that is blank (`OauthClient#accepts_redirect_uri?`); `userinfo`: Bearer token from `Person.generates_token_for(:sso_access)`; `discovery`: public
Controller: `app/controllers/sso_controller.rb` (`authorize`), `app/controllers/sso/api_controller.rb` (`discovery`, `token`, `userinfo`)
Owner: `OauthCode` (`app/models/oauth_code.rb`), `OauthClient` (`app/models/oauth_client.rb`), `Person#sso_claims` (`app/models/person.rb`)
Touches: `oauth_client`, `oauth_code` (w), `person`, `action_logs` (w), `error_logs` (w)
Verify: `test/controllers/sso_controller_test.rb`, `test/controllers/sso/api_controller_test.rb`, `test/models/oauth_code_test.rb`, `test/models/oauth_client_test.rb`, `test/lib/sso_test.rb`
Trap: `Sso.mode` is fixed at `"server"` (`app/lib/sso.rb`), so `RANGER_CLUBHOUSE_SSO_MODE` and `SsoTestHelper#set_sso_mode` change nothing and all six SSO routes always answer — the per-mode 404 comment in `config/routes.rb` is stale.
Trap: `ErrorLog.record(request:)` stores unfiltered `request.parameters` and every `HTTP_` header, so a refused `/sso/token` logs the tried `client_secret` and `code` in `error_logs` — despite the "without the secret" test name and `authenticate_client`'s comment.

### Sign In with the Ranger Clubhouse (SSO client)
Reach it: `GET /sso/login` → "Sign In with the Ranger Clubhouse" button (`sessions/_sso_door`, shown only when `Sso.client?`); return `GET /sso/callback`
Gate: public; signed-in → /me; `state` must match `session[:sso_state]`; rate limit 10/45s
Controller: `app/controllers/sso_controller.rb` (`login`, `callback`)
Owner: `Sso::Client` (`app/lib/sso/client.rb`), `Sso` (`app/lib/sso.rb`)
Touches: `person`, `sessions` (w), `action_logs` (w), `error_logs` (w)
Verify: `test/controllers/sso_controller_test.rb`, `test/lib/sso/client_test.rb`, `test/lib/sso_test.rb`
Trap: `Sso.client?` is always false, so the sign-in page never shows `sessions/_sso_door` and a refused callback (a locked person included, 403) renders the password form without its `@sso_error` reason; `/sso/login` still answers by URL.
Trap: `Sso.validate!` (`config/initializers/sso.rb`) returns before checking the five `RANGER_CLUBHOUSE_SSO_*` client variables, since the mode is never client — a missing one is never caught at boot.

### Bookmark Kiosk
Reach it: `GET /bookmark/:tag` → Administration › Admin Menu › Documents, "Open" beside a `bookmark-` document; timer refresh `GET /bookmark/:tag/document`
Gate: public; only documents tagged `bookmark-<tag>` (prefix added server-side, `Document::BOOKMARK_TAG_PREFIX`)
Controller: `app/controllers/bookmarks_controller.rb` (`show`, `document`)
Owner: `Document` (`app/models/document.rb`), `bookmark_controller.js` (`app/javascript/controllers/bookmark_controller.js`)
Touches: `document`
Verify: `test/controllers/bookmarks_controller_test.rb`, `test/models/document_test.rb`
Trap: the controller skips `set_current_user` and `build_menu_items`, so `Current.person` and `@menu_context` are nil even with a sign-in cookie — the `bookmark` layout and views must not need the signed-in person.
Trap: `bookmarks/_document` prints `document.body.html_safe`, sanitized by neither `Document` nor `Admin::DocumentsController`, so a `bookmark-` document's body is served unescaped, without sign-in, to anyone who knows the tag.

### Search Bar (autocomplete)
Reach it: `GET /autocomplete/search` → navbar Search button or Ctrl/Cmd+K (`application/_search_bar_placeholder` in `application/_top_menu`; `search_bar_controller.js` + `autocomplete_controller.js`)
Gate: `EVENT_MANAGEMENT`/`EVENT_MANAGEMENT_ON_PLAYA` (controller `authorize_role`; menu: bar only when `SearchBarPolicy.allowed?`, the same `Current.has_event_management?`); `mode=hq` needs setting: `HQ_WINDOW_INTERFACE_ENABLED` + `ADMIN`/`SHIFT_MANAGEMENT`
Controller: `app/controllers/autocomplete_controller.rb` (`search`)
Owner: `Autocomplete::PersonAdapter` (`app/services/autocomplete/person_adapter.rb`), `PersonSearch` (`app/lib/person_search.rb`), `SearchBarPolicy` (`app/lib/search_bar_policy.rb`)
Touches: `person`, `person_fka`, `email_history`, `person_photo`, `person_slot`, `slot`, `vehicle`, `person_event`, `asset`, `person_asset`, `setting`
Verify: `test/controllers/autocomplete_controller_test.rb`, `test/services/autocomplete/person_adapter_test.rb`, `test/lib/search_bar_policy_test.rb`, `test/system/search_bar_hotkey_test.rb`, `test/system/search_bar_failure_test.rb` (offline, server error, signed out), `test/lib/person_search_test.rb`
Trap: signed out, `search` answers 401, not the sign-in redirect (`AutocompleteController#request_authentication`). The search bar cancels the autocomplete's `autocomplete.error` and shows one of its `application/_dialog_status` callouts by the event's `kind`; any `input` event in the dialog takes the callout down, and Try Again runs `autocomplete#refetch` through an outlet (same text and filter chip — replaying a keystroke would drop the chip). A search still out after 10 seconds says so in the autocomplete's own Searching row, not a callout: a button at the dialog's foot would take focus out of the combobox, whose focusout calls the search off.
Trap: `AutocompleteController#adapter_for` picks by first character: `!` → `Autocomplete::VehicleAdapter`, `#` → `Autocomplete::AssetAdapter`, else (incl. `+id`) people; vehicle/asset use the present year unless the query ends `:YYYY`; only people reroute per mode.

### Menu (mega menu) & Favorites
Reach it: `GET /me/menu` → navbar Menu button or Ctrl/Cmd+Shift+K (lazy Turbo Frame in `application/_mega_menu`); star a link or a category heading `POST /me/favorites/toggle` (each star is a `<button>` that submits `#mega-menu-star-form` through its own `formaction`)
Gate: any signed-in person, and signed out both actions answer 401, not the sign-in redirect (`MegaMenuConcern#request_authentication`); categories and items filtered by `visible_if` through `MenuBuilder`; `toggle` answers 422 for a path or `category:<panel key>` not among the person's visible links or categories. The navbar offers the menu — both triggers, the dialog, the `mega-menu` controller and its Ctrl/Cmd+Shift+K — only to a person with a visible category beyond My Clubhouse and Account (`MegaMenu.offered?`, asked once per page through `MegaMenuHelper#mega_menu_offered?` by `application/_top_menu` and the tour partial; those two are the sidebar and the user dropdown), so a Ranger with no roles gets none of it, though `GET /me/menu` still answers
Controller: `app/controllers/me/menu_controller.rb` (`show`), `app/controllers/me/favorites_controller.rb` (`toggle`), `app/controllers/concerns/mega_menu_concern.rb`, `ApplicationController#track_page_visit` (`app/controllers/application_controller.rb`)
Owner: `MegaMenu` (`app/lib/mega_menu.rb`), `MegaMenuConcern` (`app/controllers/concerns/mega_menu_concern.rb`), `PersonFavorite` (`app/models/person_favorite.rb`)
Touches: `person_favorite` (w), `person_page_visit` (w), `position`, `setting`
Verify: `test/controllers/me/menu_controller_test.rb`, `test/controllers/me/favorites_controller_test.rb`, `test/system/mega_menu_favorite_test.rb`, `test/system/mega_menu_hotkey_test.rb`, `test/system/mega_menu_failure_test.rb` (offline, signed out), `test/lib/mega_menu_test.rb` (`offered?`), `test/integration/top_menu_test.rb` (the bar without it), `test/controllers/training/sessions_controller_test.rb` (training stars, recents, repeated titles), `test/models/person_favorite_test.rb`, `test/models/person_page_visit_test.rb`
Trap: opening the menu writes — `MegaMenuConcern#build_mega_menu` calls `PersonFavorite.prune_stale!` every build, hard-deleting stars for links or categories the person can't see right now, even ones hidden only by a Setting or computed flag — and for training, a position renamed or deactivated, or an ART or seasonal Trainer role ended.
Trap: `MegaMenu.linkable?` admits Symbol route-helper `path`s and app-relative String paths (a single leading `/`; only `TrainingMenu` builds them) with no `confirm:` or `data: { turbo_method: }` — Logout and Clear Cache get no star or Recent entry. `MegaMenu.tracked_paths` memoizes only `Menus::MEGA_CATEGORIES`; training pages are tracked by `Training::BaseController#tracked_page?` and never belong in it.
Trap: failures show as callouts inside the dialog (`application/_dialog_status`, shared with the search bar; `dialog_controller#showError` picks one), chosen by `mega_menu_controller` from the Turbo fetch events on the dialog: offline, server error, signed out (the 401), and still loading after 10 seconds. The slow timer runs until the menu content arrives (`searchTargetConnected`), not until `turbo:before-fetch-response`: that comes with the headers, and a body that stalls sends no event. Never `preventDefault` `turbo:fetch-request-error` there — a lazy frame whose first visit never settles ignores `reload()`, which is why `retry()` turns a never-rendered frame eager instead. The star form sits in the dialog, outside the frame: a form a reload swapped out sends its Turbo events to `<html>`, past the dialog's handlers. `dialog_controller` resets the callouts before Turbo caches the page, and closes on a backdrop click only when the click lands outside the dialog's box.
Trap: Turbo disables a submitting button, which drops its focus — `mega_menu_controller#rememberStar` (on `turbo:submit-start`) puts focus back on the re-rendered star, and `starSubmitted` (on `turbo:submit-end`) on a star whose toggle failed (not one the next star called off, which ends with neither an answer nor an error); don't remove it thinking Turbo's own restore-by-id covers it.

### Bug Report
Reach it: `GET /bug-reports/new` → navbar Bug Report button ("Report a Bug" dialog in the layout's modal frame); send `POST /bug-reports`
Gate: any signed-in person
Controller: `app/controllers/bug_reports_controller.rb` (`new`, `create`)
Owner: `BugReport` (`app/models/bug_report.rb`)
Touches: `bug_report` (w)
Verify: `test/controllers/bug_reports_controller_test.rb`, `test/integration/top_menu_test.rb`
Trap: `BugReportsController#reported_from` keeps only the Referer's path, dropping the query string on purpose (it can carry a token) — do not widen the report's `url` to the full URL.

### Health Check (/up)
Reach it: `GET /up` → load balancers and uptime monitors (no link)
Gate: public
Controller: `Rails::HealthController` (`show`; framework class, no file in `app/controllers`)
Owner: `Rails::HealthController` (railties)
Touches: none
Verify: none — no test exercises this feature
Trap: `/up` only proves the app booted — `Rails::HealthController` never touches the database, so a down MariaDB still answers 200; `RequestLogger::SKIP_PATHS` (`lib/middleware/request_logger.rb`) keeps it out of `request_log`.

### Test Harness Fixtures (test env only)
Reach it: `GET /test_harness/autocomplete` → visited directly by system tests (absent from routes.txt); `GET /test_harness/search_bar`
Gate: public (`require_authentication` skipped); routes drawn only under `Rails.env.test?`
Controller: `app/controllers/test_harness_controller.rb` (`autocomplete_fixture`, `search_bar_fixture`)
Owner: inline in controller — layout-free views `app/views/test_harness/autocomplete_fixture.html.erb` and `app/views/test_harness/search_bar_fixture.html.erb`
Touches: none
Verify: `test/system/autocomplete_component_test.rb`, `test/system/search_bar_hotkey_test.rb`
Trap: the fixtures render the real `shared/_autocomplete` and `application/_search_bar_placeholder` partials with their own locals — a new required local in either breaks these pages and their system tests too.

### Inbound SMS (Twilio webhook)
Reach it: `POST /infrastructure/sms/inbound` → Twilio's inbound-message webhook (no page); commands STOP/START/HELP/NEXT/STATS
Gate: public (CSRF skipped); known crawler user agents get 403, then anything without a valid `X-Twilio-Signature` (`TwilioSignatureConcern`), and everything while the TwilioAuthToken setting is blank; `stats` reply needs `ADMIN`
Controller: `app/controllers/infrastructure/sms_controller.rb` (`inbound`)
Owner: inline in controller — `TwilioSignatureConcern` (`app/controllers/concerns/twilio_signature_concern.rb`), `SmsService` (`app/lib/sms_service.rb`), `BroadcastMessage` (`app/models/broadcast_message.rb`), `Scheduling::Query.find_next_shift` (`app/lib/scheduling/query.rb`)
Touches: `setting` (TwilioAuthToken), `person` (w), `broadcast_message` (w), `broadcast`, `person_slot`, `slot`, `position`, `person_role`, `error_logs` (w)
Verify: `test/controllers/infrastructure/sms_controller_test.rb`
Trap: the signature is checked by twilio-ruby's `Twilio::Security::RequestValidator` with the auth token over every posted parameter (`request.request_parameters`, never a list: Twilio adds new ones without notice), against `TwilioSignatureConcern.address`: https on the mail host (`config.action_mailer.default_url_options`: `RANGER_CLUBHOUSE_HOST` in production, else `clubhouse3.dev`) and the path and query as requested. Never `request.url`: Rails builds it from Host and X-Forwarded-Host, so a text Twilio signed for another server, replayed under that server's name, would pass. Twilio must be given exactly that address, which SMS Management fills in and calls "This server". Point Twilio at any other name this server answers at, or rotate the auth token at Twilio without changing the setting, and every text is refused, which Twilio's alerts report as error 11217 or 11200.
Trap: a refusal is a 403 and one `error_logs` row (`twilio-signature-invalid`, or `twilio-auth-token-not-configured`) holding the address checked without its query, and whether a signature came at all (`signed`): never the parameters, which hold the text, and no `request:`, which would copy them in.
Trap: Twilio posts here only once Administration › SMS Management's Update Incoming Address points the Messaging Service at this address; on 2026-10-25 the live account still posted incoming texts to Clubhouse 2.
Trap: `Person.find_by_sms_number` matches `person.sms_number` exactly to `From`; `Person#mark_sms_stopped!` flips `person.sms_stopped` via `update_columns` (no audit row); legacy `sms_on_playa`/`sms_off_playa` and their `*_stopped` flags are ignored.

### Text delivery receipts (Twilio status callback)
Reach it: `POST /infrastructure/sms/status?message=<broadcast_message.id>` → the status callback address every text carries (no page)
Gate: public (CSRF skipped), the same `Infrastructure::SmsController` gates as Inbound SMS: crawler user agents get 403, then anything without a valid `X-Twilio-Signature` (`TwilioSignatureConcern`, over the address with its query), and everything while TwilioAuthToken is blank
Controller: `app/controllers/infrastructure/sms_controller.rb` (`receipt`)
Owner: `SmsService.process_status_callback` and `receipt_address` (`app/lib/sms_service.rb`), `BroadcastMessage.record_receipt` (`app/models/broadcast_message.rb`)
Touches: `broadcast_message` (w), `broadcast` (w, only after a failed receipt), `setting` (TwilioAuthToken), `error_logs` (w, refusals)
Verify: `test/controllers/infrastructure/sms_controller_test.rb`, `test/lib/sms_service_test.rb`
Trap: added 2026-10-26 (SMS Management issue 08). `SmsService.text_through` passes `status_callback:` only with `receipt_for:` (the row's id) and only while `SmsService.receipt_address` is not nil, which it is wherever `SmsManagement.incoming_url_problem` refuses the mail host (dev's localhost): asking from there would raise an 11200 alert on the live account for every text. So every text's row is written before it goes: a broadcast's rows are `queued`, then `send-unconfirmed` while in flight; a new-message alert's and a confirmation code's are written `send-unconfirmed` (a refused code is now `service-fail`, where it once wrote no row).
Trap: the row's id rides in the signed address's query (read from `request.query_parameters`, never the body, which is Twilio's), and `record_receipt` moves only the row whose id AND `message_id` (the SID) both match, from `sent` (or a code's `verify`) to `delivered`, `blocked` (30004), `bounced` (30005-30007) or `failed`: one indexed update. Anything earlier (`queued`, `sending`, `sent`; none comes for `accepted`), a repeat, a row not yet settled (no SID until Twilio answered), a stranger's SID or an unknown id changes nothing and is still answered 204. A receipt that beats the job's own write of the SID is lost; issue 11's recheck catches it.
Trap: `failed` is the one receipt that is a failure (`Broadcast::FAILURE_STATUSES`, retryable): it recounts its broadcast's `sms_failed` (`Broadcast.recount_failed_texts`), two more queries. `blocked` and `bounced` are not, as an email's bounce is not; `delivered` counts as an attempt (`Broadcast::ATTEMPTED_STATUSES`).

### SES Mail Events (AWS SNS webhook)
Reach it: `POST /infrastructure/aws-sns` → the SNS topic SES publishes Delivery/Bounce/Complaint events to (no page)
Gate: public (CSRF skipped); the message must verify against its AWS signing certificate and its `TopicArn` must equal setting: `SES_SNS_TOPIC_ARN`
Controller: `app/controllers/infrastructure/aws_sns_controller.rb` (`notification`)
Owner: `SnsMessage` (`app/lib/sns_message.rb`), `MailLog` (`app/models/mail_log.rb`), `BroadcastMessage` (`app/models/broadcast_message.rb`), `EmailSuppression` (`app/models/email_suppression.rb`)
Touches: `mail_log` (w), `broadcast_message` (w), `email_suppression` (w), `person` (w), `action_logs` (w), `error_logs` (w), `setting`
Verify: `test/controllers/infrastructure/aws_sns_controller_test.rb`, `test/models/email_suppression_test.rb`
Trap: until setting `SES_SNS_TOPIC_ARN` is filled in, `authentic?` refuses every message (403, `sns-topic-not-configured` in `error_logs`), even the SubscriptionConfirmation — so the subscription never goes live.
Trap: Delivery reports only stamp `mail_log`, deliberately writing no `action_logs` row; a Permanent bounce also sets `person.is_bouncing` (until that column is removed: nothing new may read it); a verified message of an unknown type still answers 200 so SNS stops redelivering.
Trap: every Permanent bounce, whatever its `bounceSubType` (`OnAccountSuppressionList` included), and every Complaint upserts one `email_suppression` row per address (`EmailSuppression.record`, one `INSERT … ON DUPLICATE KEY UPDATE`); Transient and Undetermined bounces, a Slack address (`IGNORED_DOMAINS`) and anything `authentic?` refuses write none. The key is the address the Clubhouse sent to: the one entry in `mail.destination`, parsed with `Mail::Address` to drop the display name RBS puts there (`SnsMessage#sent_address`), else the reported `emailAddress`, which SES takes from Final-Recipient and a forwarder can change. `MailLog.mark_as_bounced`/`mark_as_complaint` and `BroadcastMessage.mark_email_bounced` still go by the reported address, so a forwarder's bounce writes the row while the `mail_log` row stays unbounced and the `broadcast_message` row stays `sent` (accepted). A complaint sets `reason` to `complaint`, and a bounce never changes an existing row's reason, so SES's `OnAccountSuppressionList` bounce for a complainer leaves it `complaint`. A report whose `mail.messageId` equals the stored `message_id` is SNS redelivering it and changes nothing; any other report moves `last_reported_at`, `sub_type` and `message_id` and adds 1 to `report_count` (MariaDB applies the assignments left to right, so `message_id` is compared before it is overwritten). The app makes no AWS call: SES's own account-level list keeps complaints, and clearing a row never removes an address there.
Trap: `email_suppression` rows never expire and stay when their person changes address; only the clear on Person › Overview deletes one. The table was seeded once from `person.is_bouncing` (`EmailSuppression.copy_bouncing_flags`, called by the data migration `CopyBouncingFlagsToEmailSuppression` after its clock check): a flag is copied only when a Permanent `email-bouncing` action log names the person's current address, dated from the first and last such log, and never over an existing row. Readers ask `EmailSuppression.suppressed(addresses)` (one query, answering the caller's own strings, so a Clubhouse 2-era mixed-case address still matches) or `suppressed?`. `SuppressedRecipientsInterceptor` reads it too, for every ActionMailer email, and drops the recipients it holds (see Transactional mail); RBS reads it when it works out a broadcast's recipients, and once per new-message alert whose email is on (`message_notify`), both recording the skip as `suppressed` (see Ranger Broadcast System (Rbs)), but a Retry doesn't. Tests write rows with `EmailSuppressionTestHelper#suppress_email`, never fixtures.
Trap: A report matches `mail_log` on `message_id` and `to_email` together, and every row holds one address. RBS broadcast emails store the id SES assigned, and so do the rows every other email gets from `ApplicationMailer#record_mail_log` (`MailLog.record_delivery`, `deliver_now` and `deliver_later` alike) when it went through the `:ses_mail` delivery method (`SesMailDelivery`); a bounce on one of those moves no `broadcast_message` row, having no `broadcast_id`. While production sends that mail by SMTP — until `RANGER_CLUBHOUSE_SES_MAIL_LIVE` turns on `config.x.ses_mail_live` — its rows hold the mail gem's Message-ID and never match. Under the all-mail test address (`RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS`) the row and SES's report both name the test inbox, so they still match (see MailLog).
Trap: a Bounce of any type (Permanent, Transient or Undetermined) for an RBS email also moves its `broadcast_message` row from `sent` to `bounced` (`BroadcastMessage.mark_email_bounced`, given the `mail_log` row `MailLog.mark_as_bounced` returned). The match is that row's `broadcast_id` (indexed), `person_id` and `message_id` — never `broadcast_message.message_id` alone, which has no index, and never the person found by the bounced address, which in test address mode is nobody's — so it takes the exact copy, also after a Retry gave the row a new id; a row with no `broadcast_id`, or none at all, changes nothing, and a repeated report finds no `sent` row. A bounce is not a failure: nothing recounts `email_failed` and Retry never sends it (see RBS › Broadcast history). A Complaint changes no row — the email arrived; it stays on `mail_log.did_complain` and the `email-complaint` action log.

## My Clubhouse: dashboard & profile

Plain `ApplicationController`s with `layout "me"`, acting on `current_user` with no `authorize_role`: sign-in (`Authentication#require_authentication`) is the only shared gate, except that a past prospective reaches only the dashboard and the profile pages (`ApplicationController#confine_past_prospective`, skipped by those controllers; the menu hides the rest); year-keyed writes use `Current.year`. Most share a concern or templates with a `/person/:id/...` twin (`ProfileSubjectConcern`, `Alerts::EditingConcern`, `PhotoUploadConcern`, `PasskeyRegistrationConcern`, `WorkHistoryConcern`, `app/views/profile_languages/`), so changes reach it too.

### Clubhouse Dashboard
Reach it: `GET /me` → My Clubhouse › Essentials › Clubhouse Dashboard
Gate: any signed-in person; `Dashboard#type` picks tasks by status (past prospective, bonked/uberbonked: no tasks, only a status partial and help contacts)
Controller: `app/controllers/me/dashboard_controller.rb` (`index`)
Owner: `Milestones` (`app/lib/milestones.rb`), `Dashboard` (`app/lib/dashboard.rb`), `DashboardTasks::<Name>` (`app/lib/dashboard_tasks/<name>.rb`; runs only if listed in `Dashboard::RANGER_STEPS`, `ECHELON_STEPS`, `APPLICANT_TASK_GROUPS`, `AUDITOR_STEPS` or `AUDITOR_OFFSEASON_STEPS`; a `check(facts)` verdict's `partial: "x"` renders `app/views/dashboard_tasks/_x.html.erb` via `app/views/common/_dashboard_step.html.erb` with `step:`, `facts:`)
Touches: `person_event`, `person_photo`, `person_online_course`, `person_position`, `slot`, `person_slot`, `trainee_status`, `timesheet`, `access_document`, `bmid`, `vehicle`, `survey`, `document`, `setting`, `motd`, `person_motd`
Verify: `test/controllers/me/dashboard_controller_test.rb`, `test/lib/dashboard_test.rb`, `test/lib/milestones_test.rb`, `test/lib/dashboard_tasks/partial_coverage_test.rb`, `test/lib/dashboard_facts_test.rb`
Trap: `period`/`skip_period` filter only ranger/echelon steps (`Dashboard#process_step_group`), not applicant/auditor ones; `EventDate.calculate_period` never yields `post-event` — only the `DashboardPeriod` setting does.
Trap: Neither `partial_coverage_test.rb` (file exists) nor `test/lib/dashboard_tasks/*_test.rb` (`check` only) renders, so a partial reading a fact `DashboardFacts` lacks 500s `/me` and Person › Dashboard — use `DashboardRenderTest` or `/me` as a ranger.

### Onboarding tour (first sign-in)
Reach it: `GET /me`, on the first visit by anyone whose `person.on_boarded_at` is nil; again at `GET /me?tour=1` → Account › Replay Onboarding; recorded by `PATCH /me/onboarded`; cleared by an Admin or VC at Person › Overview › Actions › Reset Onboarding Tour
Gate: any signed-in person whose dashboard is the ranger, applicant or auditor shape (`Dashboard#type`): bonked and past-prospective people get no tour (their branch of `me/dashboard/index` renders without it) and no Replay item (`Menus::USER`, `not_status: [:past_prospective?, :is_any_bonked?]`); the Menu step only for a person the navbar offers the menu to (`mega_menu_offered?`) — a Ranger with no roles has no Menu button to point at
Controller: `app/controllers/me/dashboard_controller.rb` (`index` renders `me/dashboard/_onboarding`; `onboarded`)
Owner: `app/javascript/controllers/onboarding_controller.js` over the vendored driver.js (`app/javascript/vendor/driver-1.10.1.js`, pinned in `config/importmap.rb`; its sheet `app/assets/stylesheets/driver.css`, re-themed by `app/assets/stylesheets/components/driver.css`); the steps and their copy in `app/views/me/dashboard/_onboarding.html.erb`, varying by `Dashboard#type` and `Person#is_echelon?`
Touches: `person` (w)
Verify: `test/controllers/me/dashboard_controller_test.rb`, `test/system/me/onboarding_tour_test.rb`; the reset in `test/controllers/person_controller_test.rb`
Trap: every way the tour ends in the page records it (a full-page reload mid-tour does not), through driver's `onDestroyStarted`, not `onDestroyed` — driver.js skips the latter when the tour is destroyed before the current step's highlight has settled (a quick ×, as a tester does); with the former set, the controller destroys the tour itself (`finish`, also its `turbo:before-cache` action). `onboarded` writes with `update_column` on purpose (`Person.audit_model`; self-service bookkeeping like `last_seen_at`); a replay carries no url value and writes nothing. Done alone also scrolls the drawer pane back to the top and shows the success toast the partial renders into a `<template>` (cloned into the layout's `toast-container`); a dismissal does neither.
Trap: a step's `data-element` resolves to its first *visible* match (`checkVisibility` with the visibility and opacity options, since daisyUI parks the phone drawer with both), and a step with none is dropped silently: the hooks are ids — `#sidebar-toggle`, `#menu-open`, `#menu-open-phone` (`application/_top_menu`), `#sidebar-drawer-content` (`sidebar_helper`), `#links-and-things > [role=heading]` (the section's title row; the id is the `id:` local of `me/dashboard/_dashboard_document`) — so renaming one loses a step with no error but the system test's. Next and Back scroll the coming element to mid-pane themselves (smoothly unless motion is reduced) and move once the scroll ends, one wait at a time: driver's own scroll is instant unless its `smoothScroll` is on, and with it on the popover lands where the element was mid-glide, since driver places it once and re-places it only on window scroll, never on a scroll of the drawer pane. driver's fade and cutout glide are off (`animate: false`), a click on the overlay closes nothing, the popover title is escaped before driver writes it as HTML (a callsign is text), and `dialog_controller#hotkey` ignores the page's shortcuts while `body.driver-active` is set.
Trap: driver's overlay takes the pointer from everything but the highlighted element, so `SystemTestHelpers#sign_in` marks every system-test person toured; a test of the tour itself sets `on_boarded_at` back to nil after signing in.

### Me › Profile
Reach it: `GET /me/profile` → My Clubhouse › Profile & Recognition › Profile (rangers/echelons; others: My Clubhouse › Profile › Profile; also Account › My Profile); edit `GET /me/profile/:section_id/edit`; save `PATCH /me/profile/:section_id`; yearly review `PATCH /me/profile/reviewed`
Gate: any signed-in person except `is_any_bonked?` (`check_person_status` redirects to `/me`); non-ranger/applicant/echelon (e.g. auditors) cannot edit `camp`, `emergency-contact`, `clothing`
Controller: `app/controllers/me/profile_controller.rb` (`index`, `edit`, `update`, `mark_reviewed`) + `app/controllers/concerns/profile_subject_concern.rb`, `app/controllers/concerns/profile_policy_concern.rb`
Owner: `ProfileSubjectConcern` (`app/controllers/concerns/profile_subject_concern.rb`), `ProfilePolicyConcern` (`app/controllers/concerns/profile_policy_concern.rb`), `Person` validations (`app/models/person.rb`)
Touches: `person` (w), `person_event` (w), `action_logs` (w), `email_history` (w), `swag`, `person_photo`, `person_language`, `alert`, `person_alert`
Verify: `test/controllers/me/profile_controller_test.rb`, `test/system/me/profile_test.rb`, `test/system/me/profile_integration_test.rb`, `test/system/me/profile_accessibility_test.rb`, `test/controllers/person/profiles_controller_test.rb`
Trap: `mark_reviewed` sets only `person_event.pii_started_at`/`pii_finished_at` (`Milestones#has_reviewed_pi`); `person.reviewed_pi_at` (`Scheduling::Permission`, auditors/applicants) and `pi_reviewed_for_dashboard_at` (`Person#has_reviewed_pi?`) are never set.
Trap: `set_is_me` must stay a `prepend_before_action` — `ProfileSubjectConcern` registers `require_edit_permission`/`require_section_visible` on include and they read `viewing_self?` (`@is_me`), so a plain `before_action` denies self-edits.

### Me › Alert Preferences
Reach it: `GET /me/alerts/edit` → from Me › Profile (Alerts section); save `PATCH /me/alerts` with `intent` = `save_number`, `confirm_code`, `send_code` or `save_preferences`
Gate: any signed-in person (no status check); `save_number`/`send_code` refused on the Groundhog Day server (`prevent_if_ghd_server`)
Controller: `app/controllers/me/alerts_controller.rb` (`edit`, `update`) + `app/controllers/concerns/alerts/editing_concern.rb`
Owner: `Alerts::EditingConcern` (`app/controllers/concerns/alerts/editing_concern.rb`), `Alerts::SmsPreferencesService` (`app/services/alerts/sms_preferences_service.rb`), `PersonAlert` (`app/models/person_alert.rb`)
Touches: `alert`, `person_alert` (w), `person` (w), `broadcast_message` (w), `action_logs` (w), `error_logs` (w)
Verify: `test/controllers/me/alerts_controller_test.rb`, `test/services/alerts/sms_preferences_service_test.rb`, `test/controllers/person/alerts_controller_test.rb`
Trap: `Alerts::EditingConcern#update` checks `admin_intent_allowed?` only if `admin_acting?`, so on `/me/alerts` `intent=save_sms_state` (`handle_save_sms_state`) sets `sms_number`/`sms_verified`/`sms_stopped` with no code check — refuse `SMS_STATE_INTENT` there.

### Me › Known Languages
Reach it: `GET /me/profile/languages` → from Me › Profile (Languages section); add `GET /me/profile/languages/new`, `POST /me/profile/languages`; edit `GET /me/profile/languages/:id/edit`, `PATCH /me/profile/languages/:id`; remove `DELETE /me/profile/languages/:id`
Gate: any signed-in person (no status check); rows scoped through `current_user.person_language`
Controller: `app/controllers/me/languages_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PersonLanguage` (`app/models/person_language.rb`)
Touches: `person_language` (w)
Verify: `test/controllers/me/languages_controller_test.rb`, `test/controllers/person/languages_controller_test.rb`
Trap: `language_name` is the sentinel `"custom"` for a free-text language (text in `language_custom`, else cleared by `before_save`) — display `PersonLanguage#actual_name`, never `language_name`.
Trap: `app/views/profile_languages/*` (shared with `Person::LanguagesController`) link only via helpers (`profile_index_path`, `language_url`, `language_edit_url`, `language_new_url`, `languages_index_url`, `can_edit_languages?`), never `me_profile_language_path`.

### Me › Upload BMID Photo
Reach it: `GET /me/profile/photos/new` → from Me › Profile (BMID section) and the dashboard's Upload a BMID Photo task; upload `POST /me/profile/photos` (JSON); crop `GET /me/profile/photos/:id/crop`; submit `PATCH /me/profile/photos/:id/crop_save`; withdraw `DELETE /me/profile/photos/:id`
Gate: any signed-in person (no status check; `setting: PhotoUploadEnable` never consulted — off, it only swaps the dashboard task's text); `crop`/`crop_save`/`destroy` only while the photo `is_pending?`
Controller: `app/controllers/me/photos_controller.rb` (`new`, `create`, `crop`, `crop_save`, `destroy`) + `app/controllers/concerns/photo_upload_concern.rb`
Owner: `PhotoUploadConcern` (`app/controllers/concerns/photo_upload_concern.rb`), `PersonPhoto` (`app/models/person_photo.rb`)
Touches: `person_photo` (w), `active_storage_blobs` (w), `active_storage_attachments` (w)
Verify: `test/controllers/me/photos_controller_test.rb`, `test/system/me/photo_upload_preview_test.rb`, `test/models/person_photo_crop_test.rb`, `test/controllers/person/photos_controller_test.rb`
Trap: `crop_save` clears superseded uploads via `PersonPhoto.delete_pending` (a `delete_all`), leaving their `original`/`profile`/`avatar` attachments and blobs behind — use `destroy` if they must go.
Trap: `blob.metadata` has no width/height on the crop page right after upload (dev sets `config.active_storage.analyzers = []`; production analyzes after commit) — take dimensions from pixels (vips, `naturalWidth`), as `PersonPhoto#profile_dimensions` tolerates.

### Me › Passkeys
Reach it: `GET /me/profile/passkeys` → Account › Passkeys; add `GET /me/profile/passkeys/new`, `POST /me/profile/passkeys/options` (JSON, checks current password), `POST /me/profile/passkeys`; remove `DELETE /me/profile/passkeys/:id`
Gate: route constraint `Passkeys.enabled?(request)` (404 with no passkey origin, or on a single sign-on client); then any signed-in person (menu: computed `passkeys_enabled`)
Controller: `app/controllers/me/passkeys_controller.rb` (`index`, `new`, `create`, `destroy`) + `app/controllers/concerns/passkey_registration_concern.rb` (`options`, rate-limited)
Owner: `Passkeys::Registration` (`app/lib/passkeys/registration.rb`), `PersonPasskey` (`app/models/person_passkey.rb`), `PasskeyMailer` (`app/mailers/passkey_mailer.rb`)
Touches: `person_passkey` (w), `action_logs` (w), `error_logs` (w), `person`, `mail_template`
Verify: `test/controllers/me/passkeys_controller_test.rb`, `test/lib/passkeys/registration_test.rb`, `test/system/passkeys_test.rb`, `test/mailers/passkey_mailer_test.rb`, `test/models/person_passkey_test.rb`
Trap: Send `PasskeyMailer` add/remove notices from the controller as `create`/`destroy` do, never a `PersonPasskey` callback — `Person has_many :passkeys, dependent: :destroy`, so deleting an account would mail once per passkey.
Trap: Without `RANGER_CLUBHOUSE_PASSKEY_ORIGIN`, `Passkeys.origin` uses the request address only in dev/test, never for an IP, so `127.0.0.1` (Capybara default) 404s all routes — `test/system/passkeys_test.rb` sets `Capybara.app_host` to `http://localhost:<port>`.

### Change Password
Reach it: `GET /me/profile/password` → Account › Change Password (also a Me › Profile button); save `POST /me/profile/password`
Gate: any signed-in person; the current password must authenticate
Controller: `app/controllers/me/password_controller.rb` (`edit`, `update`), `app/controllers/me/password_reset_controller.rb` (`edit`, `update` — empty stub)
Owner: `PasswordForm` (`app/forms/password_form.rb`), `Person#authenticate`/`Person#password=` (`app/models/person.rb`)
Touches: `person` (w), `action_logs` (w)
Verify: `test/controllers/me/password_controller_test.rb`
Trap: `Me::PasswordResetController` (`GET`/`POST /me/profile/password-reset`) has empty actions, no template, link or test — the real email reset flow is `SessionsController` with `PasswordResetForm`.
Trap: `update`'s `current_user.save!` runs every `Person` validation, so a record failing an unrelated one (blank `home_phone`, missing address) raises an unrescued `ActiveRecord::RecordInvalid`, not a form error.

### Me › Agreements
Reach it: `GET /me/agreements` → My Clubhouse › Pre-Event › Agreements; read `GET /me/agreements/:id` (`:id` = document tag); sign `PATCH /me/agreements/:id/sign`
Gate: any signed-in person; `find_agreement` refuses a tag that is unknown, not `available`, or has no `Document` (menu: Pre-Event hidden for `is_auditor?`)
Controller: `app/controllers/me/agreements_controller.rb` (`index`, `show`, `sign`)
Owner: `Agreements` (`app/lib/agreements.rb`), `Document` (`app/models/document.rb`), `PersonEvent` (`app/models/person_event.rb`)
Touches: `person_event` (w), `person` (w), `action_logs` (w), `document`, `setting`, `slot`
Verify: `test/controllers/me/agreements_controller_test.rb`, `test/lib/agreements_test.rb`, `test/lib/role_manager_test.rb`
Trap: `RoleManager` strips every role from an Event Management holder until the dept NDA is signed (then `sign_agreement` calls `PersonRole.clear_cache`) — the NDA is listed and signable only for a raw holder (`Agreements::DOCUMENTS[:role]`, checked in `is_document_visible?` and `can_sign_document?`), so test it with `has_raw_role?(Role::EVENT_MANAGEMENT)`, never `has_role?`.

### Me › Service Recognition (awards)
Reach it: `GET /me/awards` → My Clubhouse › Profile & Recognition › Service Recognition
Gate: any signed-in person (menu: status `is_ranger?`/`is_echelon?`)
Controller: `app/controllers/me/awards_controller.rb` (`index`)
Owner: `PersonAward.retrieve_for_person` (`app/models/person_award.rb`)
Touches: `person_award`, `award`, `team`, `position`
Verify: `test/controllers/me/awards_controller_test.rb`, `test/system/me/awards_test.rb`

### Me › Work History
Reach it: `GET /me/timesheet/work-history` → from My Clubhouse › Essentials › Timesheet (Work History button); drill-downs `GET /me/timesheet/work-history/position-summary`, `GET /me/timesheet/work-history/position-all`, `GET /me/timesheet/work-history/entire-year`
Gate: `authorize_status` active, inactive, inactive extension, retired, echelon (`TimesheetDashboardConcern`: `Person::ACTIVE_STATUSES` + `ECHELON`)
Controller: `app/controllers/me/work_history_controller.rb` (`index`, `position_summary`, `position_all`, `entire_year`) + `app/controllers/concerns/work_history_concern.rb`, `app/controllers/concerns/timesheet_dashboard_concern.rb`
Owner: `WorkHistoryReport` (`app/lib/reports/work_history_report.rb`)
Touches: `timesheet`, `position`, `position_credit`
Verify: `test/controllers/me/work_history_controller_test.rb`, `test/controllers/person/work_history_controller_test.rb`
Trap: Including `WorkHistoryConcern` adds `before_action :load_work_history`, so the `include` must stay below `before_action :set_person` — above it, the report runs with a nil `@person`.
Trap: The page covers every year (`WorkHistoryReport.execute` takes no year; `setup_year`'s viewed year only feeds the back link), and drill-downs read `year`/`position_id` via `params.expect!`, so a missing one is a 500 (`ExpectedParameterMissing`), not a 400.

## My Clubhouse: messages, announcements & info

Controllers sit in `namespace :me` and render the `me` layout; all but Cadre Directory act on `current_user`. None declares `authorize_role`: any signed-in person gets in unless the controller or an included concern adds `authorize_status`. Several menu entries are narrower than their controller; Gate lines show both.

### Me › Announcements (motd)
Reach it: `GET /me/announcements` → My Clubhouse › Communication › Announcements; read toggle `POST /me/announcements/:id/toggle-read`
Gate: any signed-in person
Controller: `app/controllers/me/announcements_controller.rb` (`index`, `toggle_read`)
Owner: `Motd` (`app/models/motd.rb`), `PersonMotd` (`app/models/person_motd.rb`)
Touches: `motd`, `person_motd` (w)
Verify: `test/controllers/me/announcements_controller_test.rb`, `test/system/me/announcement_links_test.rb`, `test/models/motd_test.rb`, `test/jobs/expire_announcements_job_test.rb`
Trap: `Motd.audience_for_status` returns nil for `Person::NO_MESSAGES_STATUSES` (incl. `AUDITOR`), so auditors see no announcement, not even `for_auditors` — the test "auditor sees auditor announcements" pins the empty page.
Trap: `Motd.retrieve_announcements_for_person` ignores `expires_at`: expired ones linger here and on the dashboard until `ExpireAnnouncementsJob` runs `Motd.expire!` (5am daily, prod only, `config/recurring.yml`) — test-pinned; `Motd.active` would change it.

### Me › Messages
Reach it: `GET /me/messages` → My Clubhouse › Essentials › Messages; thread `GET /me/messages/:id`; compose `GET /me/messages/new` → `POST /me/messages`, addressed `GET /me/messages/new?to=CALLSIGN` (Me › Mentoring's Send Message; `GET /me/messages?to=` redirects there); reply `POST /me/messages/:id/reply`; a live reply read on the open thread `POST /me/messages/:id/mark-read` (`thread_live_controller`, /me only); recipient picker `GET /me/messages/find_recipient` → `POST /me/messages/search_callsigns` → `POST /me/messages/select_callsign`; read `POST /me/messages/:id/read`; archive `POST /me/messages/:id/archive`
Gate: any signed-in person reads and replies; starting a message (`new`, `create`, `find_recipient`, `search_callsigns`, `select_callsign`) needs `Person#mailbox_user?`, Rangers and Echelon, else a redirect to /me (`Me::MessagesController#require_mailbox_user`); menu and navbar envelope: the same `mailbox_user?`
Controller: `app/controllers/me/messages_controller.rb` via `app/controllers/concerns/messages_concern.rb` (`index`, `show`, `new`, `create`, `create_reply`, `toggle_read`, `toggle_archive`, `mark_read`, `find_recipient`, `search_callsigns`, `select_callsign`)
Owner: `MessagesConcern` (`app/controllers/concerns/messages_concern.rb`), `PersonMessage` (`app/models/person_message.rb`), `Rbs.message_notify` (`app/lib/rbs.rb`), `GroupMessageAnnounceJob` (`app/jobs/group_message_announce_job.rb`); the navbar unread envelope is `app/views/application/_navbar_messages.html.erb`, rendered by `application/_top_menu.html.erb` and replaced live by `PersonMessage#announce_to_recipient` (`common/messages/_arrival.turbo_stream.erb`) over the stream `layouts/application` subscribes every signed-in page to (`ApplicationCable::Connection`)
Touches: `person_message` (w), `person`, `person_photo`, `timesheet`, `team`, `position`, `broadcast` (w), `broadcast_message` (w), `person_alert`, `email_suppression`, `setting`, `error_logs` (w), `solid_cable_messages` (w)
Verify: `test/controllers/me/messages_controller_test.rb`, `test/system/me/messages_recipient_autocomplete_test.rb`, `test/controllers/person/messages_controller_test.rb`, `test/controllers/hq/messages_controller_test.rb`, `test/integration/top_menu_test.rb`, `test/channels/application_cable/connection_test.rb`, `test/channels/solid_cable_config_test.rb`, `test/system/me/live_message_arrival_test.rb`
Trap: `?to=` is /me only (`Me::MessagesController#index`/`#new`; Person and HQ compose by `direction`) and only suggests a recipient: `create` checks it again on send. Every callsign the compose flow takes (`?to=`, `select_callsign`, `create`) goes through `validate_person_for_messaging` → `Person.resolve_callsign`: the exact callsign first, else the one normalized match, never one of two ("Fire-Fly"/"Fire Fly") and never an input that normalizes to "", and nil for a non-String. Its refusal words come from the `recipient_refusal` hook: on /me one sentence for every reason, so no request tells an unknown callsign from a person's status; `MessageDirectionConcern` gives Person and HQ the reason.
Trap: `MessagesConcern` and `app/views/common/messages/*` also serve `Person::MessagesController` and `Hq::MessagesController` (/me adds `message_owner` = `current_user`, the `"me"` prefix and the `?to=` overrides of `index`/`new`), so edits hit all three mailboxes.
Trap: `MessagesConcern#set_message` redirects ("Message not thread top") any row with a `reply_to_id`, so show/reply/read/archive need the thread-top id; `PersonMessage#toggle_archived!` flips the owner's member row, while the read toggle is `PersonMessage#toggle_thread_read!`. A note to self has one member row, so archived it is in Archived alone (the bug of 2026-10-06 that showed it in Inbox too went with the flag reads).
Trap: The navbar's unread envelope (`#navbar-messages`) is `PersonMessage.count_unread` for the viewer, on every signed-in page, for a `Person#mailbox_user?` (the Messages menu item asks the same method), so a change to the unread rule changes it too. For them it is always on the page, hidden at zero, because `MessagesConcern#render_message_flags` (Mark Read/Unread and archive) and `#read_state_streams` (a thread first read in the mailbox's pane) replace it by id; on Person and HQ the flags are someone else's and it re-renders the viewer's own count unchanged.
Trap: A new message updates its recipient's open pages live: `PersonMessage`'s `after_create_commit` (`#announce_to_recipient`) broadcasts the envelope's new count and one `#live-region` line to the recipient's stream, for every way a message is made (all three mailboxes, replies, and the RBS job's `save(validate: false)`), never for a note to self or someone who is not a `Person#mailbox_user?`. A write that skips callbacks, such as the archive merge's `insert_all`, announces nothing. It renders through `ApplicationController.render` and reads nothing of a person from `Current` (the sender in a request, nobody in the RBS job), only the clock. A reply also lands in its open thread on every participant's stream (slice 5, see Clubhouse messages mailbox). A broadcast that fails is rescued into one `message-announce-exception` error log naming the message, never re-raised: an error leaving an after-commit callback leaves `save`, which would show the sender a failure for a sent message and stop an RBS job partway through its recipients, whose retry would send the first ones twice.
Trap: Live delivery needs the WebSocket: Solid Cable in development and production (`config/cable.yml`, whose durations must be written as `1.second`, never a bare number, or Solid Cable's listener thread dies and nothing arrives; `test/channels/solid_cable_config_test.rb` holds it), and an nginx that passes `Upgrade` on `/cable` (the beta's is `location = /cable` in `beta/nginx/03-nginx.conf`, tested by `beta/nginx/check.sh`; live only once the maintainer deploys it). Without it the envelope is still right on every page load. Tests run the `test` adapter, which records broadcasts and delivers none; `test/system/me/live_message_arrival_test.rb` swaps in the async adapter to drive a real browser.

### Cadre Directory
Reach it: `GET /me/directory` → My Clubhouse › Communication › Cadre Directory
Gate: any signed-in person (menu: `is_ranger?` or `is_echelon?`)
Controller: `app/controllers/me/directory_controller.rb` (`index`)
Owner: `DirectoryReport` (`app/lib/reports/directory_report.rb`) (not `TeamManagement.directory_listed?`, used only by the admin grid's Directory chip)
Touches: `team`, `person_team`, `person`, `person_photo`, `person_position`, `position`, `setting`
Verify: `test/controllers/me/directory_controller_test.rb`, `test/lib/reports/directory_report_test.rb`, `test/system/me/directory_test.rb`
Trap: `DirectoryReport.execute` picks teams by its own SQL (type in `TeamManagement::DIRECTORY_TYPES` or `include_in_directory`, and `active`), twin of `TeamManagement.directory_listed?` behind the admin Directory chip — change both or they disagree.
Trap: `DirectoryReport.execute` takes callsign titles only from held active team positions whose `position.title` ends in "manager" or "supervisor", not `team_manager`, so other lead titles never show — edit that `LIKE` query; no flag column exists.

### Me › Mentoring
Reach it: `GET /me/mentoring` → My Clubhouse › Communication › Mentoring
Gate: any signed-in person (menu: `is_ranger?`)
Controller: `app/controllers/me/mentoring_controller.rb` (`index` from `app/controllers/concerns/mentoring_concern.rb`)
Owner: `PersonMentor` (`app/models/person_mentor.rb`), `MentoringConcern` (`app/controllers/concerns/mentoring_concern.rb`), `MentorHelper` (`app/helpers/mentor_helper.rb`), `ArtMentoring::PersonHistory` (`app/lib/art_mentoring/person_history.rb`) for the ART sections
Touches: `person_mentor`, `person`, `person_fka`, `person_photo`, `timesheet`, `position`
Verify: `test/controllers/me/mentoring_controller_test.rb`, `test/helpers/mentor_helper_test.rb`, `test/lib/art_mentoring/person_history_test.rb`
Trap: ART walks (`person_mentor` rows with a `timesheet_id`) are listed below the Alpha sections, read-only, in the Alpha layout: per ART and year a "<year> <ART> Mentors" card row and a "<year> <ART> Mentees (n mentees)" card row (people, not walks) with passed/bonked/pending tallies, a card per walk with its shift (`common/mentoring/_art_section`; every card on the page comes from `common/mentoring/_mentee_card`). A walk is filed under the ART its mentee entry sits on now and the entry's year, as the roster and Verdicts file it; with the entry deleted it stays under the position it was recorded for and its `mentor_year`; a position whose team has no ART mentoring training lists under its own title, a deleted position row as "Position #id". Notes are never shown (ruled 2026-10-22). Send Message appears on every ART card, mentor and mentee alike, under the Alpha cards' rule (ruled 2026-10-22 after the mentee side was first left without). The Alpha mentors section renders only with an Alpha year, and a person with nothing to show gets one empty state.
Trap: `PersonMentor.retrieve_passing_for_person` returns the latest Alpha mentor year in any status (its `current_status` is that year's `PersonMentor.year_verdict`), which `common/mentoring/index` lists; only `MentorHelper#me_mentoring_description` checks `STATUS_PASS` — check `current_status` first.
Trap: `MentoringConcern` and `app/views/common/mentoring/index.html.erb` also serve `Person::MentoringController` (`/person/:id/mentoring`); /me differs only by the locals `app/views/me/mentoring/index.html.erb` passes (e.g. `can_edit_status: false`).
Trap: Send Message shows only to a viewer who may start a message (`mailbox_user?`, the compose page's gate) and only while `can_message?` (`PersonMentor`: `is_ranger?` and `Person#messaging_permitted?`, the rule the compose page it opens, `new_me_message_path(to:)`, applies); anyone else gets "no contact allowed", never a link the compose page refuses.

### Operational Summary
Reach it: `GET /me/operational-summary` → My Clubhouse › Pre-Event › Operational Summary
Gate: every status except AUDITOR, BONKED and UBERBONKED (`authorize_status except:`) (menu: Pre-Event hidden only from `is_auditor?`)
Controller: `app/controllers/me/operational_summary_controller.rb` (`index`)
Owner: `PersonEventInfo` (`app/lib/person_event_info.rb`), `Membership` (`app/lib/membership.rb`), `MealInfo` (`app/lib/meal_info.rb`)
Touches: `person_position`, `position`, `person_team`, `team`, `team_manager`, `person_certification`, `certification`, `trainee_status`, `trainer_status`, `slot`, `person_slot`, `provision`, `bmid`, `access_document`, `person_online_course`, `vehicle`, `person_event`, `event_dates`, `timesheet`, `setting`, `document`
Verify: `test/controllers/me/team_documents_controller_test.rb` (the Teams & Positions document links)
Trap: `PersonEventInfo.find_for_person_year` assumes `Position::TRAINING` is among the person's training positions: with none it `Position.find`s that row (unfixtured; tests must create it), and with only an ART one `delete_at(nil)` raises TypeError.

### Me › Team Document
Reach it: `GET /me/teams/:id/document` ← "View Team Document" under a team in Operational Summary › Teams & Positions (`:id` = team id); no menu entry
Gate: membership only — the team is found through the person's own `person_team` rows, so a team they are not on is a 404; no role and no team-manager check (writing the document is the manager-side port planned in `.scratch/teams-positions-team-resources/PRD.md`, `/teams-positions/team-resources`)
Controller: `app/controllers/me/team_documents_controller.rb` (`show`)
Owner: `Document` (`app/models/document.rb`, `find_by(tag:)`), `Team#resource_tag`
Touches: `team`, `person_team`, `document`
Verify: `test/controllers/me/team_documents_controller_test.rb`
Trap: The body is read only here — Operational Summary lists which teams have one by tag (`Document.where(tag:).pluck(:tag)`, `@team_document_tags`) and never selects `document.body`, which runs to megabytes for the Mentor team; keep any list that way.
Trap: `show` prints `@document.body.html_safe`; the body is sanitized only on the way in (`ResourceDocumentCrudConcern#submitted_body`), so any new write path must go through it.

### Me › Event Summary
Reach it: `GET /me/timesheet/event-summary` ← "Hours & Credits" links on `GET /me/timesheet` (My Clubhouse › Essentials › Timesheet)
Gate: status ACTIVE, INACTIVE, INACTIVE_EXTENSION, RETIRED or ECHELON (`authorize_status` in `TimesheetDashboardConcern`)
Controller: `app/controllers/me/event_summary_controller.rb` (`index`) + `app/controllers/concerns/timesheet_dashboard_concern.rb`, `app/controllers/concerns/timesheet_concern.rb` (`ApplicationController#setup_year`, `year_floor` 1990: `?year=` else current year; then `setup_timesheets`)
Owner: `EventSummaryReport` (`app/lib/reports/event_summary_report.rb`), `EventSummary` (`app/lib/event_summary.rb`), `PositionWorkSummary` (`app/lib/reports/position_work_summary.rb`)
Touches: `timesheet`, `position`, `position_credit`, `event_dates`, `timesheet_missing`, `person_event`, `setting`
Verify: `test/controllers/me/event_summary_controller_test.rb`, `test/lib/reports/event_summary_report_test.rb`, `test/controllers/hq/timesheets_controller_test.rb`
Trap: `EventSummaryReport` also feeds `Person::SwagController#index`, `HqConcern`, `TicketsAndProvisionsProgress`, and with `app/views/common/_event_summary_breakdown.html.erb` backs `Hq::TimesheetsController#event_summary`/`Person::TimesheetsController#breakdown`.

### Me › Surveys (survey response)
Reach it: `GET /me/surveys` (`type`, `slot_id`, `year`) ← dashboard tasks "Take a Training Survey (optional)" (training and mentoring sessions, each linked with its own `type`), "Take A Mentor Survey (optional)", "Take a Trainer's Training Survey (optional)"; submit `POST /me/surveys`
Gate: any signed-in person; `SurveyBuilder` then requires a passed training session (training), attended teaching status (trainer), an Alpha timesheet that year (alpha), nothing (two mentoring types)
Controller: `app/controllers/me/surveys_controller.rb` (`show`, `create`; inline `process_survey_answers`, `validate_survey_responses`)
Owner: `SurveyBuilder` (`app/lib/survey_builder.rb`), `SurveyResponseForm` (`app/forms/survey_response_form.rb`), `SurveyAnswer` (`app/models/survey_answer.rb`); `SurveyUnansweredFinder` (`app/lib/survey_unanswered_finder.rb`) decides which surveys the dashboard offers
Touches: `survey`, `survey_group`, `survey_question`, `survey_answer` (w), `slot`, `position`, `trainer_status`, `trainee_status`, `person_mentor`, `timesheet`, `person_photo`
Verify: `test/controllers/me/surveys_controller_test.rb`, `test/helpers/me/survey_question_group_partial_test.rb`, `test/lib/survey_unanswered_finder_test.rb`, `test/controllers/me/dashboard_controller_test.rb` (mentoring link)
Trap: `SurveyBuilder.retrieve_alpha_survey` raises `ArgumentError` (unrescued by `load_survey_data`: a 500) with no Alpha timesheet that year; `retrieve_mentoring_survey` never checks the asker, so anyone can answer any `slot_id`'s mentoring survey.
Trap: `create` deletes old answers (`SurveyAnswer.delete_all_for_person_slot`/`delete_all_for_survey`) outside the transaction while `SurveyBuilder.retrieve_slot_survey_trainers` hides already-rated trainers, so a resubmit loses those ratings for good.

### Me › Online Course
Reach it: `GET /me/online-course` ← "Go To Online Course" in dashboard task "Read the Ranger Manual & Complete The Online Course", and `GET /me/online-course?art=1` ← "Go To Online Course" beside each ART with an online course in "Sign Up For & Attend Advanced Ranger Training (ART)"; set up and go `POST /me/online-course`
Gate: any signed-in person, for their own account; `create` is refused on the Groundhog Day server (`prevent_if_ghd_server`)
Controller: `app/controllers/me/online_course_controller.rb` (`index`, `create`)
Owner: `Moodle#set_up_person` (`app/lib/moodle.rb`), `PersonOnlineCourse` (`app/models/person_online_course.rb`); `DashboardTasks::OnlineCourse` (`app/lib/dashboard_tasks/online_course.rb`) decides when the dashboard links here (not `Admin::OnlineCoursesController`, which manages course records)
Touches: `online_course`, `person` (w), `person_online_course` (w), `action_logs` (w), `error_logs` (w), `setting`
Verify: `test/controllers/me/online_course_controller_test.rb`, `test/controllers/me/dashboard_controller_test.rb` (ART link)
Trap: `?art=1` swaps the In-Person Training reminder for where to find the ART course; the form and `create`'s error redirects carry it, and the POST sets up the same In-Person Training course either way (as upstream).
Trap: `create` links or creates the Moodle account, enrolls it in this year's Training course, then redirects to the `OnlineCourseSiteUrl` setting on another host — so the form posts with `data-turbo="false"`, and the development database's live LMS credentials make a dev click create a real account (tests stub `Moodle#request_web_service`).
Trap: two departures from upstream's `setupPerson`: an inactive course is never chosen (the course for `all`, else `returning` for an active Ranger with 2+ `years_as_ranger`, else `new`), and an existing account is synced only on a new enrollment, not on every click.

## My Clubhouse: schedule, tickets, timesheet & vehicles

Every page acts on `current_user` under the `me` layout (`me/timesheet` for timesheet pages). Most logic lives in concerns shared with the HQ and Person pages (`ScheduleConcern`, `AvailableSignUpsConcern`, `TimesheetConcern`, `ShiftManageConcern`); /me controllers mostly supply the subject and path builders. `setup_year` reads `?year=` (floor 1990) on schedule, sign-up and timesheet pages; ticketing and vehicle pages always use the present year.

### Me › Schedule / Sign-Ups
Reach it: `GET /me/schedule` → My Clubhouse › Essentials › Schedule / Sign-Ups; remove `DELETE /me/schedule/:slot_id`; who's signed up `GET /me/schedule/:slot_id/signups`; Hours & Credits `GET /me/schedule/signup-summary`; calendar `GET /me/schedule/export`
Gate: `status: not BONKED, UBERBONKED or PAST_PROSPECTIVE`; present year: `index` sends home an applicant whose `Scheduling::Permission#training_signups_allowed` is false (menu: everyone)
Controller: `app/controllers/me/schedule_controller.rb` (`index`), `app/controllers/concerns/schedule_concern.rb` (`index`, `signups`, `export`, `destroy`, `signup_summary`)
Owner: `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Scheduling::Signup` (`app/lib/scheduling/signup.rb`; not `Scheduling::Management`), `Scheduling::Summaries` (`app/lib/scheduling/summaries.rb`)
Touches: `person_slot` (w), `slot` (w), `person` (w), `action_logs` (w), `position`, `person_position`, `position_credit`, `person_online_course`, `event_dates`, `setting`
Verify: `test/controllers/me/schedule_controller_test.rb`, `test/system/me/schedule_signups_card_test.rb`, `test/lib/scheduling/query_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`, `test/controllers/person/scheduling_controller_test.rb`
Trap: My Schedule calls `Scheduling::Query.partition_by_time(..., cutoff: :end_time)`, Available Sign-Ups `cutoff: :start_time`, so a shift under way is upcoming on one and past on the other — deliberate; keep them different.
Trap: `ScheduleConcern#destroy` reports a refused removal as a `success:` flash ("The shift could not removed.") — check the `Scheduling::Signup.remove` verdict (`Scheduling::Verdict::Removed`), not the flash key.

### Me › Available Sign-Ups
Reach it: `GET /me/schedule/sign-ups` → linked from Me › Schedule / Sign-Ups; position `GET /me/schedule/sign-ups/position/:position_id`; sign up `POST /me/schedule/sign-ups/position/:position_id/slot/:slot_id`; remove `DELETE /me/schedule/sign-ups/position/:position_id/slot/:slot_id`
Gate: `status: not BONKED, UBERBONKED or PAST_PROSPECTIVE`; present year: every action redirects to the schedule while `Scheduling::Permission#requirements` is non-empty; `show` for the Training position without `training_signups_allowed` (the Online Course) renders a preview instead of the cards -- an Online Course Required warning, then one card per month, its session count in a badge, listing its sessions by `slot.description` only, A to Z, a repeated description once with its count (`common/available_sign_ups/_training_months`), with no dates, seats or sign-up controls; the index row stays a link with a note (ruled 2026-10-22)
Controller: `app/controllers/me/available_sign_ups_controller.rb` (path builders only), `app/controllers/concerns/available_sign_ups_concern.rb` (`index`, `show`, `create`, `destroy`)
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`; not `Scheduling::Management`), `Scheduling::Permission` (`app/lib/scheduling/permission.rb`), `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Position#scheduling_header_for` (`app/models/position.rb`)
Touches: `person_slot` (w), `slot` (w), `person` (w), `action_logs` (w), `position`, `person_position`, `position_credit`, `person_event`, `person_online_course`, `timesheet`, `setting`
Verify: `test/controllers/me/available_sign_ups_controller_test.rb`, `test/controllers/hq/available_sign_ups_controller_test.rb`, `test/system/me/available_signups_shared_partials_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`, `test/lib/scheduling/permission_test.rb`
Trap: `Scheduling::ActiveRecordSlotStore#insert_signup` checks capacity against the denormalized `slot.signed_up`, which a bare `PersonSlot.create!` never increments — create sign-ups (tests too) through `Scheduling::Signup.add`.
Trap: A trainer-bound slot's capacity is `Scheduling::Query::ScheduleEntry#max_effective` (trainer sign-ups × `slot.max`, from `Scheduling::SlotCapacity#effective_max`), which the card, Add button and `Signup.add` use — never gate on raw `slot.max`.
Trap: `show` prints the position's sign-up page header by `@person`'s status (`Position#scheduling_header_for`, rendered through `rich_text` in `common/available_sign_ups/show`): Rangers and Echelon get `ranger_scheduling_header`, applicants (Prospective or Alpha) `applicant_scheduling_header`, every other status nothing. Present year only: a past year's page shows no header (ruled 2026-10-22).

### Me › Qualifications
Reach it: `GET /me/schedule/qualifications` → linked from Me › Schedule / Sign-Ups; `GET /me/timesheet/qualifications` → linked from Me › Timesheet
Gate: via `/me/schedule`: `status: not BONKED, UBERBONKED or PAST_PROSPECTIVE`; via `/me/timesheet`: `status: Person::ACTIVE_STATUSES` + `ECHELON`
Controller: `app/controllers/concerns/qualifications_concern.rb` (`qualifications`), included by `app/controllers/me/schedule_controller.rb` and `app/controllers/me/timesheet_controller.rb` (each `set_back_to` sets back link and sign-ups URL)
Owner: `TicketsAndProvisionsProgress` (`app/lib/tickets_and_provisions_progress.rb`), `QualificationsPresenter` (`app/presenters/qualifications_presenter.rb`)
Touches: `timesheet`, `slot`, `person_slot`, `position`, `position_credit`, `event_dates`, `setting`
Verify: `test/controllers/me/qualifications_controller_test.rb`, `test/presenters/qualifications_presenter_test.rb`
Trap: `QualificationsConcern#qualifications` builds `TicketsAndProvisionsProgress.new(@person)`, which always measures the present year (`Current.year`) — `?year=` changes only the back link, never the numbers.

### Self Check In/Out (shift manage)
Reach it: `GET /me/shift-manage` → My Clubhouse › Essentials › Self Check In/Out; start `POST /me/shift-manage/start`; end `POST /me/shift-manage/end`; resume `POST /me/shift-manage/resignin`; position `GET /me/shift-manage/position` + `PATCH /me/shift-manage/position`; undo `DELETE /me/shift-manage/entry`
Gate: `ADMIN`, `SHIFT_MANAGEMENT_SELF` (RoleManager drops it unless `setting: SHIFT_MANAGEMENT_SELF_ENABLED`; menu: same roles AND that setting, so an Admin can open the page the menu hides)
Controller: `app/controllers/me/shift_manage_controller.rb` (`index`), `app/controllers/concerns/shift_manage_concern.rb` (`start_shift`, `end_shift`, `resignin`, `correct_position`, `update_position`, `delete_mistake`)
Owner: `ShiftManage` (`app/lib/shift_manage.rb`), `SignInBlocker` (`app/lib/sign_in_blocker.rb`), `TimesheetManagement` (`app/lib/timesheet_management.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_event` (w), `person` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_pod` (w), `pod` (w), `action_logs` (w), `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `setting`
Verify: `test/controllers/me/shift_manage_controller_test.rb`, `test/lib/shift_manage_test.rb`, `test/lib/sign_in_blocker_test.rb`, `test/controllers/person/timesheets_controller_test.rb`
Trap: `RoleManager` drops `Role::SHIFT_MANAGEMENT_SELF` (`SETTING_GATED_ROLES`) unless setting `ShiftManagementSelfEnabled` is on (default false) — a test granting the role must create that setting row or be redirected home.
Trap: `Timesheet`'s `after_update :log_updates`/`after_destroy :log_deletion` write timesheet_log, so `ShiftManage.update_position`/`resignin` log nothing and `sign_off`/`delete_mistake` add just a SIGNOFF/DELETE_MISTAKE row — never log a change twice.

### Me › Timesheet
Reach it: `GET /me/timesheet` → My Clubhouse › Essentials › Timesheet; verify `PATCH /me/timesheet/manage/:id/verified`; correction `GET /me/timesheet/manage/:id/edit` + `PATCH /me/timesheet/manage/:id`; final confirmation `GET /me/timesheet/manage/final-confirmation` + `POST /me/timesheet/manage/final-confirmation`
Gate: `status: Person::ACTIVE_STATUSES` + `ECHELON` (from `TimesheetDashboardConcern`); final confirmation also needs `setting: TIMESHEET_CORRECTION_ENABLE` on the present year and no unverified entries
Controller: `app/controllers/me/timesheet_controller.rb` (`index`, `final_confirmation`, `final_confirmation_acknowledgement`), `app/controllers/concerns/timesheet_corrections_concern.rb` (`mark_verified`, `edit`, `update`), `app/controllers/concerns/timesheet_concern.rb` (data loading, path contract)
Owner: `Timesheet` (`app/models/timesheet.rb`), `TimesheetManagement` (`app/lib/timesheet_management.rb`), `PersonEvent` (`app/models/person_event.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `timesheet_note` (w), `person_event` (w), `timesheet_missing`, `person_position`, `position`, `position_credit`, `setting`
Verify: `test/controllers/me/timesheet_dashboard_controller_test.rb`, `test/controllers/hq/timesheets_controller_test.rb`, `test/models/timesheet_test.rb`, `test/helpers/partials_render_test.rb`
Trap: `Me::TimesheetController`'s `before_action :are_corrections_enabled?, only: [:final_confirmation, :final_confirmation_acknowledgement]` overrides `TimesheetCorrectionsConcern`'s, so `mark_verified`/`edit`/`update` skip it — list all five there.
Trap: `GET /me/timesheet` and `GET /me/timesheet/manage` both render `#index`, and the `show`/`destroy` routes from `resources :timesheet` have no action (404) — /manage is not a separate page.

### Missing Timesheet Requests
Reach it: `GET /me/timesheet/missing-request` → linked from Me › Timesheet; new `GET /me/timesheet/missing-request/new` + `POST /me/timesheet/missing-request`; amend `GET /me/timesheet/missing-request/:id/edit` + `PATCH /me/timesheet/missing-request/:id`; withdraw `DELETE /me/timesheet/missing-request/:id`
Gate: `status: Person::ACTIVE_STATUSES` + `ECHELON`, `setting: TIMESHEET_CORRECTION_ENABLE` (else back to the timesheet); an approved request cannot be changed
Controller: `app/controllers/me/missing_requests_controller.rb` (includes only), `app/controllers/concerns/missing_requests_concern.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`), `app/controllers/concerns/timesheet_concern.rb` (loads `@missing_requests`)
Owner: `TimesheetMissing` (`app/models/timesheet_missing.rb`)
Touches: `timesheet_missing` (w), `timesheet_missing_note` (w), `timesheet`, `person_event`, `person_position`, `position`, `setting`
Verify: `test/controllers/me/missing_requests_controller_test.rb`, `test/controllers/hq/missing_requests_controller_test.rb`
Trap: `MissingRequestsConcern#index` partitions `@missing_requests`, which `TimesheetConcern#setup_timesheets` sets only for the present year, so `?year=<past year>` raises NoMethodError on nil — never pass a year to these pages.

### Tickets & Stuff (Tickets & Provisions)
Reach it: `GET /me/tickets` → My Clubhouse › Pre-Event › Tickets & Stuff; section pages `GET /me/tickets/ticket` through `GET /me/tickets/review`; claim/bank `PATCH /me/tickets/documents/:id/status`; delivery `PATCH /me/tickets/delivery`; SO SAP names `PATCH /me/tickets/sap-so`; bank/claim provisions `PATCH /me/tickets/provisions`; finish `POST /me/tickets/finish`
Gate: `status: not AUDITOR or PAST_PROSPECTIVE`; section pages and writes also need `setting: TICKETING_PERIOD` = `open`, a linked BPGUID and a non-applicant, else back to the hub (menu: Pre-Event hidden from auditors and past prospectives)
Controller: `app/controllers/me/tickets_controller.rb` (`index`, `ticket`, `gift`, `vehicle_pass`, `provisions`, `sap`, `sap_so`, `review`, `update_status`, `update_delivery`, `update_sap_so`, `update_provisions`, `finish`)
Owner: `AccessDocumentStatusChange` (`app/lib/access_document_status_change.rb`), `TicketAndProvisionsPackage` (`app/lib/ticket_and_provisions_package.rb`), `TicketOverviewPresenter` (`app/presenters/ticket_overview_presenter.rb`)
Touches: `access_document` (w), `access_document_changes` (w), `provision` (w), `person_event` (w), `action_logs` (w), `timesheet`, `position_credit`, `setting`
Verify: `test/controllers/me/tickets_controller_test.rb`, `test/lib/access_document_status_change_test.rb`, `test/controllers/person/tickets_provisions_controller_test.rb`
Trap: `AccessDocument::SAP`/`AccessDocument::SAPSO` store legacy `"work_access_pass"`/`"work_access_pass_so"` (`Setting::TAS_DEFAULT_SAP_DATE` is `"TAS_DefaultWAPDate"`) — raw queries, fixtures and migrations use those literals, never "sap".
Trap: `AccessDocumentStatusChange#call` saves its own copy of the document, so yours is stale — reload it before saving, or the `set_delivery_method_by_type` before_save resets `delivery_method` (see `claim_and_set_delivery`).

### Vehicle Dashboard
Reach it: `GET /me/vehicles` → My Clubhouse › Pre-Event › Vehicle Dashboard; MVR instructions `GET /me/vehicles/mvr-submit`
Gate: `status: Person::WORKING_STATUSES` and `VehicleDashboard#any_eligible?`, else sent home (menu: computed `show_vehicles`, eligible only)
Controller: `app/controllers/me/vehicles_dashboard_controller.rb` (`index`, `mvr_submit`)
Owner: `VehicleDashboard` (`app/models/vehicle_dashboard.rb`), `VehicleEligibility` (`app/lib/vehicle_eligibility.rb`), `Agreements` (`app/lib/agreements.rb`)
Touches: `person_event`, `person_team`, `person_slot`, `slot`, `person_position`, `position`, `vehicle`, `document`, `setting`
Verify: `test/lib/vehicle_eligibility_test.rb`, `test/helpers/partials_render_test.rb`
Trap: Menu `show_vehicles` (`VehicleEligibility.is_person_eligible?`, cached per person and year) ignores `mvr_potential?`/`pvr_potential?`, which `VehicleDashboard#any_eligible?` admits — a potential-only person gets the page, no menu item.
Trap: `VehicleDashboard#days_until_mvr_deadline` counts from `Time.current`, but `mvr_deadline_passed?` uses `Current.time` (via `VehicleEligibility.retrieve_mvr_deadline`), so its days-left text disagrees under the Groundhog Day clock.

### Personal Vehicle Request (PVR)
Reach it: `GET /me/vehicles/personal/new` → linked from Vehicle Dashboard; create `POST /me/vehicles/personal`; edit `GET /me/vehicles/personal/:id/edit` + `PATCH /me/vehicles/personal/:id`; delete `DELETE /me/vehicles/personal/:id`
Gate: any signed-in person; edit, update and delete only their own present-year request not yet approved
Controller: `app/controllers/me/personal_vehicles_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`)
Owner: `Vehicle` (`app/models/vehicle.rb`)
Touches: `vehicle` (w)
Verify: `test/models/vehicle_test.rb`
Trap: `Me::PersonalVehiclesController` skips `authorize_status` and builds no `VehicleDashboard`; only `me/vehicles_dashboard/_pvr_info.html.erb` checks eligibility/agreements, so a direct `POST /me/vehicles/personal` files a pending request for anyone.

## Person Manage: account & identity

Every controller includes `PersonConcern`: `set_person` loads `params[:person_id] || params[:id]`; `authorize_role VIEW_ROLES` admits Person › Overview's Gate roles. `authorize_role` is last-call-wins: a controller's own call *replaces* VIEW_ROLES, while `before_action` checks stack on top. No page has a year selector (present year); only `layout "person"` controllers (or `PersonController`) show the Person sidebar (`Menus::PERSON`).

### Person › Overview
Reach it: `GET /person/:id` → Person sidebar › Essentials › Overview, and callsign links passing `can_view_person_page?`; Switch to HQ Interface `GET /person/:person_id/redirect_to_hq`; Actions › Resend Welcome Message `POST /person/:person_id/resend_welcome`; Actions › Reset Onboarding Tour `POST /person/:person_id/reset_onboarding`; email banner › Clear Bounce Report / Clear Spam Report `POST /person/:person_id/email-suppression/clear` (also in the HQ shell)
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`, `MENTOR`, `TRAINER`, `VC`, `SHIFT_MANAGEMENT` (PersonConcern::VIEW_ROLES); redirect_to_hq also needs setting HQ_WINDOW_INTERFACE_ENABLED; resend_welcome also needs `ADMIN` or `VC` (`authorize_ability :resend_welcome`, as Clubhouse 2's `PersonPolicy#sendWelcomeEmail`; the Actions item asks `can?(:resend_welcome)`, the same gate; denied → `person_path`), then status prospective; reset_onboarding the same, with its own `authorize_ability` and `can?`, offered only once `person.on_boarded_at` is set; the email clear `ADMIN`, `TECH_NINJA` (its own `authorize_role`, replacing VIEW_ROLES)
Controller: `app/controllers/person_controller.rb` (`show`, `redirect_to_hq`, `resend_welcome`, `reset_onboarding`), `app/controllers/concerns/person_concern.rb`, `app/controllers/person/email_suppressions_controller.rb` (`clear`)
Owner: `PersonPermissionPresenter#overview_rows` (`app/presenters/person_permission_presenter.rb`), `RoleManager` (`app/lib/role_manager.rb`), `Membership.retrieve_for_person` (`app/lib/membership.rb`), `EmailSuppression` (`app/models/email_suppression.rb`)
Touches: `person` (w), `person_role`, `role`, `person_position`, `position`, `position_role`, `person_team`, `team`, `team_role`, `person_fka`, `person_photo`, `person_banner`, `email_suppression` (w), `action_logs` (w), `timesheet`, `setting`
Verify: `test/controllers/person_controller_test.rb`, `test/controllers/person/email_suppressions_controller_test.rb`, `test/presenters/person_permission_presenter_test.rb`, `test/helpers/person/permissions_helper_test.rb`, `test/lib/role_manager_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: `RoleManager.retrieve` is cached per person and year (`person-roles-<year>-<id>`) — writers bypassing `PersonRole.add_ids_to_person`/`remove_ids_from_person` must call `RoleManager.purge_person`; test with `CacheTestHelper#with_cache_store`.
Trap: the email banner reads `email_suppression` for the person's current address, not `person.is_bouncing`, and states only the fact and the date of the last report (see Person pages & HQ Window shell). Its clear deletes that one row and writes an `email-suppression-clear` action log naming the actor, the person, the address and what the row held, then redirects back (`redirect_back_or_to`, falling back to the person page); with no row it writes nothing and says so. A Tech Ninja with none of VIEW_ROLES may clear but opens neither page, so never sees the button. For a `complaint` row, or a `bounce` row with sub-type `OnAccountSuppressionList` (`EmailSuppression#on_ses_list?`), the confirmation says SES's own list holds the address too and only the SES console clears it there; until then SES refuses mail to it and the next broadcast email writes the row again — as a bounce (sub-type `OnAccountSuppressionList`), even where the cleared row was a complaint. Changing the address also clears the banner, since the new one has no row.
Trap: `PersonController#redirect_to_hq` answers `HQ_WINDOW_INTERFACE_ENABLED` off with a 422 `turbo_stream` that Turbo drops on the hero's plain `back_to` link (`app/views/person/_hero.html.erb`) — add `data: { turbo_stream: true }` or redirect with a flash.
Trap: `resend_welcome` saves only through `create_temporary_login_token(Person::PNV_INVITATION_EXPIRE)` (`save(validate: false)`), which keeps an unexpired token and moves its expiry to 14 days — never add a `save!`: it runs every-save validations and `before_validation` rewrites, so an older prospective record that fails them gets an error page (`RecordInvalid`, 422) after the token moved, and no email.
Trap: `reset_onboarding` clears `person.on_boarded_at` with `update_attribute` — no validations, as the resend above, and `audit_model` logs the `person-update` (actor, target, the change). The Onboarding Tour row in the Account group (`person/_summary_strip`, through `person/_timestamp_value` like Last Seen and Created) reads the column for every page viewer; the tour itself is under My Clubhouse › Onboarding tour (first sign-in).

### Mark On Site / Off Site (toggle_onsite)
Reach it: `POST /person/:person_id/toggle_onsite` → Person › Overview's Mark On Site/Off Site button (`app/views/person/_actions.html.erb`)
Gate: PersonConcern::VIEW_ROLES, then `SHIFT_MANAGEMENT` (or `ADMIN`) (`authorize_ability :toggle_onsite` — Clubhouse 2 keeps `on_site` in `PersonFilter`'s `EVENT_FIELDS`, Shift Management only); denied → `person_path` (button: `can?(:toggle_onsite)`, the same gate)
Controller: `app/controllers/person_controller.rb` (`toggle_onsite`)
Owner: `Person#log_on_site_change` (`app/models/person.rb`), `PersonOnSite.record` (`app/models/person_on_site.rb`)
Touches: `person` (w), `person_on_site` (w), `action_logs` (w)
Verify: `test/controllers/person_controller_test.rb`, `test/models/person_on_site_test.rb`
Trap: `EVENT_MANAGEMENT`/`EVENT_MANAGEMENT_ON_PLAYA` alone no longer pass (ruled 2026-10-10, matching Clubhouse 2, which silently dropped their `on_site` write); HQ › On-Site Registration (`ADMIN`, `SHIFT_MANAGEMENT`) is the window's own path.
Trap: `Person#log_on_site_change` (after_save) writes `person_on_site` rows — bulk `on_site` writes (`update_all`, `update_columns`, `insert_all`) must call `PersonOnSite.reconcile(at:, creator:)`; `test/models/person_on_site_test.rb` enforces it.

### Delete Account (person#destroy)
Reach it: `DELETE /person/:id` → Person › Overview › Actions › Delete Account
Gate: PersonConcern::VIEW_ROLES, then `TECH_NINJA` alone (`authorize_ability :delete_account`, `admin: false` — Clubhouse 2's `PersonPolicy#delete` has no `before` hook, so `ADMIN` without it is refused); denied → `person_path` (Actions link: `can?(:delete_account)`, the same gate)
Controller: `app/controllers/person_controller.rb` (`destroy`)
Owner: `Person` (`app/models/person.rb`, its `dependent:` associations), `ApplicationRecord#audit_destroy` (`app/models/application_record.rb`)
Touches: `person` (w), `person_role` (w), `person_position` (w), `person_team` (w), `person_slot` (w), `timesheet` (w), `person_photo` (w), `person_fka` (w), `person_banner` (w), `person_certification` (w), `person_language` (w), `person_swag` (w), `email_history` (w), `sessions` (w), `person_passkey` (w), `action_logs` (w), `person_favorite` (w), `person_page_visit` (w), `person_motd` (w), `person_message_member` (w), `timesheet_note` (w), `timesheet_log` (w), `active_storage_attachments` (w)
Verify: `test/controllers/person_controller_test.rb`, `test/models/application_record_audit_test.rb`, `test/controllers/me/messages_controller_test.rb` (member rows)
Trap: the two gates stack — a `TECH_NINJA` holder needs a VIEW_ROLES role too, or PersonConcern bounces them to /me before `:delete_account` is asked (narrower than Clubhouse 2, whose `PersonController@destroy` asks `PersonPolicy#delete` alone); never add an `authorize_role` here, it would replace VIEW_ROLES.
Trap: no foreign key references `person`, so rows outside Person's `dependent:` list (`person_status`, `person_on_site`, `person_event`, `action_logs`) are left as orphans. So are their `person_message` rows: a thread holding one the person wrote, or one sent to them, names them "Deleted #id" (`PersonMessage.deleted_name`; `#sender_name`, `#sender_avatar` and `#recipient_avatar` read the gone person, and every mailbox listing such a thread failed on it until 2026-10-19). Their `person_message_member` rows go with them (review finding 7), and one left by an earlier deletion is skipped (`PersonMessage#other_members`, `#participants`).

### Person › Dashboard
Reach it: `GET /person/:person_id/dashboard` → Person sidebar › Essentials › Dashboard
Gate: PersonConcern::VIEW_ROLES
Controller: `app/controllers/person/dashboard_controller.rb` (`show`)
Owner: `Milestones.build_for_person` (`app/lib/milestones.rb`), `Dashboard` (`app/lib/dashboard.rb`), `DashboardFacts.from_milestones` (`app/lib/dashboard_facts.rb`)
Touches: `person_event`, `person_online_course`, `person_position`, `slot`, `person_slot`, `person_photo`, `survey`, `document`, `timesheet`, `setting`
Verify: `test/controllers/person/dashboard_controller_test.rb`, `test/lib/milestones_test.rb`, `test/lib/dashboard_test.rb`, `test/lib/dashboard_facts_test.rb`
Trap: task bodies are Me › Dashboard's shared `app/views/dashboard_tasks/_*` partials (via `common/_dashboard_step`), so their links open the viewer's own /me pages and a missing partial 500s both pages.

### Person › Profile
Reach it: `GET /person/:person_id/profile` → Person sidebar › Account & Admin › Profile; edit `GET /person/:person_id/profile/:section_id/edit`; save `PATCH /person/:person_id/profile/:section_id`
Gate: `ADMIN`, `VC`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`, `VIEW_PII` (replaces VIEW_ROLES); edit/save also `can_edit_profile?` (`ADMIN`, `VC`) plus per-section visibility (menu: no visible_if, so `MENTOR`, `TRAINER`, `SHIFT_MANAGEMENT` see it and are bounced)
Controller: `app/controllers/person/profiles_controller.rb` (`show`; `edit`, `update` from `ProfileSubjectConcern`)
Owner: `ProfileSubjectConcern` (`app/controllers/concerns/profile_subject_concern.rb`), `ProfilePolicyConcern` (`app/controllers/concerns/profile_policy_concern.rb`), `Person` (`app/models/person.rb`)
Touches: `person` (w), `email_history` (w), `action_logs` (w), `person_event`, `person_alert`, `person_language`, `person_photo`, `swag`
Verify: `test/controllers/person/profiles_controller_test.rb`, `test/controllers/me/profile_controller_test.rb`
Trap: the pages render Me › Profile's shared `app/views/profile/*` templates — link via the `profile_*_path` hooks or branch on `viewing_self?` (`@is_me`, forced false by `prepend_before_action :set_is_me`), never a bare `me_`/`person_` helper.
Trap: `VIEW_PII` is admitted here but not in VIEW_ROLES, so a View-PII-only viewer opens the profile but its "Overview" back link and the other Person sidebar pages bounce them to /me.

### Edit Callsign (callsigns + FKA)
Reach it: `GET /person/:person_id/callsign/edit` → Person › Overview › Actions › Edit Callsign; save `PATCH /person/:person_id/callsign`; release `POST /person/:person_id/callsign/release`; FKA rows `GET /person/:person_id/fka/new`, `POST /person/:person_id/fka`, `GET /person/:person_id/fka/:id/edit`, `PATCH /person/:person_id/fka/:id`, `DELETE /person/:person_id/fka/:id`
Gate: `ADMIN`, `VC`, `MENTOR` (`can_manage_callsign_or_status?` before_action on top of VIEW_ROLES); the `vintage` field `ADMIN` only, `used_vanity_change` `ADMIN`, `VC`; release `ADMIN`, `VC` only (`authorize_ability :release_callsign`, as Clubhouse 2's `PersonPolicy#releaseCallsign`), denied → the edit page (Release box: `can?(:release_callsign)`, the same gate)
Controller: `app/controllers/person/callsigns_controller.rb` (`edit`, `update`, `release`), `app/controllers/person/fka_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`)
Owner: `Person` (`app/models/person.rb`: `reset_callsign`, `update_callsign_fka`, `fka_irrelevant_override`), `PersonFka` (`app/models/person_fka.rb`)
Touches: `person` (w), `person_fka` (w), `action_logs` (w)
Verify: `test/controllers/person/callsigns_controller_test.rb`, `test/models/person_test.rb`, `test/models/person_fka_test.rb`
Trap: the form's "Callsign approved" checkbox is silently dropped — `CallsignsController#update` does not permit it; only Release and `Person#handle_past_prospective_status` change `callsign_approved` here.
Trap: `Person#update_callsign_fka` (before_save) already records the old callsign as a `person_fka` row on every callsign change (`fka_irrelevant_override` sets searchability) — new code must not create FKA rows itself.

### Edit Status
Reach it: `GET /person/:person_id/status/edit` → Person › Overview › Actions › Edit Status; save `PATCH /person/:person_id/status`
Gate: `ADMIN`, `VC`, `MENTOR` (`can_manage_callsign_or_status?` before_action on top of VIEW_ROLES)
Controller: `app/controllers/person/statuses_controller.rb` (`edit`, `update`)
Owner: `PersonStatusManagement.change` (`app/lib/person_status_management.rb`), `Person#log_status_change` (`app/models/person.rb`), `StatusChangeWarnings` (`app/lib/status_change_warnings.rb`)
Touches: `person` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_team` (w), `person_slot` (w), `person_event` (w), `handle_reservation` (w), `action_logs` (w), `slot` (w), `person_position_log` (w), `person_team_log` (w), `person_fka` (w)
Verify: `test/system/person/statuses_edit_test.rb`, `test/lib/person_status_management_test.rb`, `test/lib/status_change_warnings_test.rb`, `test/helpers/person/statuses_helper_test.rb`
Trap: status side effects (`person_status` row, positions/roles/teams, future sign-ups, `asset_authorized`) run in the `Person#log_status_change` after_save → `PersonStatusManagement.change`; `update_column(:status, …)` or `update_all` skips them all.
Trap: `StatusChangeWarnings` modals are client-side only (`status-warning` Stimulus controller via `Person::StatusesHelper#status_warning_modals_for`) — the PATCH applies any `Person::ALL_STATUSES` status unconfirmed.

### Status History
Reach it: `GET /person/:person_id/status-history` → Person › Overview › Actions › Status History (not in the sidebar)
Gate: `ADMIN`, `VC` (replaces VIEW_ROLES)
Controller: `app/controllers/person/status_history_controller.rb` (`index`)
Owner: `PersonStatus.retrieve_all_for_id` (`app/models/person_status.rb`)
Touches: `person_status`, `person`
Verify: `test/controllers/person/status_history_controller_test.rb`

### Edit Permissions
Reach it: `GET /person/:person_id/permissions` → Person › Overview › Permissions section edit link; save `PATCH /person/:person_id/permissions`
Gate: `ADMIN` only (`authorize_ability :edit_permissions` on top of VIEW_ROLES, as Clubhouse 2's `PersonPolicy#updateRoles`), denied → `person_path`; the Overview edit link asks `PersonConcern#can_edit_permissions?`, which reads the same gate; only a `TECH_NINJA` may grant or revoke `TECH_NINJA` (`PersonPermissionForm#save` silently keeps it for other editors)
Controller: `app/controllers/person/permissions_controller.rb` (`edit`, `update`)
Owner: `PersonPermissionForm` (`app/forms/person_permission_form.rb`), `PersonPermissionPresenter#role_items` (`app/presenters/person_permission_presenter.rb`), `PersonRole` (`app/models/person_role.rb`)
Touches: `person_role` (w), `action_logs` (w), `role`, `person_team`, `team`, `team_role`, `person_position`, `position`, `position_role`
Verify: `test/controllers/person/permissions_controller_test.rb`, `test/presenters/person_permission_presenter_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: Tech Ninja is always granted with Admin, so it needs no place in the gate — but `PersonPermissionForm` guards only the Tech Ninja box, so anyone past the gate can grant `ADMIN` (to themselves too); never widen the gate past `ADMIN`.
Trap: the form posts `role_ids` with a hidden blank so "uncheck everything" arrives; `permission_params` answers 400 for a missing scope or non-id value rather than read an empty list (which would revoke every direct grant).

### Person › Change Password
Reach it: `GET /person/:person_id/password` → Person › Overview › Actions › Change Password; save `PATCH /person/:person_id/password`
Gate: `ADMIN` (`require_admin` before_action on top of VIEW_ROLES)
Controller: `app/controllers/person/passwords_controller.rb` (`edit`, `update`)
Owner: `PersonPasswordForm` (`app/forms/person_password_form.rb`), `Person#password=` and `Person#log_password_change` (`app/models/person.rb`)
Touches: `person` (w), `action_logs` (w)
Verify: `test/controllers/person/passwords_controller_test.rb`, `test/models/person_test.rb`
Trap: there is no `edit_person_password_path` — the form is `GET person_password_path` (`get "password", to: "passwords#edit"` in `config/routes.rb`).
Trap: setting the password clears `tpassword` but keeps the person's `sessions` rows and passkeys — those belong to Login Sessions and Person › Passkeys.

### Person › Passkeys
Reach it: `GET /person/:person_id/passkeys` → Person sidebar › Account & Admin › Passkeys, Administration › Admin Menu › Passkeys; add `GET /person/:person_id/passkeys/new`; options `POST /person/:person_id/passkeys/options`; save `POST /person/:person_id/passkeys`; remove `DELETE /person/:person_id/passkeys/:id`
Gate: `ADMIN` (replaces VIEW_ROLES); `new`/`options`/`create` also need `Passkeys.enabled?` (passkey origin set, not an SSO client)
Controller: `app/controllers/person/passkeys_controller.rb` (`index`, `new`, `create`, `destroy`), `app/controllers/concerns/passkey_registration_concern.rb` (`options`, rate-limited 10/minute)
Owner: `Passkeys::Registration` (`app/lib/passkeys/registration.rb`), `PersonPasskey` (`app/models/person_passkey.rb`), `PasskeyMailer` (`app/mailers/passkey_mailer.rb`)
Touches: `person_passkey` (w), `action_logs` (w), `person`
Verify: `test/controllers/person/passkeys_controller_test.rb`, `test/system/passkeys_test.rb`, `test/lib/passkeys/registration_test.rb`, `test/models/person_passkey_test.rb`, `test/lib/passkeys_test.rb`
Trap: `options` checks the Admin's own password (`Passkeys::Registration#start` calls `actor.authenticate`), pins the ceremony to the person's id in the session, and `hardware_only: true` refuses synced/platform passkeys — never reuse Me's registration here.
Trap: `index`/`destroy` answer even when `Passkeys.enabled?` is false so an Admin can clear a key; only `new`/`options`/`create` sit behind `require_passkeys_enabled`, and the menu item ignores `passkeys_enabled`, unlike Me's.

### Login Sessions
Reach it: `GET /person/:person_id/login-sessions` → Person sidebar › Account & Admin › Login Sessions; revoke `DELETE /person/:person_id/login-sessions/:id`
Gate: `ADMIN` (replaces VIEW_ROLES)
Controller: `app/controllers/person/sessions_controller.rb` (`index`, `destroy`)
Owner: inline in controller — `Session` via `@person.sessions`, devices via `UserAgentParser`
Touches: `sessions` (w)
Verify: `test/controllers/person/sessions_controller_test.rb`, `test/models/session_test.rb`
Trap: revoking deletes the `sessions` row and writes no `action_logs` entry (`Session` is not an `audit_model`), unlike a passkey removal.
Trap: revoking closes every cable connection of the person, not only the revoked browser's (`Session`'s `after_destroy_commit`); their other devices reconnect at once.

### External IDs
Reach it: `GET /person/:person_id/external-ids` → Person sidebar › Account & Admin › External IDs, Shift Operations › Payroll › Missing Paycom Employee IDs; save `PATCH /person/:person_id/external-ids`
Gate: `ADMIN` (replaces VIEW_ROLES)
Controller: `app/controllers/person/external_ids_controller.rb` (`show`, `update`)
Owner: inline in controller — `Person` columns `bpguid`, `lms_id`, `lms_username`, `employee_id`
Touches: `person` (w), `action_logs` (w)
Verify: none — no test exercises this feature
Trap: `ShiftOperations::PayrollMissingIdHelper#payroll_missing_id_callsign` reads `Person::ExternalIdsController.authorized_roles` to decide who gets a link here — change the gate in this controller only.
Trap: VC can also set `bpguid`, from a Salesforce contact a search returned (a signed row link), on VC › BPGUID Lookup; only this page clears or hand-types it.

### Person › Site Log
Reach it: `GET /person/:person_id/site-log` → Person sidebar › Account & Admin › Site Log
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA` (replaces VIEW_ROLES)
Controller: `app/controllers/person/site_log_controller.rb` (`index`)
Owner: `PersonOnSite` (`app/models/person_on_site.rb`), `PersonOnSiteFilterForm` (`app/forms/person_on_site_filter_form.rb`), `Person::SiteLogHelper` (`app/helpers/person/site_log_helper.rb`)
Touches: `person_on_site`, `person`
Verify: `test/controllers/person/site_log_controller_test.rb`, `test/models/person_on_site_test.rb`, `test/lib/person_menu_test.rb`
Trap: the page reads only `person_on_site` (marks from `Person#log_on_site_change`), never `action_logs`; its filter key is `filter[marked]` because Rails overwrites a param named `action`.
Trap: `PersonOnSiteFilterForm#apply_all_but_creator` bounds days with `Date#to_time` (local clock, as the DB stores times), not `Time.zone`; only `PersonOnSite.history_for` orders, so `creator_counts` must run on unordered `PersonOnSite.where(person:)`.
Trap: the rows are one section per year, and the Duration column is filled on the off-site mark that ends a stay; `PersonOnSite.on_site_durations` pairs marks over the whole history, not the filtered rows, so a `filter[marked]=off-site` page keeps its spans.

### Person › Upload BMID Photo (photos)
Reach it: `GET /person/:person_id/photos/new` → Person › Overview › Actions › Manage Photo, Person › Profile BMID card; upload `POST /person/:person_id/photos`; crop `GET /person/:person_id/photos/:id/crop`; submit `PATCH /person/:person_id/photos/:id/crop_save`; cancel `DELETE /person/:person_id/photos/:id`
Gate: `ADMIN`, `VC` (replaces VIEW_ROLES)
Controller: `app/controllers/person/photos_controller.rb` (path hooks, `after_crop_save`), `app/controllers/concerns/photo_upload_concern.rb` (`new`, `create`, `crop`, `crop_save`, `destroy`)
Owner: `PhotoUploadConcern` (`app/controllers/concerns/photo_upload_concern.rb`), `PersonPhoto` (`app/models/person_photo.rb`)
Touches: `person_photo` (w), `active_storage_blobs` (w), `active_storage_attachments` (w), `action_logs` (w)
Verify: `test/controllers/person/photos_controller_test.rb`, `test/controllers/me/photos_controller_test.rb`, `test/models/person_photo_crop_test.rb`
Trap: `crop_save` leaves the photo `SUBMITTED` for Volunteer Coordinator › VC Menu › Photo Review; `Person#photo`/`avatar_photo_attachment` read only `approved` rows, so the Overview photo changes only after approval.
Trap: `crop_save` calls `PersonPhoto.delete_pending`, which `delete_all`s the person's other uploaded/submitted photos — no callback or `has_one_attached` dependent runs, orphaning their `active_storage_attachments` rows and blobs.

## Person Manage: communication, membership & training

Every controller includes `PersonConcern` (`app/controllers/concerns/person_concern.rb`): loads `@person` from `:person_id` (unknown id → /me) and sets `authorize_role PersonConcern::VIEW_ROLES` (`ADMIN`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`, `MENTOR`, `TRAINER`, `VC`, `SHIFT_MANAGEMENT`). A controller's own `authorize_role` REPLACES that list (last wins); `authorize_ability`, `require_current_year_for` and before_actions stack. Menus: `Menus::PERSON` (`app/lib/menus.rb`); year-scoped pages use `setup_year`.

### Person › Messages
Reach it: `GET /person/:person_id/messages` → Person › Account & Admin › Messages; thread `GET /person/:person_id/messages/:id`; compose `GET /person/:person_id/messages/new?direction=to|from` + `POST /person/:person_id/messages`; reply `POST /person/:person_id/messages/:id/reply`; flags `POST /person/:person_id/messages/:id/read`, `POST /person/:person_id/messages/:id/archive`
Gate: `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA` (replaces PersonConcern's list)
Controller: `app/controllers/person/messages_controller.rb` (`index`, `show`, `new`, `create`, `create_reply`, `toggle_read`, `toggle_archive`, `find_recipient`, `search_callsigns`, `select_callsign` — all from `MessagesConcern`)
Owner: `MessagesConcern` (`app/controllers/concerns/messages_concern.rb`), `MessageDirectionConcern` (`app/controllers/concerns/message_direction_concern.rb`), `PersonMessage` (`app/models/person_message.rb`) (not `Hq::MessagesController`, the HQ-window twin)
Touches: `person_message` (w), `person`, `person_alert`, `email_suppression`, `broadcast` (w), `broadcast_message` (w)
Verify: `test/controllers/person/messages_controller_test.rb`, `test/controllers/hq/messages_controller_test.rb`, `test/controllers/me/messages_controller_test.rb`
Trap: Plain `ADMIN` is denied (the gate replaces PersonConcern's list), and `EVENT_MANAGEMENT_ON_PLAYA` counts only while the `EVENT_MANAGEMENT_ON_PLAYA_ENABLED` setting is on (`RoleManager::SETTING_GATED_ROLES`).
Trap: `MessageDirectionConcern` must be included after `MessagesConcern` (reverse-order hook overrides) and keeps `mark_read_on_view?` false, so viewing never marks a thread read; views are `app/views/common/messages/`, shared with Me and HQ.

### Person › Mail Log
Reach it: `GET /person/:person_id/mail-log` → Person › Account & Admin › Mail Log; body `GET /person/:person_id/mail-log/:id/body` (lazy turbo frame)
Gate: `ADMIN`, `VC` (replaces PersonConcern's list)
Controller: `app/controllers/person/mail_log_controller.rb` (`index`, `body`)
Owner: `MailLog` (`app/models/mail_log.rb`), `EmailHistory` (`app/models/email_history.rb`), `MailLogHelper` (`app/helpers/mail_log_helper.rb`)
Touches: `mail_log`, `email_history`, `person`, `broadcast`
Verify: `test/controllers/person/mail_log_controller_test.rb`, `test/models/mail_log_test.rb`, `test/helpers/mail_log_helper_test.rb`, `test/controllers/admin/mail_log_controller_test.rb`
Trap: `MailLogHelper#mail_body_srcdoc` must return a plain String, never `html_safe` — `srcdoc="…"` in `app/views/common/mail_log/body.html.erb` is the second escape that keeps third-party mail HTML in the sandboxed iframe.
Trap: `app/views/common/mail_log/` (table, legend, body) is shared with `Admin::MailLogController` at `/admin/mail-log`, so a change there changes both pages.
Trap: a row whose text was never kept (`MailLog#body_withheld?`: no `broadcast_id` and a NULL body — the five withheld mailers', see MailLog) opens to a `ui_empty_state` notice, "The text of this email isn't kept, so it can't be shown.", inside the same turbo frame and with no iframe. The words name no mailer, since a Clubhouse 2-era row may also have a NULL body for a reason nobody recorded. The VC application's Mail Log section (`vc/applications/_mail_log_section.html.erb`) draws bodies itself and has no notice; no withheld mailer sets an application, so it never lists such a row.

### Person › Alert Preferences
Reach it: `GET /person/:person_id/profile/alerts/edit` → Person › Profile, Alert Preferences edit link; save `PATCH /person/:person_id/profile/alerts` (`intent=save_preferences|save_sms_state`)
Gate: `ADMIN` (replaces PersonConcern's list); `intent=save_sms_state` also needs `TECH_NINJA`
Controller: `app/controllers/person/alerts_controller.rb` (`edit`, `update` — both from `Alerts::EditingConcern`)
Owner: `Alerts::EditingConcern` (`app/controllers/concerns/alerts/editing_concern.rb`), `PersonAlert` (`app/models/person_alert.rb`)
Touches: `alert`, `person_alert` (w), `person` (w), `action_logs` (w)
Verify: `test/controllers/person/alerts_controller_test.rb`, `test/controllers/me/alerts_controller_test.rb`
Trap: `admin_acting?` is always true here and `admin_intent_allowed?` passes only `save_preferences`/`save_sms_state`, so `save_number`, `confirm_code`, `send_code` get `head :forbidden` — the SMS number flow is `Me::AlertsController` only.
Trap: It renders the shared `app/views/alerts/edit.html.erb` (also `/me`), switching on the `admin_acting` local — there is no `app/views/person/alerts/`.
Trap: `person_alert` was `alert_person` until 2026-10-18; beta and amazon rename it in two deploys, a view first and the table after (Asset check-out / check-in has the Trap).

### Person › Manage Account Banners
Reach it: `GET /person/:person_id/banners` → Person › Overview actions menu "Manage Account Banners"; `POST /person/:person_id/banners`; `PATCH /person/:person_id/banners/:id`; `DELETE /person/:person_id/banners/:id`
Gate: PersonConcern list, then `require_banner_manager`: `ADMIN`, `VC`
Controller: `app/controllers/person/banners_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PersonBanner` (`app/models/person_banner.rb`) (not `Communication::PersonBannersController`, the cross-person Account Banners list)
Touches: `person_banner` (w), `person`
Verify: `test/controllers/person/banners_controller_test.rb`, `test/controllers/person_controller_test.rb`
Trap: `PersonBanner.find_for_query(active: true)` keeps `is_permanent = TRUE OR YEAR(created_at) = Current.year`, so a non-permanent banner shows on Overview and the HQ window only in its creation year; this page lists all.

### Person › Known Languages
Reach it: `GET /person/:person_id/profile/languages` → Person › Profile, Languages edit link; add `GET /person/:person_id/profile/languages/new` + `POST /person/:person_id/profile/languages`; `PATCH /person/:person_id/profile/languages/:id`; `DELETE /person/:person_id/profile/languages/:id`
Gate: `ADMIN`, `VC`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA` (replaces PersonConcern's list); new/create/edit/update/destroy need `ADMIN`, `VC` (`require_edit_permission`) (Profile link: `ADMIN`, `VC` only)
Controller: `app/controllers/person/languages_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PersonLanguage` (`app/models/person_language.rb`)
Touches: `person_language` (w)
Verify: `test/controllers/person/languages_controller_test.rb`, `test/controllers/me/languages_controller_test.rb`
Trap: Shared `app/views/profile_languages/` (also `Me::LanguagesController`) builds URLs only via controller `helper_method`s (`language_url`, `language_edit_url`, `languages_index_url`…) — never call a `person_*` route helper there.
Trap: `resources :languages` also generates `GET /person/:person_id/profile/languages/:id`, but there is no `show` action — link to index or edit, never that URL.

### Person › Manage Teams & Positions (membership)
Reach it: `GET /person/:person_id/membership/edit` → Person › Overview "Teams & Positions" edit link (only when `is_team_manager?`); save `PATCH /person/:person_id/membership`
Gate: PersonConcern list, then `only_team_managers`: `ADMIN` or a `team_manager` row (`is_team_manager?`)
Controller: `app/controllers/person/memberships_controller.rb` (`edit`, `update`)
Owner: `Membership` (`app/lib/membership.rb`), `PersonMembershipForm` (`app/forms/person_membership_form.rb`), `PersonMembershipPresenter` (`app/presenters/person_membership_presenter.rb`)
Touches: `person_team` (w), `person_team_log` (w), `team_manager` (w), `person_position` (w), `person_position_log` (w), `action_logs` (w), `team`, `position`, `team_role`, `position_role`, `role`
Verify: `test/controllers/person/memberships_controller_test.rb`
Trap: A missing list stays nil and is left alone, but a sent empty list revokes everything the editor manages — the form's hidden blanks and the `IdList.clean?` / 400 check in `membership_params` stop malformed wipes.
Trap: Despite `Membership.update_positions_for_person`'s VC/Mentor comment, only `ADMIN` manages team-less positions: `can_manage_positions` keeps only managed `team_id`s and `PersonMembershipPresenter#can_manage_general_positions?` is admin-only.

### Person › Applications
Reach it: `GET /person/:person_id/applications` → Person › Intake › Applications
Gate: `ADMIN`, `VC` (replaces PersonConcern's list)
Controller: `app/controllers/person/applications_controller.rb` (`index`)
Owner: `ProspectiveApplication` (`app/models/prospective_application.rb`)
Touches: `prospective_application`, `person`
Verify: `test/controllers/person/applications_controller_test.rb`
Trap: Read-only by design — status changes and emails belong to `Vc::ApplicationsController`, notes to `Vc::ApplicationNotesController` (both under `/vc/applications`); add no write actions here.

### Person › Unified Flagging
Reach it: `GET /person/:person_id/unified-flagging` → Person › Intake › Unified Flagging; known folks `PATCH /person/:person_id/unified-flagging/known-folks`
Gate: `ADMIN`, `INTAKE`, `REGIONAL_MANAGEMENT` (replaces PersonConcern's list); `REGIONAL_MANAGEMENT` without `ADMIN`/`INTAKE` gets the RRN-only view; known-folks update `ADMIN`, `VC`, `INTAKE`
Controller: `app/controllers/person/unified_flagging_controller.rb` (`show`, `update_known_folks`)
Owner: `Intake` (`app/lib/intake.rb`, `history_for_person`, present year), `Training` (`app/lib/training.rb`, `retrieve_training_history_for_ids`) (not `Vc::UnifiedFlaggingController` / `Training::UnifiedFlaggingController`, the `UnifiedFlaggingConcern` roster pipeline pages)
Touches: `person_intake`, `person_intake_note`, `person_mentor`, `slot`, `person_slot`, `trainee_status`, `trainee_note`, `trainer_status`, `timesheet`, `person_status`, `person` (w), `action_logs` (w)
Verify: `test/controllers/person/unified_flagging_controller_test.rb`, `test/lib/intake_test.rb`
Trap: `ensure_can_update_known_folks` and `@can_edit_known_folks` allow `VC`, but class-level `authorize_role [ADMIN, INTAKE, REGIONAL_MANAGEMENT]` bounces VC-only users first — widen it if VC alone should edit Known Rangers/PNVs.
Trap: `app/views/person/unified_flagging/_training_notes.html.erb` is read-only for all and reads `TraineeNote` via `Training.retrieve_training_history_for_ids`, not `PersonIntakeNote` — `PersonIntakeNote::TYPES` has no training team.

### Person › Add Note / Rank (intake notes)
Reach it: `GET /person/:person_id/unified-flagging/notes/new?type=` → Person › Unified Flagging "Add Note / Rank" and the pipeline detail frame (`app/views/common/unified_flagging/detail.html.erb`); `POST /person/:person_id/unified-flagging/notes`; `PATCH /person/:person_id/unified-flagging/notes/:id`; `DELETE /person/:person_id/unified-flagging/notes/:id`
Gate: `ADMIN`, `INTAKE`, `REGIONAL_MANAGEMENT`, `VC`, `MENTOR` (replaces PersonConcern's list), then `check_intake_permissions!` per team: vc → `VC`, mentor → `MENTOR`, personnel → `ADMIN`, rrn → `REGIONAL_MANAGEMENT` (`ADMIN` always passes)
Controller: `app/controllers/person/intake_notes_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`)
Owner: `IntakeNoteForm` (`app/forms/intake_note_form.rb`), `PersonIntakeNote` (`app/models/person_intake_note.rb`), `PersonIntake` (`app/models/person_intake.rb`)
Touches: `person_intake_note` (w), `person_intake` (w), `action_logs` (w), `person_mentor`, `slot`, `person_slot`, `trainee_status`, `trainee_note`, `trainer_status`, `timesheet`, `person_status`
Verify: `test/controllers/person/intake_notes_controller_test.rb`, `test/lib/intake_test.rb`, `test/controllers/mentoring/potential_alphas_controller_test.rb`, `test/controllers/mentoring/convert_prospectives_controller_test.rb`, `test/controllers/mentoring/post_season_summary_controller_test.rb`
Trap: `INTAKE` passes the class gate, but `PERMISSION_ROLE_FOR_TYPE` maps every `PersonIntakeNote::TYPES` value to VC/MENTOR/ADMIN/REGIONAL_MANAGEMENT (INTAKE only for unknown types), so INTAKE-only users can write no note.
Trap: Without a known `origin`, `intake_notes_return_path` goes to `person_unified_flagging_path`, which bounces VC/MENTOR-only writers to /me — pipeline links must carry `origin`/`origin_year` (`ORIGIN_RETURNS`, `intake_notes_origin_params`). The `vc`, `mentoring` and `mentoring_post_season` origins (`selects: true`) return with `?person=`, which the review pane selects; `mentoring_convert` (a table) keeps a `#person-N` anchor, which Turbo drops after a form submission.

### Person › Mentoring
Reach it: `GET /person/:person_id/mentoring` → Person › Training & History › Mentoring; status change `PATCH /person/:person_id/mentoring`
Gate: PersonConcern list, then `index`: `ADMIN`, `MENTOR`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA` (`ensure_can_view`); `update`: `ADMIN`, `MENTOR` (`ensure_can_update`) (menu: no visible_if — `TRAINER`, `VC`, `SHIFT_MANAGEMENT` see the link and are bounced)
Controller: `app/controllers/person/mentoring_controller.rb` (`update`; `index` from `MentoringConcern`)
Owner: `PersonMentor` (`app/models/person_mentor.rb`), `PersonMentorStatusForm` (`app/forms/person_mentor_status_form.rb`), `MentoringConcern` (`app/controllers/concerns/mentoring_concern.rb`), `ArtMentoring::PersonHistory` (`app/lib/art_mentoring/person_history.rb`) for the ART sections
Touches: `person_mentor` (w), `person`, `person_photo`, `person_fka`, `timesheet`, `position`
Verify: `test/controllers/person/mentoring_controller_test.rb` (the ART sections and the Verdicts link), `test/helpers/mentor_helper_test.rb` (`person_mentoring_description` only), `test/controllers/me/mentoring_controller_test.rb` (shared `MentoringConcern#index` and template), `test/forms/person_mentor_status_form_test.rb` (the form's Alpha-only scope), `test/lib/art_mentoring/person_history_test.rb`
Trap: `PersonMentorStatusForm#save` uses `update_all` on the (person, mentor_year) Alpha `person_mentor` rows, so despite `PersonMentor`'s `audit_model = true` no `action_logs` row is written and `actor:` is discarded.
Trap: `person_mentor` is shared by mentee position (`position_id`, database default `Position::ALPHA`); the Alpha readers and the status form's scope filter on `Position::ALPHA`, so the form never restates an ART walk. ART walks are listed read-only below the Alpha sections (as on Me › Mentoring, without Send Message), and each ART section carries a View Verdicts button to that ART's Verdicts page for that year only when the viewer passes `Training.view_roles(training)` (`MentorHelper#art_history_verdicts_link`); they are recorded on the ART's roster, never here.
Trap: `index` and `app/views/common/mentoring/index.html.erb` are shared with `Me::MentoringController` — put person-only behaviour in template locals (`status_form_path_builder`, `can_edit_status`), not concern branches.

### Person › Training / ARTs
Reach it: `GET /person/:person_id/training` → Person › Training & History › Training / ARTs; course change `PATCH /person/:person_id/training/online-course`; force-complete `POST /person/:person_id/training/online-course/mark-completed`; Moodle sync `POST /person/:person_id/training/online-course/sync`; Moodle password `POST /person/:person_id/training/online-course/reset-password`
Gate: PersonConcern list; online-course actions also need `TECH_NINJA` or `TRAINER` (`authorize_ability :manage_online_course, admin: false` — plain `ADMIN` is view-only); mark-completed, sync and reset-password also need the present year (`require_current_year_for`)
Controller: `app/controllers/person/training_controller.rb` (`index`, `update_online_course`, `mark_online_course_completed`, `sync_online_course_info`, `reset_online_course_password`)
Owner: `PersonEventInfo` (`app/lib/person_event_info.rb`), `PersonOnlineCourse` (`app/models/person_online_course.rb`), `Moodle` (`app/lib/moodle.rb`) (not `Hq::TrainingController`, the read-only HQ twin)
Touches: `person_online_course` (w), `person` (w: Moodle sync stores `lms_username`), `online_course`, `person_event`, `trainee_status`, `trainer_status`, `slot`, `person_position`, `position`, `action_logs` (w)
Verify: `test/controllers/person/training_controller_test.rb`, `test/helpers/partials_render_test.rb` (`person/training/_moodle_account`), `test/lib/moodle_test.rb`
Trap: `update_online_course` only repoints `person_online_course.online_course_id` (no Moodle enrollment) and skips `require_current_year_for`, so it writes whatever year arrives in `?year=`.
Trap: `update_online_course` and `mark_online_course_completed` set `poc.audit_reason`, but `PersonOnlineCourse` lacks `audit_model = true`, so neither writes `action_logs` — only reset-password logs (`lms-password-reset`).

### Person › Certifications
Reach it: `GET /person/:person_id/certifications` → Person › Training & History › Certifications; details `GET /person/:person_id/certifications/:id`; add `GET /person/:person_id/certifications/new` + `POST /person/:person_id/certifications`; `PATCH /person/:person_id/certifications/:id`; `DELETE /person/:person_id/certifications/:id`
Gate: PersonConcern list; new/create/edit/update/destroy also need `ADMIN` or `CERTIFICATION_MGMT` (`authorize_ability :manage_certifications`)
Controller: `app/controllers/person/certifications_controller.rb` (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PersonCertification` (`app/models/person_certification.rb`), `Certification` (`app/models/certification.rb`)
Touches: `person_certification` (w), `certification`, `person`
Verify: `test/controllers/person/certifications_controller_test.rb`
Trap: `create` never checks for an existing row (no uniqueness validation, non-unique (person_id, certification_id) index), so re-adding duplicates it and `Certification#total_people` double-counts — `BulkUpload::CertificationHandler` updates instead.

### Person › Agreements
Reach it: `GET /person/:person_id/agreements` → Person › Account & Admin › Agreements; save `PATCH /person/:person_id/agreements`
Gate: `ADMIN`, `EVENT_MANAGEMENT` to view (`authorize_ability :view_agreements`); update `ADMIN` only (`:manage_agreements`), present year only (`require_current_year_for`)
Controller: `app/controllers/person/agreements_controller.rb` (`index`, `update`)
Owner: `Agreements` (`app/lib/agreements.rb`, `retrieve`, `admin_set_signature`) (not `Agreements::BulkSignatureController`, the bulk-signature page)
Touches: `person_event` (w), `person` (w), `document`, `setting`, `action_logs` (w)
Verify: `test/controllers/person/agreements_controller_test.rb`, `test/lib/agreements_test.rb`, `test/controllers/person_controller_test.rb`
Trap: Unchecking Dept NDA (`signed_nda`) for an `EVENT_MANAGEMENT` holder without `TECH_NINJA` wipes all their roles next request (`RoleManager#retrieve_roles`; `admin_set_signature` clears the role cache).
Trap: A test creating the `dept-nda` Document must give its EM users a signed `person_event` row, or they bounce to /me.
Trap: `Agreements::DOCUMENTS` maps each flag's home — annual on `person_event` (per year), lifetime (`behavioral_agreement`) on `person`, Radio Checkout = column `person_event.asset_authorized` — read it before adding or querying a flag.

## Person Manage: event records

Every controller includes `PersonConcern`, which loads `@person` from `:person_id` and gates on `VIEW_ROLES` (`ADMIN`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`, `MENTOR`, `TRAINER`, `VC`, `SHIFT_MANAGEMENT`) unless `authorize_role` replaces it (last call wins). `authorize_ability`/`before_action` checks stack on top, so roles named only there need a page-gate role. `setup_year` reads `?year=`; `require_current_year_for` refuses past-year writes, admins included.

### Person › Tickets & Provisions
Reach it: `GET /person/:person_id/tickets-provisions` → Person › Event & Credentials › Tickets & Provisions; view-as-member `GET /person/:person_id/tickets-provisions/dashboard`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS` (replaces VIEW_ROLES)
Controller: `app/controllers/person/tickets_provisions_controller.rb` (`show`, `dashboard`), `app/controllers/concerns/provision_management_concern.rb` (`load_provisions`)
Owner: `AccessDocument` (`app/models/access_document.rb`), `ProvisionManagementConcern` (`app/controllers/concerns/provision_management_concern.rb`), `TicketAndProvisionsPackage` (`app/lib/ticket_and_provisions_package.rb`)
Touches: `access_document`, `provision`, `person_event`, `setting`
Verify: `test/controllers/person/tickets_provisions_controller_test.rb`
Trap: `dashboard` (`me/tickets/_landing`, `admin_view: true`) must not stamp `person_event.ticketing_last_visited_at` — only `Me::TicketsController` sets it, and this page shows it as the member's own last visit.
Trap: `me/tickets/_landing` defaults `person:` to `current_user` and reads `@ticket_package` — `dashboard` must pass `person: @person` and build `TicketAndProvisionsPackage.new(@person.id)`, or it shows the admin's own tickets.

### Person › New / Edit Access Document
Reach it: `GET /person/:person_id/tickets-provisions/access-documents/new` → linked from Person › Tickets & Provisions; create `POST /person/:person_id/tickets-provisions/access-documents`; edit `GET /person/:person_id/tickets-provisions/access-documents/:id/edit` → `PATCH /person/:person_id/tickets-provisions/access-documents/:id`; history `GET /person/:person_id/tickets-provisions/access-documents/:id/history`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/person/access_documents_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`, `history`)
Owner: `AccessDocument` (`app/models/access_document.rb`) (not `AccessDocumentStatusChange`), `AccessDocumentChange` (`app/models/access_document_change.rb`), `TicketingInfo` (`app/lib/ticketing_info.rb`)
Touches: `access_document` (w), `access_document_changes` (w), `action_logs` (w), `setting`
Verify: `test/controllers/person/access_documents_controller_test.rb`
Trap: Admin edits are plain `AccessDocument` saves (callbacks set delivery defaults, clear unused fields, prepend comments, write `access_document_changes`) — never use `AccessDocumentStatusChange`, whose bank/release cascade is /me's.
Trap: `AccessDocument::SAP` is stored as `"work_access_pass"` (`SAPSO`: `"work_access_pass_so"`) — raw SQL, fixtures and migrations must use those literals, not "sap".

### Person › New / Edit Provision
Reach it: `GET /person/:person_id/tickets-provisions/provisions/new` → linked from Person › Tickets & Provisions and Person › BMID (with `?type=` and `?origin=`); create `POST /person/:person_id/tickets-provisions/provisions`; edit `GET /person/:person_id/tickets-provisions/provisions/:id/edit` → `PATCH /person/:person_id/tickets-provisions/provisions/:id`; delete `DELETE /person/:person_id/tickets-provisions/provisions/:id`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`, `EDIT_BMIDS`
Controller: `app/controllers/person/provisions_controller.rb` (hooks only: `provision_person`, `find_provision`, `provision_form_path`, `provision_return_path`, `provision_return_label`), actions in `app/controllers/concerns/provision_crud_concern.rb` (`new`, `create`, `edit`, `update`, `destroy`)
Owner: `ProvisionCrudConcern` (`app/controllers/concerns/provision_crud_concern.rb`), `Provision` (`app/models/provision.rb`), `ProvisionManagementConcern` (`app/controllers/concerns/provision_management_concern.rb`)
Touches: `provision` (w), `action_logs` (w)
Verify: `test/controllers/person/provisions_controller_test.rb`, `test/controllers/person/bmids_controller_test.rb`, `test/controllers/ticketing/provisions_controller_test.rb`, `test/controllers/bmid/provisions_controller_test.rb`
Trap: `ProvisionCrudConcern` and the `app/views/common/provisions/` form also serve `Ticketing::ProvisionsController` and `Bmid::ProvisionsController` — put person-only behaviour in this controller's hooks.
Trap: Save, Cancel and Delete return to the `origin` param's page (checked against `ProvisionManagementConcern::PROVISION_ORIGINS`) — a link or form that drops `origin:` sends a BMID admin back to Tickets & Provisions.

### Person › BMID
Reach it: `GET /person/:person_id/bmid` → Person › Event & Credentials › BMID; save `POST /person/:person_id/bmid` (first save) or `PATCH /person/:person_id/bmid`
Gate: `ADMIN`, `EDIT_BMIDS` (replaces VIEW_ROLES, so VC cannot view)
Controller: `app/controllers/person/bmids_controller.rb` (`show`, `create`, `update`), `app/controllers/concerns/provision_management_concern.rb`
Owner: `Bmid` (`app/models/bmid.rb`), `BmidRelationshipLoader` (`app/lib/bmid_relationship_loader.rb`), `ProvisionManagementConcern` (`app/controllers/concerns/provision_management_concern.rb`)
Touches: `bmid` (w), `access_document` (w), `access_document_changes` (w), `action_logs` (w), `provision`, `person_event`, `person`, `person_slot`, `slot`, `setting`
Verify: `test/controllers/person/bmids_controller_test.rb`, `test/models/bmid_test.rb`
Trap: Each save re-snapshots usable provisions onto `bmid.meals`/`showers` (`save_bmid` → `Bmid#load_provision_package`) but `Bmid::BadgesController` never does — only the "Specials" roster reads those columns; the printer reads live provisions.
Trap: A changed admission date rewrites `access_date`/`access_any_time` on all the person's qualified, claimed or banked SAPs and Staff Credentials (`Bmid#update_sap` → `AccessDocument.update_saps_for_person`) when the pair differs from what `set_sap` loaded.

### Person › Swag
Reach it: `GET /person/:person_id/swag` → Person › Event & Credentials › Swag (also the search bar's Swag mode); record `GET /person/:person_id/swag/new?swag_type=…` → `POST /person/:person_id/swag`; edit `GET /person/:person_id/swag/:id/edit` → `PATCH /person/:person_id/swag/:id`
Gate: page `PersonConcern::VIEW_ROLES`; `new`, `create`, `edit`, `update` and `destroy` also need `ADMIN` or `QUARTERMASTER` (`require_swag_manager`)
Controller: `app/controllers/person/swag_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: inline in controller: `PersonSwag` (`app/models/person_swag.rb`), `Swag` (`app/models/swag.rb`), `EventSummaryReport` (`app/lib/reports/event_summary_report.rb`) for present-year hours
Touches: `person_swag` (w), `swag`, `person`, `timesheet`, `position`, `position_credit`, `event_dates`
Verify: none — no test exercises this feature
Trap: The controller never calls `authorize_role`, so a Quartermaster without a `PersonConcern::VIEW_ROLES` role is bounced to /me, though `swag_manager?` and `SearchBarPolicy::SWAG_MODE_ROLES` both name `QUARTERMASTER`.

### Person › Assets
Reach it: `GET /person/:person_id/assets` → Person › Essentials › Assets; checkout `POST /person/:person_id/assets`; check in `PATCH /person/:person_id/assets/:id/check_in`; attachment `GET /person/:person_id/assets/:id/change_attachment` → `PATCH /person/:person_id/assets/:id/update_attachment`; authorization `PATCH /person/:person_id/assets/authorization`; history modal `GET /person/:person_id/assets/:id/history`
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA` on every action (`authorize_ability :manage_assets`, atop VIEW_ROLES); `destroy` and `update_authorization` `ADMIN` only; `create` and `update_authorization` present year only (menu: no visible_if, so all VIEW_ROLES see it)
Controller: `app/controllers/person/assets_controller.rb` (`index`, `create`, `check_in`, `change_attachment`, `update_attachment`, `update_authorization`, `history`, `destroy`), checkout logic in `app/controllers/concerns/asset_management_concern.rb`
Owner: `AssetManagementConcern` (`app/controllers/concerns/asset_management_concern.rb`), `PersonAsset` (`app/models/person_asset.rb`), `PersonEvent` (`app/models/person_event.rb`)
Touches: `person_asset` (w), `person_event` (w), `action_logs` (w), `asset`, `asset_attachment`, `person`
Verify: `test/controllers/person/assets_controller_test.rb`, `test/models/person_asset_test.rb`, `test/controllers/hq/assets_controller_test.rb`, `test/models/asset_test.rb`
Trap: `authorize_ability :manage_assets` has no `only:`, so the unconditional "Assets" menu item bounces Mentors, Trainers, VCs and Shift Management from `index` to `person_path` ("You are not authorized to manage assets."), test-pinned.
Trap: `AssetManagementConcern`'s barcode guards also serve `Hq::AssetsController`, `Hq::ShiftManageController` and `Hq::SiteRegistrationController` — person-only checkout behaviour goes in this controller's `assets_*` hooks (`assets_person` and five paths).

### Person › Vehicles
Reach it: `GET /person/:person_id/vehicles` → Person › Event & Credentials › Vehicles (also the search bar's `!` search, for an owned vehicle); writes `PATCH /person/:person_id/vehicles/update_mvr_flags`, `PATCH /person/:person_id/vehicles/update_pvr_flags`, `PATCH /person/:person_id/vehicles/update_agreements`, `PATCH /person/:person_id/vehicles/update_blacklist`
Gate: page `PersonConcern::VIEW_ROLES`; every write is `ADMIN` only (`authorize_ability :manage_vehicles`, as Clubhouse 2's event-info page and `PersonFilter::RANGER_ADMIN_FIELDS` — `VEHICLE_MANAGEMENT` only reads here); flag and agreement updates also need the present year, `update_blacklist` has no year gate
Controller: `app/controllers/person/vehicles_controller.rb` (`index`, `update_mvr_flags`, `update_pvr_flags`, `update_agreements`, `update_blacklist`)
Owner: `VehicleEligibility` (`app/lib/vehicle_eligibility.rb`), `PersonEvent` (`app/models/person_event.rb`)
Touches: `person_event` (w), `person` (w), `action_logs` (w), `position`, `person_position`, `team`, `person_team`, `person_slot`, `slot`
Verify: `test/controllers/person/vehicles_controller_test.rb`, `test/lib/vehicle_eligibility_test.rb`
Trap: `person_team`/`person_position` carry no year, so past years show today's MVR/PVR teams and positions beside that year's sign-ups and `person_event` flags, and `VehicleEligibility.is_mvr_eligible?(…, @year)` is true for any year if on an MVR team today.
Trap: The `!` search (`Autocomplete::VehicleAdapter`) lands here with no `year` (`!ABC:2024` still shows the present year), and this page never reads `vehicle` — registrations live at `/vehicles/registry`.

### Person › Pogs
Reach it: `GET /person/:person_id/pogs` → Person › Event & Credentials › Pogs; new `GET /person/:person_id/pogs/new` → `POST /person/:person_id/pogs`; edit `GET /person/:person_id/pogs/:id/edit` → `PATCH /person/:person_id/pogs/:id`
Gate: page `PersonConcern::VIEW_ROLES`; every action except `index` needs `EVENT_MANAGEMENT` (or `ADMIN`) (`authorize_ability :manage_pogs`, as Clubhouse 2's `PersonPogPolicy`; `EVENT_MANAGEMENT_ON_PLAYA` passes while RoleManager confers it) (menu: `ADMIN`, `EVENT_MANAGEMENT`)
Controller: `app/controllers/person/pogs_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PersonPog` (`app/models/person_pog.rb`)
Touches: `person_pog` (w), `action_logs` (w), `timesheet`, `person`
Verify: `test/controllers/person/pogs_controller_test.rb`, `test/models/person_pog_test.rb`
Trap: `SHIFT_MANAGEMENT` opens this page (VIEW_ROLES) but only reads it — HQ's end-of-shift pogs go through `Hq::ShiftManageController`, not this gate.
Trap: No `require_current_year_for`, so "Add Pog" on a past viewed year stamps the pog now and redirects to that year's list (`PersonPog.find_for_query` filters on `created_at`), where it seems to vanish.

### Person › Awards (Service Recognition Awards)
Reach it: `GET /person/:person_id/awards` → Person › Training & History › Awards; grant `GET /person/:person_id/awards/new?type=team|position|special` → `POST /person/:person_id/awards`; edit `GET /person/:person_id/awards/:id/edit` → `PATCH /person/:person_id/awards/:id`; rebuild `POST /person/:person_id/awards/rebuild`
Gate: page `PersonConcern::VIEW_ROLES`; `new`, `create`, `edit`, `update`, `destroy` and `rebuild` need `AWARD_MANAGEMENT` (or `ADMIN`) (`authorize_ability :manage_awards`)
Controller: `app/controllers/person/awards_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `rebuild`)
Owner: `PersonAward` (`app/models/person_award.rb`), `AwardManagement` (`app/lib/award_management.rb`), `YearsManagement` (`app/lib/years_management.rb`)
Touches: `person_award` (w), `person` (w), `action_logs` (w), `award`, `team`, `position`
Verify: `test/controllers/person/awards_controller_test.rb`
Trap: `AwardManagement.rebuild_for_person_id` is a deliberate, test-pinned no-op (commented out to match production Laravel), so "Rebuild awards" changes nothing — do not uncomment it without a product decision.
Trap: Saving or deleting a `PersonAward` re-saves `person` (`years_of_awards`, `years_of_service`, audited to `action_logs`) via `after_save`/`after_destroy` → `YearsManagement.update_years_of_awards`.

### Person › Timesheets
Reach it: `GET /person/:person_id/timesheets` → Person › Essentials › Timesheets (also the search bar's Timesheet mode); review `GET /person/:person_id/timesheets/:id/edit` → `PATCH /person/:person_id/timesheets/:id`; confirm `POST /person/:person_id/timesheets/confirm`; audit log `GET /person/:person_id/timesheets/log`; hours `GET /person/:person_id/timesheets/breakdown`; back fill `GET /person/:person_id/timesheets/backfill` → `POST /person/:person_id/timesheets/backfill`; end shift `POST /person/:person_id/timesheets/:id/signoff`
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `TIMESHEET_MANAGEMENT` (`PersonTimesheetConcern`, replaces VIEW_ROLES); `update` and `destroy` need `TIMESHEET_MANAGEMENT`; `signoff` needs `SHIFT_MANAGEMENT` or `TIMESHEET_MANAGEMENT`; `confirm` needs `TIMESHEET_MANAGEMENT` or `TECH_NINJA` (each also passes `ADMIN`); back fill is `ADMIN` only
Controller: `app/controllers/person/timesheets_controller.rb` (`index`, `edit`, `update`, `destroy`, `signoff`, `confirm`, `backfill`, `create_backfill`, `log`, `breakdown`), `app/controllers/concerns/person_timesheet_concern.rb`, filters in `app/helpers/person/timesheets_helper.rb`
Owner: `Timesheet` (`app/models/timesheet.rb`), `TimesheetManagement` (`app/lib/timesheet_management.rb`), `EventSummaryReport` (`app/lib/reports/event_summary_report.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `timesheet_note` (w), `person_event` (w), `person` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_pod` (w), `pod` (w), `action_logs` (w), `timesheet_missing`, `position`, `position_credit`, `event_dates`
Verify: `test/controllers/person/timesheets_controller_test.rb`, `test/helpers/person/timesheets_helper_test.rb`, `test/models/timesheet_test.rb`, `test/controllers/concerns/person_concern_test.rb`, `test/lib/reports/event_summary_report_test.rb`
Trap: `Timesheet#log_updates` (`after_update`) is the only audit path for corrections — writing `TimesheetLog::UPDATE`/`VERIFY` rows in `Person::TimesheetsController#update` logs every edit twice.
Trap: `confirm` always flips the present year's `person_event.timesheet_confirmed` (`current_year`), whatever `?year=` says — only the view hides the button on other years.

### Person › Shift Check In/Out (shift manage)
Reach it: `GET /person/:person_id/shift-manage` → linked from Person › Timesheets ("Shift Check In/Out"); start `POST /person/:person_id/timesheets/shift/start`; end `POST /person/:person_id/timesheets/shift/end`; resume `POST /person/:person_id/timesheets/shift/resignin`; position `GET /person/:person_id/timesheets/shift/position` → `PATCH /person/:person_id/timesheets/shift/position`; delete mistake `DELETE /person/:person_id/timesheets/shift/entry`
Gate: page gate `ADMIN`, `EVENT_MANAGEMENT`, `TIMESHEET_MANAGEMENT` (`PersonTimesheetConcern`) plus `SHIFT_MANAGEMENT` (or `ADMIN`) via `authorize_ability :manage_shifts`; forcing a blocked check-in needs `ADMIN` or `CAN_FORCE_SHIFT` (`ShiftManage::FORCE_ROLES`)
Controller: `app/controllers/person/timesheets_controller.rb` (`shift_manage`, `start_shift`, `end_shift`, `resignin`, `correct_position`, `update_position`, `delete_mistake`), actions in `app/controllers/concerns/shift_manage_concern.rb`
Owner: `ShiftManage` (`app/lib/shift_manage.rb`), `ShiftManageConcern` (`app/controllers/concerns/shift_manage_concern.rb`), `TimesheetManagement` (`app/lib/timesheet_management.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_event` (w), `person` (w), `person_status` (w), `person_position` (w), `person_role` (w), `person_pod` (w), `pod` (w), `action_logs` (w), `position`, `slot`, `person_slot`
Verify: `test/controllers/person/timesheets_controller_test.rb`, `test/lib/shift_manage_test.rb`, `test/controllers/concerns/person_concern_test.rb`, `test/controllers/hq/shift_manage_controller_test.rb`, `test/controllers/me/shift_manage_controller_test.rb`
Trap: `PersonTimesheetConcern`'s `authorize_role` bounces a Shift-Management-only user to /me before `:manage_shifts` is checked — HQ workers check people in at `GET /hq/:person_id/shift-manage`.
Trap: The interstitials (blocked, too-short, correct-position) stream into the "modal" frame via `turbo_stream.update` — every form or button in them needs `data: { turbo_frame: "_top" }` or the success redirect stays trapped.

### Person › Missing Timesheet Requests
Reach it: `GET /person/:person_id/timesheets/missing-requests/new` → linked from Person › Timesheets ("New Request"); create `POST /person/:person_id/timesheets/missing-requests`; review `GET /person/:person_id/timesheets/missing-requests/:id/edit` → `PATCH /person/:person_id/timesheets/missing-requests/:id`; view `GET /person/:person_id/timesheets/missing-requests/:id`
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `TIMESHEET_MANAGEMENT` (`PersonTimesheetConcern`) for `new`, `create` and `show`; `edit`, `update` and `destroy` need `TIMESHEET_MANAGEMENT` (or `ADMIN`); `create` permits review fields only for those roles
Controller: `app/controllers/person/missing_requests_controller.rb` (`new`, `create`, `show`, `edit`, `update`, `destroy`), `app/controllers/concerns/person_timesheet_concern.rb`
Owner: `TimesheetMissingReview` (`app/lib/timesheet_missing_review.rb`), `TimesheetMissing` (`app/models/timesheet_missing.rb`)
Touches: `timesheet_missing` (w), `timesheet_missing_note` (w), `timesheet` (w), `timesheet_log` (w), `timesheet_note` (w), `person_event` (w), `person` (w), `action_logs` (w), `person_position`, `position`
Verify: `test/controllers/person/missing_requests_controller_test.rb`, `test/controllers/person/timesheets_controller_test.rb`
Trap: `update` resets a request to pending whenever `additional_notes` arrives without a `review_status` change — keep that requester-note field off `app/views/person/missing_requests/edit.html.erb` or every note reopens an approved request.
Trap: A bare `Timesheet.create` skips the position check, note copy, `CREATED`/`VIA_MISSING_ENTRY` log and present-year un-confirm — approve-and-create must go through `TimesheetMissingReview.save_and_maybe_create_entry` (one transaction).

### Person › Schedule / Sign-Ups
Reach it: `GET /person/:person_id/schedule` → Person › Essentials › Schedule / Sign-Ups; remove `DELETE /person/:person_id/schedule/:slot_id`; who's signed up `GET /person/:person_id/schedule/:slot_id/signups`; summary `GET /person/:person_id/schedule/signup-summary`; qualifications `GET /person/:person_id/schedule/qualifications`; calendar `GET /person/:person_id/schedule/export`
Gate: `PersonConcern::VIEW_ROLES` only; no write gate, so any viewer can remove a sign-up — `SHIFT_MANAGEMENT` included on purpose (ruled 2026-10-10), though Clubhouse 2's `SchedulePolicy` admits only `EVENT_MANAGEMENT`, `ADMIN`, `VC`, `TRAINER`, `MENTOR`
Controller: `app/controllers/person/scheduling_controller.rb` (`index`, `signups`, `destroy`, `signup_summary`, `qualifications`, `export`), actions in `app/controllers/concerns/schedule_concern.rb` and `app/controllers/concerns/qualifications_concern.rb`
Owner: `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `Scheduling::Summaries` (`app/lib/scheduling/summaries.rb`)
Touches: `person_slot` (w), `slot` (w), `person` (w), `action_logs` (w), `position`, `person_position`, `position_credit`, `timesheet`, `event_dates`, `setting`
Verify: `test/controllers/person/scheduling_controller_test.rb`, `test/controllers/concerns/person_concern_test.rb`, `test/controllers/hq/scheduling_controller_test.rb`, `test/controllers/me/schedule_controller_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`
Trap: `ScheduleConcern#destroy` reports a failed removal with a `success:` flash ("The shift could not removed.") — assert on the message text, not `flash[:success]`.
Trap: `ScheduleConcern`, `QualificationsConcern` and `common/schedule` also serve `Me::ScheduleController` and `Hq::SchedulingController` — person links go in `app/views/person/scheduling/index.html.erb`'s path lambdas and `schedule_redirect_path`/`set_back_to`.

### Person › Available Sign-Ups
Reach it: `GET /person/:person_id/schedule/sign-ups` → linked from Person › Schedule / Sign-Ups; position `GET /person/:person_id/schedule/sign-ups/position/:position_id`; add `POST /person/:person_id/schedule/sign-ups/position/:position_id/slot/:slot_id`; remove `DELETE /person/:person_id/schedule/sign-ups/position/:position_id/slot/:slot_id`
Gate: `PersonConcern::VIEW_ROLES` only; no write gate — `SHIFT_MANAGEMENT` adds and removes sign-ups on purpose (ruled 2026-10-10; see Person › Schedule / Sign-Ups)
Controller: `app/controllers/person/available_sign_ups_controller.rb` (`index`, `show`, `create`, `destroy`), actions in `app/controllers/concerns/available_sign_ups_concern.rb`
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `Scheduling::Permission` (`app/lib/scheduling/permission.rb`), `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Position#scheduling_header_for` (`app/models/position.rb`)
Touches: `person_slot` (w), `slot` (w), `person` (w), `action_logs` (w), `position`, `person_position`, `person_event`, `person_online_course`, `person_photo`, `setting`
Verify: `test/controllers/person/scheduling_controller_test.rb`, `test/controllers/hq/available_sign_ups_controller_test.rb`, `test/controllers/me/available_sign_ups_controller_test.rb`, `test/lib/scheduling/permission_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`
Trap: In the present year `retrieve_permission_and_recommendation` redirects every action to the schedule on an unmet `Scheduling::Permission` requirement, even for an admin, and `create` never forces (`Scheduling::Signup.add(@person, @slot, false)`).
Trap: `destroy` forces (`Scheduling::Signup.remove(@person, @slot, true)`), so an admin, or a Trainer/Mentor on an in-person training/Alpha slot (`can_force_schedule_change`), removes started or ended shifts unconfirmed, unlike `ScheduleConcern#destroy`.
Trap: `show` prints the position's sign-up page header by the subject's status (`Position#scheduling_header_for`, see Me › Available Sign-Ups): an operator sees what the member sees.

### Person › Work History
Reach it: `GET /person/:person_id/work-history` → Person › Training & History › Work History; drill-downs `GET /person/:person_id/work-history/position-summary`, `GET /person/:person_id/work-history/position-all`, `GET /person/:person_id/work-history/entire-year`
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `TIMESHEET_MANAGEMENT` (replaces VIEW_ROLES)
Controller: `app/controllers/person/work_history_controller.rb` (`index`), drill-downs and `load_work_history` in `app/controllers/concerns/work_history_concern.rb` (`position_summary`, `position_all`, `entire_year`)
Owner: `WorkHistoryReport` (`app/lib/reports/work_history_report.rb`), `WorkHistoryConcern` (`app/controllers/concerns/work_history_concern.rb`)
Touches: `timesheet`, `position`, `position_credit`
Verify: `test/controllers/person/work_history_controller_test.rb`, `test/controllers/me/work_history_controller_test.rb`
Trap: `WorkHistoryReport` drops Alpha, Deep Freeze and any position titled with "Training", and files pre-2008 entries only under `inaccurate_years`, so drill-downs for those return an empty 422 (`head :unprocessable_entity`).
Trap: `WorkHistoryConcern` has no authorization (it also backs `Me::WorkHistoryController`) — keep the role gate in each including controller.

## HQ Window

Every controller includes `HqConcern`, directly or via `HqTimesheetConcern`: `authorize_role [ADMIN, SHIFT_MANAGEMENT]` (a later `authorize_role` replaces it, never narrows), `set_person` from `:person_id`, setting `HQ_WINDOW_INTERFACE_ENABLED`, `load_hq_shell`, layout `layouts/hq.html.erb`. The year is always `Current.year` (no `setup_year`). `load_hq_shell` consumes the once-per-person entry-warning flag, so several controllers skip it on redirect, download or stream actions.

### Switch to HQ Interface (HQ index redirector)
Reach it: `GET /hq/:person_id` → person page hero "Switch to HQ Interface" (via `GET /person/:person_id/redirect_to_hq`, `PersonController#redirect_to_hq`); search bar HQ Window mode (`SearchBarPolicy::MODE_PATHS`)
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/index_controller.rb` (`show`)
Owner: inline in controller — `Person#on_site` picks shift manage, else on-site registration
Touches: `person`
Verify: `test/controllers/hq/index_controller_test.rb`, `test/lib/search_bar_policy_test.rb`, `test/controllers/autocomplete_controller_test.rb`, `test/system/search_bar_hotkey_test.rb`

### HQ › Shift Check In/Out (shift manage)
Reach it: `GET /hq/:person_id/shift-manage` → HQ sidebar › HQ Window › Shift Check In/Out; start `POST /hq/:person_id/shift-manage/shift/start`; end `POST /hq/:person_id/shift-manage/shift/end`; resume `POST /hq/:person_id/shift-manage/shift/resignin`; verify `PATCH /hq/:person_id/shift-manage/timesheet/:timesheet_id/verify`; correction `PATCH /hq/:person_id/shift-manage/timesheet/:timesheet_id/correction`; missing request `GET /hq/:person_id/shift-manage/missing-request/new` → `POST /hq/:person_id/shift-manage/missing-request`; pog `POST /hq/:person_id/shift-manage/pogs`; radio `POST /hq/:person_id/shift-manage/assets`; off site `POST /hq/:person_id/shift-manage/off-site`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED; forcing a blocked check-in or position change: `ADMIN`, `CAN_FORCE_SHIFT` (`ShiftManage::FORCE_ROLES`)
Controller: `app/controllers/hq/shift_manage_controller.rb` (`index`, `verify_timesheet`, `unverify_timesheet`, `correction_form`, `submit_correction`, `new_missing_request`, `create_missing_request`, `new_pog`, `create_pog`, `edit_pog`, `cancel_pog_form`, `update_pog`, `mark_off_site`), `app/controllers/concerns/shift_manage_concern.rb` (`start_shift`, `end_shift`, `resignin`, `correct_position`, `update_position`, `delete_mistake`), `app/controllers/concerns/asset_management_concern.rb` (`asset_checkout`, `asset_check_in`, `asset_change_attachment`, `asset_update_attachment`), `app/javascript/controllers/hq_shift_controller.js` (checklist chips, Skip Review flags, leave-page guards)
Owner: `ShiftManage` (`app/lib/shift_manage.rb`), `RadioAccounting` (`app/lib/radio_accounting.rb`), `HqTodo` (`app/lib/hq_todo.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `timesheet_note` (w), `timesheet_missing` (w), `timesheet_missing_note` (w), `person_pog` (w), `person_asset` (w), `person` (w), `person_on_site` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_event` (w), `person_pod` (w), `pod` (w), `action_logs` (w), `asset`, `asset_attachment`, `slot`, `position`
Verify: `test/controllers/hq/shift_manage_controller_test.rb`, `test/lib/shift_manage_test.rb`, `test/lib/radio_accounting_test.rb`, `test/models/person_pog_test.rb`, `test/models/person_asset_test.rb`
Trap: stream actions here read the shell's `@event_info`, `@event_periods`, `@person_event` (`pog_issue_warnings`, `load_assets`) — never `skip_before_action :load_hq_shell` here, or pogs and radios break.
Trap: an action changing timesheets, assets or pogs leaves the folded section rows on stale counts — also stream `section_summary_streams`/`pogs_summary_stream`, with `replace`.

### HQ › On-Site Registration (site registration)
Reach it: `GET /hq/:person_id/site-registration` → HQ sidebar › HQ Window › On-Site Registration; steps `PATCH /hq/:person_id/site-registration/camp-info`, `PATCH /hq/:person_id/site-registration/emergency-contact`, `GET /hq/:person_id/site-registration/radio-check`, radios `POST /hq/:person_id/site-registration/assets`; commit `POST /hq/:person_id/site-registration/on-site`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED; emergency-contact save: `can_edit_emergency_contact?` (`ADMIN`/`VC`, or `EVENT_MANAGEMENT`/`EVENT_MANAGEMENT_ON_PLAYA` with setting EVENT_MANAGEMENT_ON_PLAYA_ENABLED, or `EDIT_EMERGENCY_CONTACT`); no step saves once on site (`block_when_on_site`)
Controller: `app/controllers/hq/site_registration_controller.rb` (`show`, `save_camp_info`, `save_emergency_contact`, `radio_check`, `mark_on_site`), `app/controllers/concerns/asset_management_concern.rb` (`asset_checkout`, `asset_check_in`, `asset_change_attachment`, `asset_update_attachment`; outcomes via this controller's `assets_outcome` override, a Turbo Stream into `hq-step-radios`), `app/javascript/controllers/hq_wizard_controller.js` (client-side step engine)
Owner: inline in controller over `Person`/`PersonAsset`; `AssetManagementConcern` (`app/controllers/concerns/asset_management_concern.rb`); `PersonEventInfo` (`app/lib/person_event_info.rb`)
Touches: `person` (w), `person_on_site` (w), `person_asset` (w), `action_logs` (w), `asset`, `asset_attachment`, `person_event`, `bmid`, `provision`
Verify: `test/controllers/hq/site_registration_controller_test.rb`, `test/models/person_on_site_test.rb`, `test/models/person_asset_test.rb`
Trap: `radio_check` (`allowed_event_radio?`) and the `assets_outcome` override read the shell's `@event_info`/`@person_event` — keep `load_hq_shell` on its stream actions or they raise on nil.
Trap: `Person#log_on_site_change` (`after_save`) writes `person_on_site` history — flip `on_site` with `save(validate: false)` as `mark_on_site`/`Hq::ShiftManageController#mark_off_site` do, never `update_column`/`update_all`.

### HQ › Schedule / Sign Ups
Reach it: `GET /hq/:person_id/schedule` → HQ sidebar › HQ Window › Schedule / Sign Ups; remove `DELETE /hq/:person_id/schedule/:slot_id`; who else `GET /hq/:person_id/schedule/:slot_id/signups`; hours `GET /hq/:person_id/schedule/signup-summary`; calendar `GET /hq/:person_id/schedule/export`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/scheduling_controller.rb` (`index`, `export`, `signups`, `destroy`, `signup_summary`), actions from `app/controllers/concerns/schedule_concern.rb`; `setup_year` overridden to `Current.year`
Owner: `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `Scheduling::Summaries` (`app/lib/scheduling/summaries.rb`)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `position`, `person_position`, `position_credit`
Verify: `test/controllers/hq/scheduling_controller_test.rb`, `test/lib/scheduling/query_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`, `test/controllers/person/scheduling_controller_test.rb`
Trap: `ScheduleConcern#signup_summary` and `Hq::TimesheetsController#event_summary` assign `@summary`, so a shell `@summary` would show scheduled hours as earned — prefix new `HqConcern` ivars `hq_`, like `@hq_summary`.
Trap: `include HqConcern` must precede `ScheduleConcern` — reversed, `ensure_person_for_schedule` loads the operator and `setup_slot` checks their sign-up on `destroy`.

### HQ › Available Sign-Ups
Reach it: `GET /hq/:person_id/schedule/sign-ups` → linked from HQ › Schedule / Sign Ups; position `GET /hq/:person_id/schedule/sign-ups/position/:position_id`; add `POST /hq/:person_id/schedule/sign-ups/position/:position_id/slot/:slot_id`; remove `DELETE /hq/:person_id/schedule/sign-ups/position/:position_id/slot/:slot_id`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED; subject must have no unmet `Scheduling::Permission` requirements (`retrieve_permission_and_recommendation`)
Controller: `app/controllers/hq/available_sign_ups_controller.rb` (`index`, `show`, `create`, `destroy`), actions from `app/controllers/concerns/available_sign_ups_concern.rb`; `setup_year` overridden to `Current.year`
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `Scheduling::Query` (`app/lib/scheduling/query.rb`), `Scheduling::Permission` (`app/lib/scheduling/permission.rb`), `Position#scheduling_header_for` (`app/models/position.rb`)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `position`, `person_position`, `position_credit`
Verify: `test/controllers/hq/available_sign_ups_controller_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`, `test/lib/scheduling/permission_test.rb`, `test/controllers/me/available_sign_ups_controller_test.rb`
Trap: `include HqConcern` must precede `AvailableSignUpsConcern` — reversed, `ensure_person_for_available_sign_ups` loads the operator, so `retrieve_permission_and_recommendation` and `setup_position` gate on the operator.
Trap: `AvailableSignUpsConcern#destroy` calls `Scheduling::Signup.remove(@person, @slot, true)`, so an operator who can force (`ADMIN`, `Scheduling::Signup.can_force_schedule_change`) removes a started shift from a stale page — check `slot.has_started`.
Trap: `show` prints the position's sign-up page header by the subject's status (`Position#scheduling_header_for`, see Me › Available Sign-Ups): an operator sees what the member sees.

### HQ › Qualifications
Reach it: `GET /hq/:person_id/schedule/qualifications` → linked from HQ › Schedule / Sign Ups
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/scheduling_controller.rb` (`qualifications` from `app/controllers/concerns/qualifications_concern.rb`; `set_back_to` sets `@back_to_url`/`@signups_url`)
Owner: `TicketsAndProvisionsProgress` (`app/lib/tickets_and_provisions_progress.rb`), `QualificationsPresenter` (`app/presenters/qualifications_presenter.rb`)
Touches: `timesheet`, `position_credit`, `slot`, `person_slot`, `position`, `event_dates`, `setting`
Verify: `test/controllers/hq/scheduling_controller_test.rb`, `test/presenters/qualifications_presenter_test.rb`, `test/controllers/me/qualifications_controller_test.rb`

### HQ › Messages
Reach it: `GET /hq/:person_id/messages` → HQ sidebar › HQ Window › Messages; compose `GET /hq/:person_id/messages/new` (`?direction=to|from`) → `POST /hq/:person_id/messages`; thread `GET /hq/:person_id/messages/:id`; reply `POST /hq/:person_id/messages/:id/reply`; read toggle `POST /hq/:person_id/messages/:id/read`; archive toggle `POST /hq/:person_id/messages/:id/archive`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED (not the /person mailbox's `EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`)
Controller: `app/controllers/hq/messages_controller.rb` (`index`, `show`, `new`, `create`, `find_recipient`, `search_callsigns`, `select_callsign`, `toggle_read`, `toggle_archive`, `create_reply`, all from `app/controllers/concerns/messages_concern.rb` + `app/controllers/concerns/message_direction_concern.rb`)
Owner: `MessagesConcern` (`app/controllers/concerns/messages_concern.rb`), `MessageDirectionConcern` (`app/controllers/concerns/message_direction_concern.rb`), `PersonMessage` (`app/models/person_message.rb`)
Touches: `person_message` (w), `broadcast` (w), `broadcast_message` (w), `person`, `person_alert`, `email_suppression`
Verify: `test/controllers/hq/messages_controller_test.rb`, `test/controllers/person/messages_controller_test.rb`, `test/controllers/me/messages_controller_test.rb`
Trap: opening a thread at HQ never marks it read (`MessageDirectionConcern#mark_read_on_view?` is false) — the shell's unread count and the shift page's "Deliver Messages" chip clear only via the read toggle.
Trap: re-registering `before_action :load_hq_shell` replaces `HqConcern`'s registration and options (`show`/`new` then 500) — wrap it under a new name as `load_hq_shell_unless_stream` does.

### HQ › Timesheet / Corrections
Reach it: `GET /hq/:person_id/timesheets` → HQ sidebar › HQ Window › Timesheet / Corrections; verify `PATCH /hq/:person_id/timesheets/:id/verified`; correction `GET /hq/:person_id/timesheets/:id/edit` → `PATCH /hq/:person_id/timesheets/:id`; hours & credits `GET /hq/:person_id/timesheets/event-summary`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED; subject status: an active status or `echelon` (`HqTimesheetConcern#require_subject_can_use_timesheets`, else redirect to shift manage)
Controller: `app/controllers/hq/timesheets_controller.rb` (`index`, `event_summary`), `app/controllers/concerns/timesheet_corrections_concern.rb` (`mark_verified`, `edit`, `update`), `app/controllers/concerns/hq_timesheet_concern.rb` (data and paths, over `app/controllers/concerns/timesheet_concern.rb`)
Owner: `Timesheet` (`app/models/timesheet.rb`), `TimesheetManagement` (`app/lib/timesheet_management.rb`), `EventSummaryReport` (`app/lib/reports/event_summary_report.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `timesheet_note` (w), `person_event` (w), `timesheet_missing`, `position`, `position_credit`, `person_position`
Verify: `test/controllers/hq/timesheets_controller_test.rb`, `test/controllers/me/timesheet_controller_test.rb`, `test/models/timesheet_test.rb`, `test/lib/reports/event_summary_report_test.rb`
Trap: `HqTimesheetConcern#corrections_setting_enabled?` is hard-wired `true`, so `TIMESHEET_CORRECTION_ENABLE` gates only /me, and verifying the last entry lands on `hq_timesheets_path`, never the /me-only final confirmation.
Trap: verify and correction exist twice at HQ (`TimesheetCorrectionsConcern` and `Hq::ShiftManageController#verify_timesheet`/`#submit_correction`) — land a behaviour change in both.

### HQ › Missing Timesheet Requests
Reach it: `GET /hq/:person_id/timesheets/missing-requests` → linked from HQ › Timesheet / Corrections; new `GET /hq/:person_id/timesheets/missing-requests/new` → `POST /hq/:person_id/timesheets/missing-requests`; amend `GET /hq/:person_id/timesheets/missing-requests/:id/edit` → `PATCH /hq/:person_id/timesheets/missing-requests/:id`; withdraw `DELETE /hq/:person_id/timesheets/missing-requests/:id`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED; subject status: an active status or `echelon` (`HqTimesheetConcern#require_subject_can_use_timesheets`)
Controller: `app/controllers/hq/missing_requests_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, all from `app/controllers/concerns/missing_requests_concern.rb`), subject/paths from `app/controllers/concerns/hq_timesheet_concern.rb`
Owner: `MissingRequestsConcern` (`app/controllers/concerns/missing_requests_concern.rb`), `TimesheetMissing` (`app/models/timesheet_missing.rb`)
Touches: `timesheet_missing` (w), `timesheet_missing_note` (w), `position`, `person_position`, `timesheet`
Verify: `test/controllers/hq/missing_requests_controller_test.rb`, `test/controllers/me/missing_requests_controller_test.rb`
Trap: `MissingRequestsConcern#create` lacks the `with_defaults(partner: "")` that `Hq::ShiftManageController#create_missing_request` adds, which NOT NULL, default-less `timesheet_missing.partner` needs when a payload omits it.
Trap: `HqTimesheetConcern` must include `HqConcern` and `TimesheetConcern` at module level — inside `included do`, `TimesheetConcern`'s /me defaults (`timesheet_person = current_user`, `me_*` paths) shadow every HQ override.

### HQ › Asset Check In/Out
Reach it: `GET /hq/:person_id/assets` → HQ sidebar › HQ Window › Asset Check In/Out; checkout `POST /hq/:person_id/assets`; check in `PATCH /hq/:person_id/assets/:person_asset_id/check-in`; attachment `GET /hq/:person_id/assets/:person_asset_id/change-attachment` → `PATCH /hq/:person_id/assets/:person_asset_id/attachment`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/assets_controller.rb` (`index`), `app/controllers/concerns/asset_management_concern.rb` (`asset_checkout`, `asset_check_in`, `asset_change_attachment`, `asset_update_attachment`)
Owner: `AssetManagementConcern` (`app/controllers/concerns/asset_management_concern.rb`), `PersonAsset` (`app/models/person_asset.rb`), `Asset` (`app/models/asset.rb`)
Touches: `person_asset` (w), `action_logs` (w), `asset`, `asset_attachment`, `person_event`
Verify: `test/controllers/hq/assets_controller_test.rb`, `test/models/person_asset_test.rb`, `test/models/asset_test.rb`, `test/controllers/person/assets_controller_test.rb`
Trap: `AssetManagementConcern#asset_checkout` never checks the Radio Checkout Agreement (`person_event.asset_authorized`); only `app/views/hq/assets/index.html.erb` hides the form, so a direct `POST /hq/:person_id/assets` still checks gear out.

### HQ › Training / ARTs
Reach it: `GET /hq/:person_id/training` → HQ sidebar › HQ Window › Training / ARTs
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/training_controller.rb` (`index`, empty; data from `HqConcern#load_hq_shell`)
Owner: `PersonEventInfo` (`app/lib/person_event_info.rb`), `Training` (`app/lib/training.rb`)
Touches: `person_online_course`, `trainee_status`, `trainer_status`, `slot`, `person_slot`, `position`, `person_position`
Verify: `test/controllers/hq/training_controller_test.rb`, `test/controllers/person/training_controller_test.rb`, `test/lib/training_test.rb`
Trap: `index` is empty on purpose — the view renders the shell's present-year `@event_info` and `@year` is nil, so never `skip_before_action :load_hq_shell` here and use `Current.year` in the view.

### HQ › Tickets and Provisions Progress
Reach it: `GET /hq/:person_id/tickets-provisions` → HQ shell right-column "Tickets & Provisions Progress" button (`app/views/hq/shared/_summary_column.html.erb`, `modal` frame); lazy frame re-requests `GET /hq/:person_id/tickets-provisions?progress=1`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`; setting: HQ_WINDOW_INTERFACE_ENABLED
Controller: `app/controllers/hq/tickets_provisions_controller.rb` (`show`; skips `load_hq_shell`, renders `layout: false`)
Owner: `TicketsAndProvisionsProgress` (`app/lib/tickets_and_provisions_progress.rb`)
Touches: `timesheet`, `position_credit`, `slot`, `person_slot`, `position`, `event_dates`, `setting`
Verify: `test/controllers/hq/tickets_provisions_controller_test.rb`, `test/controllers/me/qualifications_controller_test.rb`

## Training: sessions

Every controller inherits `Training::BaseController` (layout `training`): `load_training` resolves `:slug` via `Training.find_training_position` (unknown slug or numeric id → /me), `authorize_training_view` admits `Training.view_roles`, `setup_year` reads `?year=` (default: present year). `Training::Sessions::BaseController` adds `load_session` + `authorize_session_management`; graduation and work history swap the latter for `authorize_graduation`. Every training page prints a person through `person_display_link`: an ART trainer without a person-page role (`PersonConcern::VIEW_ROLES`) gets the callsign as text, where `callsign_link` would hand them a link that bounces to /me.

### Training › Sessions
Reach it: `GET /training/:slug` → In-Person Training › In-Person Training › Sessions (ARTs: ART <name> › ART <name> › Sessions; one category per active training position)
Gate: `authorize_training_view` (`Training.view_roles`): `ADMIN`, `TRAINER`, `MENTOR`, `VC` (In-Person); `ADMIN`, `ART_TRAINER_BASE | position.id` (ART)
Controller: `app/controllers/training/sessions_controller.rb` (`index`); `app/controllers/training/base_controller.rb` (`load_training`, `authorize_training_view`, `setup_year`)
Owner: `Training::SessionList` (`app/lib/training/session_list.rb`), `Training` (`app/lib/training.rb`: `slug`, `find_training_position`, `view_roles`, `session_position_ids`), `TrainingMenu` (`app/lib/training_menu.rb`)
Touches: `position`, `slot`, `person_slot`, `person`, `trainer_status`
Verify: `test/controllers/training/sessions_controller_test.rb`, `test/lib/training/session_list_test.rb`, `test/lib/training_menu_test.rb`, `test/lib/training_test.rb`, `test/helpers/training/session_link_helper_test.rb`
Trap: `Training::SessionList.execute` partitions on `Slot#has_day_ended?`, not `has_ended`, so a session ended earlier today (slot timezone) stays under "In Progress & Upcoming Sessions" until the next day — deliberate, so trainers can finish scoring.
Trap: A Position passed to a path helper emits its numeric id (no `to_param`), which `find_training_position` redirects away — build paths with `training_slug` / `Training.slug(position)`.

### Training Session
Reach it: `GET /training/:slug/session/:slot_id` → the session time on Training › Sessions; the training reports' `training_session_link` (`app/helpers/training/session_link_helper.rb`)
Gate: `authorize_training_view` (view_roles); Score / Add Person / Add Trainer / Graduate Trainees / Work History follow `can_manage_session?`, `can_adjust_roster?`, `can_graduate?`
Controller: `app/controllers/training/sessions_controller.rb` (`show`); `app/controllers/training/base_controller.rb` (`load_session`, ability helpers)
Owner: `TrainingSession` (`app/lib/training_session.rb`), `TrainingSession::Graduation` (`app/lib/training_session/graduation.rb`), `Training::SessionsHelper` (`app/helpers/training/sessions_helper.rb`)
Touches: `slot`, `person_slot`, `person`, `person_photo`, `trainee_status`, `trainee_note`, `person_status`, `person_intake`, `person_position`, `position`, `person_fka`, `trainer_status`
Verify: `test/controllers/training/session_page_test.rb`, `test/lib/training_session_test.rb`
Trap: `TrainingSession::Trainee#status` is the person's status at `slot.ends` (`person_status` history) and `#current_status` today's — the trainer's verdict is `#training_status`, never `status`.
Trap: `Training::SessionList.trainer_slot_match?` (exact description match, trainer slot begins in [session begins − 1 hour, session ends]) groups trainers for the landing page and `TrainingSession#build_trainer_groups` — change it there only.

### Score Trainee (score dialog, trainer notes)
Reach it: `GET /training/:slug/session/:slot_id/score/:person_id` → Score on a Training Session trainee card (modal); save `POST /training/:slug/session/:slot_id/score/:person_id`; notes `GET /training/:slug/session/:slot_id/notes/:note_id/edit`, `PATCH`/`DELETE /training/:slug/session/:slot_id/notes/:note_id`
Gate: `authorize_session_management` → `can_manage_session?`: `ADMIN`, `TRAINER` (In-Person); `ADMIN`, `ART_TRAINER_BASE | position.id` (ART); note edits: author-only, never `is_log` rows (`NotesController#load_note`)
Controller: `app/controllers/training/sessions/scores_controller.rb` (`edit`, `update`), `app/controllers/training/sessions/notes_controller.rb` (`edit`, `update`, `destroy`), `app/controllers/training/sessions/base_controller.rb`
Owner: `TrainingSession#score!` (`app/lib/training_session.rb`), `Training::ScoreForm` (`app/forms/training/score_form.rb`), `TraineeNote` (`app/models/trainee_note.rb`)
Touches: `trainee_status` (w), `trainee_note` (w), `action_logs` (w), `slot`, `person_slot`, `person`, `person_status`, `person_intake`
Verify: `test/controllers/training/sessions/scores_controller_test.rb`, `test/lib/training_session_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: `TraineeStatus#rank` maps the legacy column default 0 to nil — read it through the getter, never `pluck`/raw SQL, or the page shows "Rank 0" and `score!` logs a bogus rank-change note.
Trap: `update_all`/`upsert` skip `TraineeStatus`'s `after_commit :purge_role_cache`, so cached roles miss training-gated grants and revokes — write verdicts through `score!` (a model `save!`).

### Save Trainers (session trainer attendance)
Reach it: `POST /training/:slug/session/:slot_id/trainer-statuses` → Save Trainers in the Trainers section of Training Session
Gate: `authorize_session_management` → `can_manage_session?`: `ADMIN`, `TRAINER` (In-Person); `ADMIN`, `ART_TRAINER_BASE | position.id` (ART)
Controller: `app/controllers/training/sessions/trainer_statuses_controller.rb` (`update_all`), `app/controllers/training/sessions/base_controller.rb`
Owner: `TrainingSession#save_trainer_statuses!` (`app/lib/training_session.rb`), `TrainerStatus` (`app/models/trainer_status.rb`) (not `Training::TrainerAttendanceReport`, a read-only report)
Touches: `trainer_status` (w), `slot`, `person_slot`, `person`, `position`
Verify: `test/controllers/training/sessions/rosters_controller_test.rb`, `test/lib/training_session_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: `Slot#trainer_status` is a computed-column reader (`read_attribute`) shadowing the `has_many :trainer_status` association, and `trainer_status.slot_id` is the session's slot (`trainer_slot_id` the trainer's) — query `TrainerStatus` directly.
Trap: Rows whose `[trainer_slot_id, person_id]` is not on a matched trainer group's roster, or whose status is not pending/attended/no-show, are silently skipped, yet the page still flashes "Trainer attendance was updated."

### Add Person / Add Trainer (session roster)
Reach it: `GET /training/:slug/session/:slot_id/roster/new` → Add Person / Add Trainer on Training Session (modal search); add `POST /training/:slug/session/:slot_id/roster`; remove `DELETE /training/:slug/session/:slot_id/roster/:person_id`
Gate: `authorize_session_management` + `authorize_roster_adjustment` → `can_adjust_roster?`: `ADMIN` or a directly assigned `TRAINER` (In-Person); `ADMIN`, `ART_TRAINER_BASE | position.id` (ART)
Controller: `app/controllers/training/sessions/rosters_controller.rb` (`new`, `create`, `destroy`), `app/controllers/training/sessions/base_controller.rb`
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `PersonSearch` (`app/lib/person_search.rb`), `TrainingSession#trainer_groups` (`app/lib/training_session.rb`)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `person` (w), `person_fka`, `email_history`, `person_position`, `position`
Verify: `test/controllers/training/sessions/rosters_controller_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`, `test/lib/person_search_test.rb`
Trap: `has_role?(Role::TRAINER)` also admits the Trainer Seasonal masquerade, which `can_adjust_roster?` refuses — In-Person roster checks use `Current.roles_manager.has_directly_assigned_role?(Role::TRAINER)`.
Trap: Forms in the "modal" frame that redirect to the session page (add, Add Anyway, Remove From Session) need `data: { turbo_frame: "_top" }` or only the modal swaps and the roster looks stale; blocked verdicts still return 422 turbo-streams.

### Graduate Trainees
Reach it: `GET /training/:slug/session/:slot_id/graduation` → Graduate Trainees on an ART Training Session (modal); grant `POST /training/:slug/session/:slot_id/graduation`
Gate: `authorize_training_view` then `authorize_graduation` → `can_graduate?`: ART only; `ADMIN`, or `ART_TRAINER_BASE | position.id` + `ART_GRADUATE_BASE | position.id`; the ART also needs a `Position::ART_GRADUATE_TO_POSITIONS` entry (Green Dot, Tow Truck, Sandman) or `load_graduation` redirects
Controller: `app/controllers/training/sessions/graduations_controller.rb` (`show`, `create`), `app/controllers/training/sessions/base_controller.rb`, `app/controllers/training/base_controller.rb` (`can_graduate?`)
Owner: `TrainingSession::Graduation` (`app/lib/training_session/graduation.rb`), `PersonPosition.add_ids_to_person` (`app/models/person_position.rb`)
Touches: `person_position` (w), `person_position_log` (w), `action_logs` (w), `person_slot`, `person`, `trainee_status`, `position`, `position_role`, `timesheet`
Verify: `test/controllers/training/sessions/graduations_controller_test.rb`, `test/lib/training_session/graduation_test.rb`
Trap: Candidacy needs an explicit passed `TraineeStatus` (deliberately, unlike upstream), and `Graduation::NOT_PASSED` means "anything but a pass" — never compare it with `TraineeStatus::STATUS_NOT_PASSED`.
Trap: `requirement_gaps` counts `person.years_as_ranger` minus `Current.year` (not the session's `begins_year`) and `requirement_stats` sums timesheets across all years, so a past-year session still graduates against today.

### Training Session › Work History
Reach it: `GET /training/:slug/session/:slot_id/work-history/:person_id` → Work History on an ART Training Session trainee card (modal); hour links re-request it with `detail_position_id`/`detail_year` into the `wh-detail` frame
Gate: `authorize_training_view` then `authorize_graduation` → `can_graduate?` (ART only: `ADMIN`, or `ART_TRAINER_BASE | position.id` + `ART_GRADUATE_BASE | position.id`); the person must be on the session roster (`PersonSlot.have_slot?`)
Controller: `app/controllers/training/sessions/work_histories_controller.rb` (`show`), `app/controllers/training/sessions/base_controller.rb`
Owner: `WorkHistoryReport` (`app/lib/reports/work_history_report.rb`; top-level, as `app/lib/reports` is an autoload root; also behind `/person/:person_id/work-history`)
Touches: `timesheet`, `position`, `position_credit`, `person_slot`, `person`
Verify: `test/controllers/training/sessions/graduations_controller_test.rb`
Trap: It is gated on graduation (`skip_before_action :authorize_session_management`) and `can_graduate?` is false unless `Training.art?`, so on In-Person Training everyone is refused, admins and scoring Trainers included.
Trap: `WorkHistoryReport.execute` drops Alpha, Deep Freeze, "Training" titles and pre-2008 entries, so its totals won't match `TrainingSession::Graduation#requirement_stats` (`mentee_requirements` positions, every year) — take readiness from `Graduation`.

### Sign-Up Sheet & Trainer's Report (session print views)
Reach it: `GET /training/:slug/session/:slot_id/signup-sheet` → Sign-Up Sheet on Training Session; `GET /training/:slug/session/:slot_id/trainers-report` → Trainer's Report
Gate: `authorize_training_view` (view_roles; Mentors and VCs can print both)
Controller: `app/controllers/training/sessions_controller.rb` (`signup_sheet`, `trainers_report`; private `trainee_bands`, `band_label_for`, `full_day_callsigns`)
Owner: `TrainingSession` (`app/lib/training_session.rb`); the report's band partition is inline in the controller
Touches: `slot`, `person_slot`, `person`, `person_photo`, `trainee_status`, `trainee_note`, `person_status`, `person_intake`, `person_position`, `position`, `person_fka`, `trainer_status`
Verify: `test/controllers/training/session_page_test.rb`
Trap: A class-level `layout "print", only: [...]` replaces the inherited `training` layout (and sidebar) for every other action — the print views call `render layout: "print"` per action.
Trap: There is deliberately no trainees-per-page constant — `break-inside: avoid`, a repeating thead and a named `@page` rule via `content_for :page_rules` ("Page N of M") paginate; never slice the roster into pages in Ruby.
Trap: The report's bands (`band_label_for`, auditor status first) differ from `TrainingSession#veteran?` behind the on-screen Vets count.

### Trainer Resources
Reach it: `GET /training/:slug/resources` → In-Person Training › In-Person Training › Trainer Resources (ARTs: ART <name> › ART <name> › Trainer Resources); editor `GET /training/:slug/resources/edit`; save `POST`/`PATCH /training/:slug/resources`; delete `DELETE /training/:slug/resources`
Gate: read: `authorize_training_view`; write (`edit`, `create`, `update`, `destroy`): plus `can_manage_resource?` — `ADMIN`, or a view role + `TRAINER_RESOURCE_MANAGEMENT_BASE | position.id`; an ART with no `team_id` refuses everyone, admins included
Controller: `app/controllers/training/resources_controller.rb` (`show`, concern hooks), `app/controllers/concerns/resource_document_crud_concern.rb` (`edit`, `create`, `update`, `destroy`)
Owner: `ResourceDocumentCrudConcern` (`app/controllers/concerns/resource_document_crud_concern.rb`), `Document` (`app/models/document.rb`), `Position#build_resource_tag` (`app/models/position.rb`); the concern and `app/views/common/resource_documents/` are shared with Teams & Positions › Team Resources
Touches: `document` (w), `position` (w), `action_logs` (w)
Verify: `test/controllers/training/resources_controller_test.rb`, `test/models/position_test.rb`
Trap: The body is cleaned twice: on the way in (`submitted_body` → `helpers.rich_text`) and again on the way out (`common/resource_documents/_document` renders `rich_text(document.body)`), because documents written through Clubhouse 2 or Admin › Documents never passed the editor. Never print it `html_safe`.
Trap: A position's `resource_tag` is typed in Position Records and followed only through `Document.resource_tag` (see Team Resources), and every pointer change writes a `position-update` action log by hand (`sync_resource_tag`): Position is not an audited model.
Trap: The tag is derived once, at first save (`scaffold_resource_document` + `sync_resource_tag`), so renaming a position never re-files its document — don't re-derive it on save (it collides with the unique tag index).

## Training: reports & follow-up

Every page inherits `Training::BaseController`: unknown `:slug` → `/me`, gate `Training.view_roles`, `@year` from `?year=` (a year-scoped `filter_bar` must re-send it via `hidden_field_tag :year, @year`). Each CSV (`CsvExportConcern`) exports the whole report, ignoring filters. Menu items live in `TrainingMenu` (`app/lib/training_menu.rb`), one `<training>` category per active training (its links and the category can be starred in the mega menu, and `Training::BaseController#tracked_page?` records Recently visited for its exact menu paths — not session pages or CSVs); `year_scoped: true` carries `?year=` onto their string paths too, and the reports with a filter bar add `active_prefix: true` so their item stays lit once a filter adds params. People print through `person_display_link`, as on the session pages (see Training: sessions).

### Capacity
Reach it: `GET /training/:slug/capacity` → <training> › Reports › Capacity
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/capacity_controller.rb` (`index`, html + csv)
Owner: `Training::CapacityReport` (`app/lib/training/capacity_report.rb`), `Training::SessionList.trainer_slot_match?` (`app/lib/training/session_list.rb`)
Touches: `slot`, `person_slot`, `trainee_status`, `person_status`
Verify: `test/controllers/training/capacity_controller_test.rb`, `test/lib/training/capacity_report_test.rb`, `test/lib/training/session_list_test.rb`, `test/helpers/training/session_link_helper_test.rb`
Trap: `Slot#begins_adjusted` runs `in_time_zone` on `slot.begins`, already local wall-clock time, shifting sessions outside the app zone — export `slot.begins.strftime` plus a `timezone_abbr` column, as `csv_rows` does.
Trap: `count_trainers` counts only active trainer slots while `Training::SessionList` and `TrainerAttendanceReport` include inactive ones — trainer numbers differ by design; do not align them.

### Multiple Enrollments
Reach it: `GET /training/:slug/multiple-enrollments` → <training> › Reports › Multiple Enrollments
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/multiple_enrollments_controller.rb` (`index`, html + csv)
Owner: `Training::MultipleEnrollmentReport` (`app/lib/training/multiple_enrollment_report.rb`)
Touches: `slot`, `person_slot`, `person`, `position`
Verify: `test/controllers/training/multiple_enrollments_controller_test.rb`, `test/helpers/training/session_link_helper_test.rb`
Trap: `Slot.session_group_name` matches "Part N" only at a description's end — keep `MultipleEnrollmentReport.group_key`, and its `.to_s`, since `slot.description` can be NULL.
Trap: `flagged_by_person` reads inactive sessions and skips the HQ Refresher fold (`Training.session_position_ids`) on purpose; `section_position_ids` adds mentee sections only when `Training.has_mentees?`, keeping Sandman's shift position out.

### Completed Training
Reach it: `GET /training/:slug/completed-training` → <training> › Reports › Completed Training; session page `GET /training/:slug/completed-training/:slot_id`
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/completed_training_controller.rb` (`index` html + csv, `show`)
Owner: `Training::CompletedReport` (`app/lib/training/completed_report.rb`), `Training::SessionList.trainer_slot_match?` (`app/lib/training/session_list.rb`)
Touches: `slot`, `trainee_status`, `trainer_status`, `person`
Verify: `test/controllers/training/completed_training_controller_test.rb`, `test/lib/training/completed_report_test.rb`, `test/lib/training/session_list_test.rb`
Trap: `Training::BaseController` already has a private `load_session` that builds a `TrainingSession` — `show` uses `load_report_session`; never name a new report action's loader `load_session`.
Trap: `CompletedReport` counts a pass even after the trainee left the roster, while `CapacityReport` and `TrainedNoWorkReport` require the `person_slot` row — pass counts differ between pages by design.

### All Trainee Notes (all notes)
Reach it: `GET /training/:slug/all-notes` → <ART> › Reports › All Trainee Notes
Gate: `ADMIN`, `ART_TRAINER_BASE | id` (`Training.view_roles` for an ART); `require_art_training` redirects the In-Person slug
Controller: `app/controllers/training/all_notes_controller.rb` (`index`, html + csv)
Owner: `Training::TraineeNotesReport` (`app/lib/training/trainee_notes_report.rb`)
Touches: `trainee_status`, `slot`, `person_slot`, `trainee_note`, `person_position`, `person`
Verify: `test/controllers/training/all_notes_controller_test.rb`
Trap: `standing_by_person` reads mentee positions only when `Training.has_mentees?` — Sandman's `ART_GRADUATE_TO_POSITIONS` entry lists `positions` without the flag, so dropping the gate makes Sandmen mentees.
Trap: `notes_by_pair` drops `is_log: true` `trainee_note` rows (the audit trail) and keys notes by `[person_id, slot_id]` — never group them by person alone.

### Trainer Attendance
Reach it: `GET /training/:slug/trainer-attendance` → <training> › Reports › Trainer Attendance
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/trainer_attendance_controller.rb` (`index`, html + csv)
Owner: `Training::TrainerAttendanceReport` (`app/lib/training/trainer_attendance_report.rb`), `Training::SessionList.trainer_slot_match?` (`app/lib/training/session_list.rb`)
Touches: `slot`, `person_slot`, `trainer_status`, `person`, `position`
Verify: `test/controllers/training/trainer_attendance_controller_test.rb`, `test/lib/training/trainer_attendance_report_test.rb`, `test/lib/training/session_list_test.rb`, `test/helpers/training/session_link_helper_test.rb`
Trap: `Slot#trainer_status` (`app/models/slot.rb`) is a computed-column reader (`read_attribute`) that overrides the `has_many :trainer_status` association — use `TrainerStatus.where(trainer_slot_id:)`, as `rows_by_person` does.
Trap: `Row#slot` is the trainer's own TRAINER slot, which the session page's `load_session` redirects away — link a row via `training_session_link row.slot, session_id: row.session_slot_id`, as `_session_line.html.erb` does.

### Untrained People
Reach it: `GET /training/:slug/untrained-people` → <training> › Reports › Untrained People
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/untrained_people_controller.rb` (`index`, html + csv)
Owner: `Training::UntrainedPeopleReport` (`app/lib/training/untrained_people_report.rb`), `Training.working_position_ids` (`app/lib/training.rb`)
Touches: `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `person`
Verify: `test/controllers/training/untrained_people_controller_test.rb`, `test/helpers/training/session_link_helper_test.rb`
Trap: For a pending trainer, `Row#training_slot` is a TRAINER slot that `load_session` rejects — link a slot only if its position is in `Training.session_position_ids`, as `app/views/training/untrained_people/index.html.erb` does.
Trap: A raw `training_position_id` match finds nothing for In-Person Training — use `Training.working_position_ids`, the single source shared with Trained, No Rangering.

### Trained, No Rangering (trained no work)
Reach it: `GET /training/:slug/trained-no-work` → <training> › Reports › Trained, No Rangering
Gate: `Training.view_roles` — In-Person: `ADMIN`, `TRAINER`, `MENTOR`, `VC`; ART: `ADMIN`, `ART_TRAINER_BASE | id`
Controller: `app/controllers/training/trained_no_work_controller.rb` (`index`, html + csv)
Owner: `Training::TrainedNoWorkReport` (`app/lib/training/trained_no_work_report.rb`), `Training.working_position_ids` (`app/lib/training.rb`)
Touches: `position`, `slot`, `person_slot`, `trainee_status`, `trainer_status`, `timesheet`, `person`
Verify: `test/controllers/training/trained_no_work_controller_test.rb`
Trap: Upstream's join for trainers who taught was dead code — `taught` pairs attendance on `trainer_status.trainer_slot_id` with a sign-up on that trainer slot; do not port the upstream join back.
Trap: `build_people` keeps only `Person::ACTIVE_STATUSES`, so `person(:alpha_ranger)` is always absent — a "rangered, so not listed" test needs an active fixture or it proves nothing.

### Current Mentees (mentees)
Reach it: `GET /training/:slug/mentees` → <ART> › Reports › Current Mentees; revoke `DELETE /training/:slug/mentees/:person_id`; undo `POST /training/:slug/mentees/:person_id/restore`
Gate: `ADMIN`, `ART_TRAINER_BASE | id` to view; `destroy`/`restore` add `can_graduate?` (`ADMIN`, `ART_GRADUATE_BASE | id`); `require_mentee_training` redirects any slug without `Training.has_mentees?` (only Tow Truck and Green Dot)
Controller: `app/controllers/training/mentees_controller.rb` (`index` html + csv, `destroy`, `restore`; both render turbo_stream)
Owner: `Training::MenteesReport` (`app/lib/training/mentees_report.rb`), `PersonPosition.remove_ids_from_person` / `add_ids_to_person` (`app/models/person_position.rb`), `Training.mentee_position_ids` (`app/lib/training.rb`) (not `Training.mentee_position_id`)
Touches: `person_position` (w), `person_position_log` (w), `action_logs` (w), `person_slot` (w), `slot` (w), `timesheet`, `position`, `position_role`, `person` (w)
Verify: `test/controllers/training/mentees_controller_test.rb`, `test/lib/training/mentees_report_test.rb`, `test/lib/training_menu_test.rb`, `test/lib/scheduling/signup_bulk_characterization_test.rb`
Trap: `Training.mentee_position_ids` reads ART graduate mentee positions from `Position::ART_GRADUATE_TO_POSITIONS`; singular `Training.mentee_position_id` reads the one position flagged `is_art_mentee` on an ART mentoring training's team (`has_art_mentoring`) — never swap or merge them.
Trap: A revoke also drops future sign-ups (`Scheduling::Signup::Bulk.remove_future_sign_ups_for_position`); `restore` only re-grants via `add_ids_to_person` dated today, so the closed `person_position_log` row and dropped sign-ups stay gone.

### Training › Mentoring
Reach it: `GET /training/:slug/mentoring` → <ART> › Mentoring (ART mentoring trainings only)
Gate: `Training.view_roles` (ART: `ADMIN`, `ART_TRAINER_BASE | id`), then `Training::Mentoring::BaseController#require_art_mentoring` (`position.has_art_mentoring`, else redirect to the training's Sessions); the menu item keys on the same flag (`TrainingMenu.definition`)
Controller: `app/controllers/training/mentoring/landing_controller.rb` (`index`)
Owner: `ArtMentoring::Shifts` (`app/lib/art_mentoring/shifts.rb`), with `ArtMentoring::VerdictsReport` and `ArtMentoring::MultipleShiftsReport` built on it for the doors' counts
Touches: `position`, `team`, `timesheet`, `slot`, `person_slot`, `person_mentor`, `person_position`, `person`
Verify: `test/controllers/training/mentoring/landing_controller_test.rb`, `test/lib/art_mentoring/shifts_test.rb`, `test/lib/training_menu_test.rb`
Trap: On Shift Now, Next Mentee Shifts and the Mentees on Shift Now and Upcoming Sign-Ups tiles render for the current year only (`@is_current_year`); a past year shows its counts alone.
Trap: On shift, Need a Mentor and Awaiting a Verdict count mentee entries, not shifts (`Shifts::Group#on_shift_entries`, `#needing_mentor`, `#awaiting_verdict`), and each entry is in one state: no mentor yet needs a mentor, on shift or after (a verdict is recorded with a mentor; until 2026-10-22 the tile counted only mentees on shift, so after the event it read 0 while no one had a mentor); a mentor and still Pending once signed out awaits a verdict. An entry open longer than `ArtMentoring::Shifts::ON_SHIFT_WITHIN` (a day) was never signed out and counts as ended, or a past year would hide its shift and pin it on shift for good. Every mentoring page shows the two counts through `art_need_mentor_box` / `art_awaiting_verdict_box`.
Trap: Passed and Bonked come from `ArtMentoring::VerdictsReport#count`, not from the shift groups' walks, so they agree with Verdicts, a deleted entry's walk included.

### Training › Mentoring › Verdicts
Reach it: `GET /training/:slug/mentoring/verdicts` (html, csv) → Training › Mentoring › Verdicts
Gate: as Training › Mentoring; read-only
Controller: `app/controllers/training/mentoring/verdicts_controller.rb` (`index`)
Owner: `ArtMentoring::VerdictsReport` (`app/lib/art_mentoring/verdicts_report.rb`) on `ArtMentoring::Shifts`; the filters' options and chips in `Training::MentoringHelper`
Touches: `person_mentor`, `timesheet`, `slot`, `person_slot`, `position`, `person`
Verify: `test/controllers/training/mentoring/verdicts_controller_test.rb`, `test/lib/art_mentoring/verdicts_report_test.rb`
Trap: A walk outlives its mentee's deleted timesheet entry (ruled 2026-10-21): it is listed as "Shift deleted", counts for its mentor, and no page can change it. An entry moved off every mentee position keeps its walk, at the entry's own time. So the report takes the walks `ArtMentoring::Shifts` found by entry, then adds those filed under the mentee position and `mentor_year` whose entry is not among them -- except one whose entry now sits on another ART's mentee position (`Training.cadre_position_ids(:mentee)`), which counts for that ART, as on its roster (2026-10-22).
Trap: The Verdict and Mentor filters narrow the Verdicts table and its CSV; the Mentors table is always the season. A mentor's Shifts and Average Length come from their own mentor-position entries (ended ones only for the average); walks on a mentee shift they did not sign in around get a line of their own, "Not signed in as a mentor".

### Training › Mentoring › Multiple Shifts
Reach it: `GET /training/:slug/mentoring/multiple-shifts` (html, csv) → Training › Mentoring › Multiple Shifts
Gate: as Training › Mentoring; read-only
Controller: `app/controllers/training/mentoring/multiple_shifts_controller.rb` (`index`)
Owner: `ArtMentoring::MultipleShiftsReport` (`app/lib/art_mentoring/multiple_shifts_report.rb`) on `ArtMentoring::Shifts`; the shift chips in `Training::MentoringHelper#art_mentee_shift_chips`, dated by `DateTimeHelper#short_datetime_format`
Touches: `timesheet`, `slot`, `person_slot`, `person_mentor`, `position`, `person`
Verify: `test/controllers/training/mentoring/multiple_shifts_controller_test.rb`, `test/lib/art_mentoring/multiple_shifts_report_test.rb`
Trap: A shift counts once: the sign-ups are `ArtMentoring::Shifts#upcoming`'s, which drops only the mentees already signed in to a shift early -- the others stay listed as still to come there and here. Latest Verdict is the walk on the latest ended entry; an entry still on shift has none yet. The Kind filter's values are `MultipleShiftsReport::KINDS`.

### Training › Mentoring › Mentor Assignment
Reach it: `GET /training/:slug/mentoring/assignment` (the picker) → Training › Mentoring; one shift `GET /training/:slug/mentoring/assignment/:key`, where `key` is the mentee slot id, or `t` plus the anchor timesheet id for sign-ins that matched no shift; save `POST` the same path
Gate: as Training › Mentoring; `save` also `authorize_session_management` (ART: the same trainer role), in any year (ruled 2026-10-22: a past year's assignments and verdicts are recorded and corrected here, never read-only); only a reader without the trainer role gets the roster with nothing to change. A pass's grants also need the training's ART graduate role (`can_graduate?`)
Controller: `app/controllers/training/mentoring/assignments_controller.rb` (`index`, `show`, `save`)
Owner: `ArtMentoring::Shifts`, `ArtMentoring::Assignment` (`app/lib/art_mentoring/assignment.rb`), `ArtMentoring::Pass` (`app/lib/art_mentoring/pass.rb`), `Training::MentoringHelper` (`app/helpers/training/mentoring_helper.rb`)
Touches: `person_mentor` (w), `action_logs` (w), `person_team` (w), `person_position` (w), `person_slot` (w), `timesheet`, `slot`, `position`, `person`
Verify: `test/controllers/training/mentoring/assignments_controller_test.rb`, `test/lib/art_mentoring/assignment_test.rb`, `test/lib/art_mentoring/pass_test.rb`, `test/lib/art_mentoring/shifts_test.rb`
Trap: Grouping (ruled 2026-10-21): an entry joins the mentee slot its `slot_id` names, else the nearest mentee slot starting within `ArtMentoring::Shifts::WINDOW` (one hour); the rest cluster around the earliest sign-in. A mentor is on a shift when their mentor slot, or with none their sign-in, starts within the hour. Do not unify `WINDOW` with `AlphaSignOut::HOURS_*` or `MentorShiftReport::HOURS_*`.
Trap: One walk is one `person_mentor` row per mentor per mentee timesheet entry (`timesheet_id` + `mentor_id` unique, at most `ArtMentoring::Assignment::MENTOR_SLOTS` mentors, the rows sharing status and notes; `position_id` is the mentee position; `ArtMentoring::Shifts::Walk` wraps an entry's rows). `ArtMentoring::Shifts` finds walks by entry alone, so an entry corrected onto this ART's mentee position from another's brings its walk, and the next save files it here (`position_id`, `mentor_year`; chosen 2026-10-22). `ArtMentoring::Assignment` checks every row before writing and writes the shift in one transaction; No mentor with Pending and no notes destroys the stored walk; a save that loses a race comes back as `Result#conflict`, not a 500, and the page reads the shift again so it shows what is stored. The mentor select never offers the mentee themself.
Trap: `person_mentor` is utf8mb4 (`20261022000001`), so notes keep an emoji; a form sends a line break as CR LF, which the controller folds to LF before the `NOTES_MAX` check, as the textarea's maxlength counts it.
Trap: Pass (ruled 2026-10-21): a graduate saving a row newly set to Passed is asked first. The save answers 422 with `_pass_dialog` inside the roster's form, and only Record Pass (`name="confirmed"`) answers it, so Cancel and then Save asks again. The grants (`ArtMentoring::Pass`: join the team with its Recommended positions -- `TeamManagement::BulkTeamChange.positions_for`, never for a status in `BulkTeamChange::BLOCKED_STATUSES` -- and revoke every mentee position the ART's graduation granted, `Training.mentee_position_ids` plus the flagged one, with their future sign-ups; chosen 2026-10-22). One offer per person: two entries of one mentee on a shift share one answer. The dialog and the flash name the positions the person actually held are written in the walk's transaction: a team or position conferring Admin or Tech Ninja raises `AuthorizationError`, which records nothing and comes back as `Result#denied`. A non-graduate's pass is recorded at once and its row says a graduate can finish it; a graduate later sees Grant Team Positions (`grant_for`) on any recorded pass with something left to grant.
Trap: The pass dialog is `closable: false` because the modal helper's backdrop is a form of its own, and a form cannot nest in the roster's. The title's close button and Cancel both close it without writing. It renders first in the form, so Record Pass is the form's default button: rendered after the rows, Enter on one of its check boxes pressed a row's Grant Team Positions instead, and the question came back with every box reset.
Trap: A walk whose timesheet entry was deleted is orphaned (the table has no foreign keys) and never appears here, so nothing can change it again; Verdicts keeps listing it as "Shift deleted" (ruled 2026-10-21).
Trap: The picker's cards are `common/mentoring/_shift_card`, shared with the Alpha pages' `_alpha_shift_card` so the card's class strings live once (the CSS ratchet had no room for a second copy).

### Online Course Progress
Reach it: `GET /training/:slug/online-course-progress` → In-Person Training › Reports › Online Course Progress
Gate: `Training.view_roles` AND `ADMIN`, `TRAINER` (`Training.online_course_progress_roles`, via `authorize_progress_report`) (menu: In-Person only; an ART URL is not redirected and shows an empty report)
Controller: `app/controllers/training/online_course_progress_controller.rb` (`index`, html + csv)
Owner: `Training::OnlineCourseProgressReport` (`app/lib/training/online_course_progress_report.rb`) (not `PersonOnlineCourse.find_for_query`)
Touches: `person_online_course`, `person`
Verify: `test/controllers/training/online_course_progress_controller_test.rb`
Trap: `PersonOnlineCourse.for_year` and `find_for_query(year:)` filter on the `completed_at` year, dropping everyone still in progress — filter the `year` and `position_id` columns directly, as the report does.
Trap: `test/fixtures/person_online_course.yml` puts `active_ranger` in 2026 In-Person; a new 13/2026/"all" `OnlineCourse` hits `online_course_position_id_year_course_for_unique` — `PersonOnlineCourse.delete_all` in setup, reuse `online_course(:training_all_2026)`.

### Training › Unified Flagging
Reach it: `GET /training/:slug/unified-flagging` → In-Person Training › Reports › Unified Flagging; `?person=:id` fills the read-only review pane; detail frame `GET /training/:slug/unified-flagging/:person_id`
Gate: `ADMIN`, `INTAKE` (`authorize_role Training.unified_flagging_roles`) AND `Training.view_roles` (`ADMIN`, `TRAINER`, `MENTOR`, `VC`); `require_in_person_training` redirects ART slugs (menu: In-Person only, `ADMIN`, `INTAKE`)
Controller: `app/controllers/training/unified_flagging_controller.rb` (URL and read-only hooks), `app/controllers/concerns/unified_flagging_concern.rb` (`index`, `detail`)
Owner: `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`), `Intake` (`app/lib/intake.rb`)
Touches: `person`, `person_status`, `person_intake`, `person_intake_note`, `person_mentor`, `person_fka`, `slot`, `person_slot`, `trainee_status`, `trainee_note`, `trainer_status`, `timesheet`
Verify: `test/controllers/training/unified_flagging_controller_test.rb`, `test/lib/intake_test.rb`, `test/controllers/vc/unified_flagging_controller_test.rb`
Trap: `Intake.retrieve_all_for_year` defaults to `only_flagged: true`, hiding Prospectives with no adverse mark — assert on the count or empty state, not an unflagged person's absence.
Trap: `authorize_role` (`app/helpers/authorize_helper.rb`) sets a class attribute, so a second call replaces the Admin/Intake gate; the tree gate stacks only as the base controller's `authorize_training_view` before_action.

### Training › Surveys
Reach it: `GET /training/:slug/surveys` → <training> › Reports › Surveys; report `GET /training/:slug/surveys/:survey_id/reports/:report_id`; per-trainer `GET /training/:slug/surveys/:survey_id/trainers/:person_id`; from survey management via `survey_feedback_path` (`app/helpers/communication/surveys_helper.rb`)
Gate: `Training.view_roles` AND, for the index, `Training.survey_management_roles` (In-Person: `ADMIN`, `SURVEY_MANAGEMENT_TRAINING`; mapped ART: `ADMIN`, `SURVEY_MANAGEMENT_BASE | id`; otherwise `ADMIN`); report and per-trainer pages: `authorize_survey_report` (`Survey#can_manage_survey?`, or `is_trainer_for_survey?` for non-trainer-type surveys) (menu: `survey_management_roles` only)
Controller: `app/controllers/training/surveys_controller.rb` (`index`), `app/controllers/concerns/survey_reporting_concern.rb` (`report`, `trainer`, html + csv)
Owner: `SurveyReportingConcern` (`app/controllers/concerns/survey_reporting_concern.rb`), `SurveyBuilder` (`app/lib/survey_builder.rb`), `Survey` (`app/models/survey.rb`)
Touches: `survey`, `survey_group`, `survey_question`, `survey_answer`, `slot`, `position`, `person`, `person_photo`
Verify: `test/controllers/training/surveys_controller_test.rb`, `test/controllers/mentoring/surveys_controller_test.rb`, `test/controllers/communication/surveys_controller_test.rb`, `test/lib/training_test.rb` (the mentor and mentee readers)
Trap: The Mentor Surveys and Mentee Surveys sections, and which surveys a slug admits, come from `Training.survey_position_ids`: the positions flagged `is_art_mentor` / `is_art_mentee` on the team of a training flagged `has_art_mentoring` — found by team, never by `training_position_id` (ruled 2026-10-21; that link also gates sign-in on the ART). A test that builds those positions without a team and the flags gets only Training Surveys; `SurveyTestHelper#setup_survey_positions` sets them.
Trap: `SurveyBuilder` returns a `variance`, not a standard deviation — pass a "Std Dev" column through `SurveyReportHelper#survey_std_dev`.
Trap: A `summarize_rating` question reports via `report.summarized_ratings`, not `trainer.questions` — per-trainer totals must count both, as `count_trainer_ratings` does, or the roster reads 0 next to a ranked table.

## Mentoring: prospectives & alphas

Every page uses `layout "mentoring"` behind `authorize_role [Role::ADMIN, Role::MENTOR]`; the four roster pages include `UnifiedFlaggingConcern` for the lazy `detail` frame (not `MentoringConcern`, which backs Me › Mentoring and Person › Mentoring). Only Post Season Summary (floor 2008) and Mentor Shift Report (floor 2010) read `?year=`, Alpha Surveys lists every year, and the rest override `setup_year` to pin `Current.year`.

### Potential Alphas
Reach it: `GET /mentoring/potential-alphas` → Mentoring › Pre-Event › Potential Alphas; `?person=:id` fills the review pane (`unified_flagging_path` drops `:year`: the roster is current standing); detail `GET /mentoring/potential-alphas/:person_id`
Gate: `ADMIN`, `MENTOR`; note writes re-checked per team by `Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE` (Mentor writes mentor notes only)
Controller: `app/controllers/mentoring/potential_alphas_controller.rb` (`index`, `detail` from `app/controllers/concerns/unified_flagging_concern.rb`); notes: `app/controllers/person/intake_notes_controller.rb` (origin `mentoring`)
Owner: `Intake.retrieve_current_potentials` (`app/lib/intake.rb`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`), `Mentoring::PotentialAlphasHelper` (`app/helpers/mentoring/potential_alphas_helper.rb`)
Touches: `person`, `person_fka`, `person_intake` (w), `person_intake_note` (w), `action_logs` (w), `person_mentor`, `person_slot`, `slot`, `trainee_status`, `trainee_note`, `person_status`, `timesheet`, `trainer_status`
Verify: `test/controllers/mentoring/potential_alphas_controller_test.rb`, `test/lib/intake_test.rb`, `test/controllers/person/intake_notes_controller_test.rb`
Trap: `setup_year` pins `Current.year` because `Intake.retrieve_current_potentials` lists today's Prospectives and Alphas — honouring `?year=` or adding a year selector clips ranks and notes to a past year.
Trap: The with-issues stat boxes count the unfiltered roster by `Mentoring::PotentialAlphasHelper::ISSUE_GROUPS` — never `summary[:flagged]`, which is true for a rank 3/4 in any earlier year and overcounts.

### Convert Prospectives
Reach it: `GET /mentoring/convert-prospectives` → Mentoring › Pre-Event › Convert Prospectives; convert `POST /mentoring/convert-prospectives`; detail `GET /mentoring/convert-prospectives/:person_id`
Gate: `ADMIN`, `MENTOR`; note writes re-checked per team by `Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE` (Mentor writes mentor notes only)
Controller: `app/controllers/mentoring/convert_prospectives_controller.rb` (`index`, `convert`, `detail` from `UnifiedFlaggingConcern`); notes: `app/controllers/person/intake_notes_controller.rb` (origin `mentoring_convert`)
Owner: `ProspectiveConversion` (`app/lib/prospective_conversion.rb`), `Intake.retrieve_trained_prospectives` (`app/lib/intake.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `action_logs` (w), `person_intake_note` (w), `person_intake` (w), `trainee_status`, `trainee_note`, `trainer_status`, `slot`, `person_slot`, `person_mentor`, `person_fka`, `timesheet`
Verify: `test/controllers/mentoring/convert_prospectives_controller_test.rb`, `test/lib/person_status_management_test.rb`, `test/controllers/person/intake_notes_controller_test.rb`
Trap: `convert` re-renders `:index` with 422 on purpose, keeping the just-converted Alphas via `Intake.retrieve_trained_prospectives(keep_ids:)` — a redirect loses them, as they are no longer Prospectives.
Trap: Person's `after_save :log_status_change` → `PersonStatusManagement.change` grants the Alpha position, not `ProspectiveConversion.convert` — tests must create `Position::ALPHA` (id 1, not in fixtures) or `PersonPosition`'s `belongs_to :position` fails.

### Alpha Status
Reach it: `GET /mentoring/alpha-status` → Mentoring › Pre-Event › Alpha Status; `?person=:id` fills the read-only review pane (`unified_flagging_path` drops `:year`); detail `GET /mentoring/alpha-status/:person_id`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_status_controller.rb` (`index`, `detail` from `UnifiedFlaggingConcern`; `unified_flagging_read_only?` is true)
Owner: `Intake.retrieve_year_class` + `Intake.became_alpha_ids` (`app/lib/intake.rb`), `Mentoring::AlphaStatusHelper` (`app/helpers/mentoring/alpha_status_helper.rb`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`)
Touches: `person_status`, `person`, `person_fka`, `person_intake`, `person_intake_note`, `person_mentor`, `person_slot`, `slot`, `trainee_status`, `trainee_note`, `timesheet`, `trainer_status`
Verify: `test/controllers/mentoring/alpha_status_controller_test.rb`, `test/lib/intake_test.rb`
Trap: `section_of` files "Became an Alpha" from `Intake.became_alpha_ids` (status audit trail) as well as current status — `person.status` alone puts a Shiny Penny (Alpha, then Active) under "Ready for Alpha status".
Trap: The roster is `Intake.retrieve_year_class` (entered the year's class, minus same-year washouts) — not interchangeable with `retrieve_current_potentials` (current status) or `retrieve_post_season_class` (keeps washouts).

### Mentor Shift Report
Reach it: `GET /mentoring/shift-report` → Mentoring › Scheduling › Shift Report; shift `?slot_id=`, on-duty mode `?on_duty=1`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/shift_report_controller.rb` (`index`)
Owner: `MentorShiftReport` (`app/lib/reports/mentor_shift_report.rb`; top-level, as `app/lib/reports` is an autoload root), `AlphaShiftRoster.shifts_for_year` (`app/lib/alpha_shift_roster.rb`)
Touches: `slot`, `person_slot`, `person`, `position`, `timesheet`, `person_mentor`
Verify: `test/controllers/mentoring/shift_report_controller_test.rb`, `test/lib/reports/mentor_shift_report_test.rb`, `test/lib/alpha_shift_roster_test.rb`
Trap: The viewed year only fills the shift picker — `MentorShiftReport.on_duty` reads the present year, and `load_slot_report` finds the slot in any year and runs `MentorShiftReport.for_slot` on its `begins_year`.
Trap: `MentorShiftReport::HOURS_PRIOR`/`HOURS_AFTER` (1h before, 3h after, active slots only) differ from `AlphaSignOut::HOURS_PRIOR`/`HOURS_AFTER` (1h before, 2h after) — don't unify them.

### Convert Alphas
Reach it: `GET /mentoring/alphas-convert` → Mentoring › Alpha Management › Convert Alphas (declared, not rendered; see Trap); convert `POST /mentoring/alphas-convert` with `target=active|bonked`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alphas_convert_controller.rb` (`index`, `convert`)
Owner: `AlphaConversion` (`app/lib/alpha_conversion.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person_mentor`, `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/mentoring/alphas_convert_controller_test.rb`, `test/lib/person_status_management_test.rb`, `test/lib/alpha_conversion_test.rb` (verdicts read Alpha rows only)
Trap: `Menus::MENTORING`'s "Alpha Management" (`app/lib/menus.rb`) lists its five pages under `sections:`, not `items:`, so `MenuBuilder.build_sections` drops them and the empty section — no sidebar, mega menu or other link reaches this page.
Trap: Disagreeing same-year `person_mentor` rows are settled by `PersonMentor.year_verdict` (`PersonMentor::VERDICT_PRECEDENCE`: bonk, self-bonk, pass, pending), here in `AlphaConversion.verdicts_for_year` and in `PersonMentor.retrieve_all_mentors_for_ids`, which every mentor history reads — `MIN(status)` and `order(:status).first` disagree on that ENUM and can mint a self-bonked Alpha.

### Alpha Sign-Out
Reach it: `GET /mentoring/alpha-signout` → Mentoring › Alpha Management › Alpha Sign-Out (declared, not rendered; see Trap); shift `?slot_id=`, every Alpha on duty `?on_duty=1`; sign out `POST /mentoring/alpha-signout`
Gate: `ADMIN`, `MENTOR`; the POST also needs `SHIFT_MANAGEMENT` or `TIMESHEET_MANAGEMENT` (ADMIN passes) via `authorize_ability :sign_out_alphas`; the view hides the button with `can?(:sign_out_alphas)`
Controller: `app/controllers/mentoring/alpha_signout_controller.rb` (`index`, `sign_out`)
Owner: `AlphaSignOut` (`app/lib/alpha_sign_out.rb`), `ShiftManage.sign_off` (`app/lib/shift_manage.rb`), `AlphaShiftRoster.shifts_for_year` (`app/lib/alpha_shift_roster.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_pod` (w), `pod` (w), `person_event` (w), `person` (w), `action_logs` (w), `slot`, `person_slot`, `position`
Verify: `test/controllers/mentoring/alpha_signout_controller_test.rb`, `test/lib/shift_manage_test.rb`, `test/lib/alpha_shift_roster_test.rb`, `test/models/pod_test.rb`
Trap: Like Convert Alphas, this page sits under the "Alpha Management" `sections:` key in `app/lib/menus.rb`, which `MenuBuilder.build_sections` drops — no menu shows it and nothing links to it.
Trap: `AlphaSignOut.sign_out` calls `ShiftManage.sign_off` per entry, untransacted, re-checking `position_id: Position::ALPHA` and the open shift — not via `ShiftManageConcern#end_shift`, whose too-short-shift modal can't interrupt a bulk loop.

### Post Season Summary
Reach it: `GET /mentoring/post-season-summary` → Mentoring › Post Event › Post Season Summary; `?person=:id` fills the review pane (mentors and verdict live there, the Alpha-shift state on the line); detail `GET /mentoring/post-season-summary/:person_id`
Gate: `ADMIN`, `MENTOR`; note writes re-checked per team by `Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE` (Mentor writes mentor notes only)
Controller: `app/controllers/mentoring/post_season_summary_controller.rb` (`index`, `detail` from `UnifiedFlaggingConcern`); notes: `app/controllers/person/intake_notes_controller.rb` (origin `mentoring_post_season`)
Owner: `Intake.retrieve_post_season_class` (`app/lib/intake.rb`; not `retrieve_year_class`), `Mentoring::PostSeasonSummaryHelper` (`app/helpers/mentoring/post_season_summary_helper.rb`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`)
Touches: `person_status`, `person`, `person_fka`, `person_mentor`, `person_intake` (w), `person_intake_note` (w), `action_logs` (w), `person_slot`, `slot`, `trainee_status`, `trainee_note`, `timesheet`, `trainer_status`
Verify: `test/controllers/mentoring/post_season_summary_controller_test.rb`, `test/lib/intake_test.rb`, `test/controllers/person/intake_notes_controller_test.rb`
Trap: `section_of` flags on the viewed year's bonk or self-bonk (`summary[:bonk]`, re-pointed by `retrieve_post_season_class`), UBERBONKED status, or `mentor_rank >= Intake::BELOW_AVERAGE` — not the sibling pages' `Intake` severity groups.
Trap: The Walked and No Alpha sign-up tiles and the Alpha-shift filter read `post_season_signup_state` (mentors first), not `summary[:signed_up]` — a walk-up whose sign-up row is gone counts as walked, never as no sign-up.
Trap: The pane's extras (`PANE_EXTRAS`) are passed both by the page and by `render_review_pane` for the frame request; a new extra goes in the constant.
Trap: `unified_flagging_origin` sends its own `mentoring_post_season` token with `origin_year` (`Person::IntakeNotesController::ORIGIN_RETURNS`) — `mentoring` returns to current-status Potential Alphas, which lacks a past year's bonked mentee.

### Alpha Surveys
Reach it: `GET /mentoring/surveys` → Mentoring › Post Event › Alpha Surveys; report `GET /mentoring/surveys/:survey_id/reports/:report_id`; per-mentor `GET /mentoring/surveys/:survey_id/mentors/:person_id`
Gate: `ADMIN`, `MENTOR`, plus `Survey.can_manage_surveys?(person, Position::ALPHA)` (Admin, or the composed `SURVEY_MANAGEMENT_BASE | Position::ALPHA` role) via `authorize_survey_management` (index) and `authorize_survey_report` (reports) (menu: `ADMIN`, `MENTOR`)
Controller: `app/controllers/mentoring/surveys_controller.rb` (`index`; `report`, `trainer` from `app/controllers/concerns/survey_reporting_concern.rb`, HTML and CSV)
Owner: `SurveyReportingConcern` (`app/controllers/concerns/survey_reporting_concern.rb`), `SurveyBuilder` (`app/lib/survey_builder.rb`), `Survey` (`app/models/survey.rb`)
Touches: `survey`, `survey_group`, `survey_question`, `survey_answer`, `person`, `slot`, `position`
Verify: `test/controllers/mentoring/surveys_controller_test.rb`, `test/models/survey_test.rb`
Trap: `load_survey` admits only `type == Survey::ALPHA` and `position_id == Position::ALPHA` — keep both halves; they stop a training survey's id being read through this Mentor-level page.
Trap: `SurveyReportingConcern`'s `included` block registers `load_survey` → `authorize_survey_report` → `load_report_links` → `load_slots` in order — define the first two as methods, never redeclare any as a before_action (it re-appends last).

## Mentoring: the alpha shift

`authorize_role [Role::ADMIN, Role::MENTOR]` sits on both `Base` controllers, Acceptance Sheets and Mentor Assignments. Alpha Schedule (`year_floor` 2008) and Alpha Pods (2023) read the year via `setup_year`, but `load_slot` finds an Alpha slot of any year; Sheets and Assignments pin the present year. `Menus::MENTORING` nests "Alpha Management" under `sections:`, not `items:`, so `MenuBuilder.build_sections` drops it and no menu links Sheets, Assignments or Pods.

### Alpha Schedule
Reach it: `GET /mentoring/alpha-schedule` → Mentoring › Scheduling › Alpha Schedule; shift `GET /mentoring/alpha-schedule/:slot_id`; sheets `GET /mentoring/alpha-schedule/:slot_id/signup-sheet`, `GET /mentoring/alpha-schedule/:slot_id/info-sheet`, `GET /mentoring/alpha-schedule/:slot_id/apparel`; dialog `GET /mentoring/alpha-schedule/:slot_id/no-alphas`
Gate: `ADMIN`, `MENTOR`; `require_signed_in_alphas` redirects `info_sheet` and `apparel` to the shift page until someone is signed in
Controller: `app/controllers/mentoring/alpha_schedule_controller.rb` (`index`, `show`, `no_alphas`, `signup_sheet`, `info_sheet`, `apparel`), base `app/controllers/mentoring/alpha_schedule/base_controller.rb` (gate, `setup_year`, `load_slot`)
Owner: `AlphaShiftRoster` (`app/lib/alpha_shift_roster.rb`), `ShirtTotals` (`app/lib/shirt_totals.rb`)
Touches: `slot`, `person_slot`, `person`, `timesheet`, `person_intake`, `person_intake_note`, `person_mentor`, `trainee_status`, `person_status`, `trainee_note`, `swag`
Verify: `test/controllers/mentoring/alpha_schedule_controller_test.rb`, `test/lib/alpha_shift_roster_test.rb`, `test/lib/shirt_totals_test.rb`
Trap: `AlphaShiftRoster` takes signed-in from `Timesheet.retrieve_signed_in_people(Position::ALPHA)` (any slot, any year), so an Alpha on two shifts counts as signed in on both — match `timesheet.slot_id` for an exact shift.
Trap: `AlphaShiftRoster.for_slot` caps intake, notes and training history, and reads mentor status, at `slot.begins_year` (not `@year` or `Current.year`) — pass the slot, never the viewed year.

### Alpha Schedule › Add Person (shift roster)
Reach it: `GET /mentoring/alpha-schedule/:slot_id/people/new` → Alpha Schedule shift page › Add Person; add `POST /mentoring/alpha-schedule/:slot_id/people`; remove `DELETE /mentoring/alpha-schedule/:slot_id/people/:person_id`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_schedule/rosters_controller.rb` (`new`, `create`, `destroy`), base `app/controllers/mentoring/alpha_schedule/base_controller.rb`
Owner: `Scheduling::Signup` (`app/lib/scheduling/signup.rb`), `AlphaShiftRoster.addable?` (`app/lib/alpha_shift_roster.rb`), `PersonSearch` (`app/lib/person_search.rb`)
Touches: `person_slot` (w), `slot` (w), `action_logs` (w), `person` (w), `person_fka`, `email_history`, `person_position`
Verify: `test/controllers/mentoring/alpha_schedule/rosters_controller_test.rb`, `test/lib/scheduling/signup_characterization_test.rb`
Trap: `create` runs `AlphaShiftRoster.addable?` (`Person::ALPHA`/`Person::PROSPECTIVE` only) before `Scheduling::Signup.add`, so `force=1` cannot bypass it — keep eligibility rules out of the force path.
Trap: `destroy` always calls `Scheduling::Signup.remove(person, @slot, true)` so mentors can edit a started shift's roster (test-pinned) — do not "correct" `want_to_force` to `false`.

### Alpha Pod Management
Reach it: `GET /mentoring/alpha-pods` → Mentoring › Alpha Management › Alpha Pods (not rendered, see intro); board `GET /mentoring/alpha-pods/:slot_id`; print `GET /mentoring/alpha-pods/:slot_id/print`; add pod `POST /mentoring/alpha-pods/:slot_id/pods`; delete `DELETE /mentoring/alpha-pods/:slot_id/pods/:id`; reorder `PATCH /mentoring/alpha-pods/:slot_id/pods/:id/move`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_pods_controller.rb` (`index`, `show`, `print_sheet`), `app/controllers/mentoring/alpha_pods/pods_controller.rb` (`create`, `destroy`, `move`), base `app/controllers/mentoring/alpha_pods/base_controller.rb` (gate, `load_slot`, `render_board`, `render_refusal`)
Owner: `AlphaPodBoard` (`app/lib/alpha_pod_board.rb`), `Pod` (`app/models/pod.rb`: `create_alpha_set!`, `destroy_set!`, `move!`) (not `CruiseDirectionBoard`: its `shift` pods share the table)
Touches: `pod` (w), `person_pod` (w), `action_logs` (w), `slot`, `person_slot`, `timesheet`, `person`, `person_mentor`
Verify: `test/controllers/mentoring/alpha_pods_controller_test.rb`, `test/models/pod_test.rb`
Trap: `pod.type` is a domain column (`inheritance_column = nil`) shared with Cruise Direction `shift` pods — scope via `Pod.for_slot(...).of_type(...)` or `Pod::ALPHA_SET_TYPES`; name pods by `Pod#number` (alpha and mitten pods keep `sort_index` 1).
Trap: `AlphaPodBoard.unassigned_alphas` is every signed-in Alpha (`Timesheet.retrieve_signed_in_people`, any slot or year) minus this slot's alpha-pod members, so another shift's board lists walking Alphas as unassigned.

### Alpha Pod Management › Pod members
Reach it: `GET /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/new` → Alpha Pod Management board › pod card › Add; add `POST /mentoring/alpha-pods/:slot_id/pods/:pod_id/people`; edit `GET /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/:person_id/edit`; update `PATCH /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/:person_id`; remove `DELETE /mentoring/alpha-pods/:slot_id/pods/:pod_id/people/:person_id`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_pods/people_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`), base `app/controllers/mentoring/alpha_pods/base_controller.rb` (`render_board`, `render_refusal`)
Owner: `Pod` (`app/models/pod.rb`: `add_person!`, `remove_person!`, `relocate_person!`, `move_person!`), `AlphaPodBoard.pools_for` (`app/lib/alpha_pod_board.rb`), `PersonPod` (`app/models/person_pod.rb`)
Touches: `person_pod` (w), `pod` (w), `action_logs` (w), `person`, `timesheet`, `position`, `person_position`, `person_mentor`, `slot`
Verify: `test/controllers/mentoring/alpha_pods_controller_test.rb`, `test/models/pod_test.rb`
Trap: Only `removed_at` (set by `Pod#remove_person!`, no delete) ends a membership (`PersonPod.current`, `Pod#current_members`); `Pod.shift_ended` (every sign-out, via `Timesheet#handle_shift_end`) only stamps `left_at` — never filter on it.
Trap: A `new`/`edit` guard that redirects swaps in the layout's empty `modal` frame, showing nothing — use `render_refusal`, which renders `mentoring/alpha_pods/unavailable` on `turbo_frame_request?`.

### Alpha Acceptance Sheets
Reach it: `GET /mentoring/alpha-acceptance-sheets` → Mentoring › Alpha Management › Acceptance Sheets (not rendered, see intro); print `GET /mentoring/alpha-acceptance-sheets/print`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_acceptance_sheets_controller.rb` (`index`, `print_sheets`; shift/issues filters inline)
Owner: `AlphaAcceptanceSheets` (`app/lib/alpha_acceptance_sheets.rb`)
Touches: `person`, `person_photo`, `person_fka`, `person_intake`, `person_intake_note`, `person_slot`, `slot`, `trainee_status`, `person_status`, `trainee_note`, `person_mentor`
Verify: `test/controllers/mentoring/alpha_acceptance_sheets_controller_test.rb`, `test/lib/alpha_acceptance_sheets_test.rb`
Trap: `setup_year` is overridden to `@year = Current.year`, so `?year=` is ignored and the roster is whoever is Alpha now; the year scopes only the trained check, Alpha shift sign-ups and intake-note reach.
Trap: `Entry#trainings` is the whole Dirt training history, but `Entry#trained` (the `NOT_TRAINED` issue) needs a pass in a present-year session — never derive "trained" from `trainings`.

### Alpha Mentor Assignments
Reach it: `GET /mentoring/alpha-mentor-assignments` → Mentoring › Alpha Management › Mentor Assignments (not rendered, see intro; also linked from Convert Alphas); save `POST /mentoring/alpha-mentor-assignments`; pod fill `POST /mentoring/alpha-mentor-assignments/pod-prefill`; print `GET /mentoring/alpha-mentor-assignments/print`
Gate: `ADMIN`, `MENTOR`
Controller: `app/controllers/mentoring/alpha_mentor_assignments_controller.rb` (`index`, `save`, `pod_prefill`, `print_sheet`; filters and `submitted_rows` parsing inline)
Owner: `AlphaMentorAssignment` (`app/lib/alpha_mentor_assignment.rb`), `PersonMentor` (`app/models/person_mentor.rb`)
Touches: `person_mentor` (w), `action_logs` (w), `person`, `person_position`, `person_slot`, `slot`, `timesheet`, `pod`, `person_pod`
Verify: `test/controllers/mentoring/alpha_mentor_assignments_controller_test.rb`, `test/lib/alpha_mentor_assignment_test.rb`
Trap: `AlphaMentorAssignment.assign!` writes only present-year `person_mentor` rows, never `person.status` (Convert Alphas does); "pending" is mostly an absent row, so filter with `Entry#pending?`, not `person_mentor.status`.
Trap: `sync_row` destroys every stored row for the (person, year) that is not on the submitted sheet, so the `existing` scope in `assign!` must stay filtered to `position_id: Position::ALPHA` — `person_mentor` is shared by mentee position, and an unfiltered scope would delete another position's walk on save (`test/lib/alpha_mentor_assignment_test.rb` pins it).
Trap: A row's status is pre-filled from `PersonMentor.retrieve_all_mentors_for_ids`, which settles a year's disagreeing rows by `PersonMentor.year_verdict` (bonk over self-bonk over pass), and `sync_row` restates every one of that year's Alpha rows to the submitted status — so saving a disagreeing Alpha unchanged writes that verdict across the year, the one Convert Alphas acts on.
Trap: Pod members (`AlphaPodBoard::ON_DUTY_POSITIONS`) outside `mentor_pool`/`assignable_mentor_ids` (`Position::MENTOR` holders plus recorded mentors) get no `<option>` and silently vanish — copy via `pod_prefill` (narrows, reports `not_assignable`).
Trap: The database no longer refuses a second Alpha row for one mentor, mentee and year. The `person_id` key now ends in `person_mentor.timesheet_id`, which names the mentee's shift on an ART walk (UNIQUE: one mentor per shift) and is NULL on every Alpha row, and MariaDB never matches one NULL against another. `PersonMentor`'s uniqueness validation is the only guard, so a writer using `insert_all`, `update_all` or `save(validate: false)` must keep Alpha rows unique itself. The validation runs only when a row is new or its key changes: Rails cannot skip the query for an unchanged row whose scope holds a NULL, and an Alpha save restates every row's status. Rolling `20261021000002` back refuses while duplicate Alpha rows exist.

## Scheduling: slots & position credits

All five controllers use `layout "scheduling"` and `setup_year`: the year comes from `?year=`, and a missing, malformed or later year falls back to the present year. Slot pages are gated on `ADMIN` or `EDIT_SLOTS`, position credit pages on `ADMIN` alone.

### Slots
Reach it: `GET /scheduling/slots` → Scheduling › Scheduling Administration › Slots; drill-down `GET /scheduling/slots/position/:position_id`; form `GET /scheduling/slots/new`, `POST /scheduling/slots`, `GET /scheduling/slots/:id/edit`, `PATCH /scheduling/slots/:id`; delete `DELETE /scheduling/slots/:id` (edit form); repeat `POST /scheduling/slots/:id/repeat`; activate/deactivate all `POST /scheduling/slots/position/:position_id/active`; bulk delete `DELETE /scheduling/slots/position/:position_id/bulk-delete`; link fields `GET /scheduling/slots/link-options`
Gate: `ADMIN`, `EDIT_SLOTS`
Controller: `app/controllers/scheduling/slots_controller.rb` (`index`, `position`, `new`, `create`, `edit`, `update`, `destroy`, `repeat`, `bulk_destroy`, `set_active_all`, `link_options`), `app/controllers/concerns/position_lookup_concern.rb`, `app/javascript/controllers/link_options_controller.js`
Owner: `Slot` (`app/models/slot.rb`), `Scheduling::SlotsHelper` (`app/helpers/scheduling/slots_helper.rb`); filters, repeat, save-as-new (`CLONE_ATTRS`) inline in controller
Touches: `slot` (w), `position`, `position_credit`, `event_dates`, `person_slot` (w), `trainer_status` (w), `trainee_status` (w), `person` (w), `action_logs` (w)
Verify: `test/controllers/scheduling/slots_controller_test.rb`, `test/models/role_cache_invalidation_test.rb`
Trap: `update_all` skips Slot's `after_commit :purge_training_role_caches` (only on `active`/`begins_year`/`position_id` changes) — bulk writes must call `Slot.purge_training_role_caches(ids)`, as `set_active_all` does, or RoleManager goes stale.
Trap: `setup_year` maps later years to the present, so a next-year slot saves (`compute_time_fields` sets `begins_year` from `begins`) but the `slot_position_path` redirect to `year: slot.begins_year` shows a list without it until the year rolls over.

### Copy Slots
Reach it: `GET /scheduling/slots/copy` → Slots (Copy Slots), position's slots page (Bulk Copy); preview/commit `POST /scheduling/slots/copy` (`preview` re-renders only)
Gate: `ADMIN`, `EDIT_SLOTS`
Controller: `app/controllers/scheduling/slot_copies_controller.rb` (`new`, `create`)
Owner: `Scheduling::SlotCopier` (`app/lib/scheduling/slot_copier.rb`); `filter[...]` narrowing inline in controller
Touches: `slot` (w), `position`
Verify: `test/controllers/scheduling/slot_copies_controller_test.rb`
Trap: `SlotCopier.default_delta_days` shifts the viewed year's Labor Day to `Current.year`'s, so copying while viewing the present year shifts 0 days, duplicating the slots in place — the page only warns.
Trap: `SlotCopier.copyable_slots` drops slots with a nonzero `training_id`, a `trainer_slot_id` or a `trainee_slot_id` even when posted, and `COPY_ATTRS` never carries trainer or parent links to the copies.

### Bulk Edit Slots
Reach it: `GET /scheduling/slots/position/:position_id/bulk-edit` → position's slots page (Bulk Edit); commit `POST /scheduling/slots/position/:position_id/bulk-edit`
Gate: `ADMIN`, `EDIT_SLOTS`
Controller: `app/controllers/scheduling/slot_bulk_edits_controller.rb` (`new`, `create`), `app/controllers/concerns/position_lookup_concern.rb`
Owner: `Slot` (`app/models/slot.rb`); inline in controller: `Slot#update!` per selected slot, one transaction
Touches: `slot` (w), `position`, `trainee_status`, `trainer_status`
Verify: `test/controllers/scheduling/slot_bulk_edits_controller_test.rb`
Trap: `column_params` drops blank fields (`compact_blank`), so bulk edit can set but never clear description or Additional Information (`url`) — clear `url` per slot on the edit form, where description is required.

### Position Credits
Reach it: `GET /scheduling/position-credits` → Scheduling › Scheduling Administration › Position Credits; drill-down `GET /scheduling/position-credits/position/:position_id` (both also `.csv`); form `GET /scheduling/position-credits/new`, `POST /scheduling/position-credits`, `GET /scheduling/position-credits/:id/edit`, `PATCH /scheduling/position-credits/:id`; delete `DELETE /scheduling/position-credits/:id`; bulk delete `DELETE /scheduling/position-credits/position/:position_id/bulk-delete`
Gate: `ADMIN`
Controller: `app/controllers/scheduling/position_credits_controller.rb` (`index`, `position`, `new`, `create`, `edit`, `update`, `destroy`, `bulk_destroy`), `app/controllers/concerns/csv_export_concern.rb`
Owner: `PositionCredit` (`app/models/position_credit.rb`), `Scheduling::PositionCreditsHelper` (`app/helpers/scheduling/position_credits_helper.rb`)
Touches: `position_credit` (w), `position`
Verify: `test/controllers/scheduling/position_credits_controller_test.rb`, `test/models/position_credit_test.rb`
Trap: `PositionCredit.compute_credits` (behind `#credits` on `Timesheet`, `TimesheetMissing`, `Slot`) caches per year until `after_commit :flush_year_caches` — after `update_all`/`delete_all`/`insert_all`, call `PositionCredit.flush_year_cache(year)` per year.
Trap: `start_year`/`end_year` are MariaDB generated columns (`db/schema.rb`) Rails never reloads after save, so a just-saved credit has nil or the old year — read `start_time.year`, as `credit_position_path` and `flush_year_caches` do.

### Credit Timeline
Reach it: `GET /scheduling/position-credits/position/:position_id/timeline` (also `.csv`) → position's credits page (Credit Timeline)
Gate: `ADMIN`
Controller: `app/controllers/scheduling/position_credits_controller.rb` (`timeline`)
Owner: `Scheduling::CreditTimeline` (`app/lib/scheduling/credit_timeline.rb`), `Scheduling::PositionCreditsHelper#credit_timeline_chart` (`app/helpers/scheduling/position_credits_helper.rb`)
Touches: `position_credit`, `position`
Verify: `test/lib/scheduling/credit_timeline_test.rb`, `test/controllers/scheduling/position_credits_controller_test.rb`
Trap: `timeline` charts by `start_year` (`PositionCredit.for_year`), but `compute_credits` misses load `PositionCredit.find_for_year_position` → `for_year_position`, also by `end_year`: a credit past New Year may earn nothing unless `warm_bulk_year_cache` ran first.

### Copy Position Credits
Reach it: `GET /scheduling/position-credits/copy` → Position Credits (Copy Position Credits), position's credits page (Bulk Copy); preview/commit `POST /scheduling/position-credits/copy` (`preview` re-renders only)
Gate: `ADMIN`
Controller: `app/controllers/scheduling/position_credit_copies_controller.rb` (`new`, `create`)
Owner: `Scheduling::PositionCreditCopier` (`app/lib/scheduling/position_credit_copier.rb`), `Scheduling::SlotCopier` (`app/lib/scheduling/slot_copier.rb`, Labor Day shift, `adjust_time`)
Touches: `position_credit` (w), `position`
Verify: `test/controllers/scheduling/position_credit_copies_controller_test.rb`
Trap: `PositionCreditCopier.copy` never dedupes and `SlotCopier.default_delta_days` is 0 when viewing the present year, so copying then, or twice, stacks credits `PositionCredit.credits_for` sums (double rate) — the page only warns for the present year.

## Scheduling: reports

Each page is a read-only `ApplicationController` subclass in `app/controllers/scheduling/` with `layout "scheduling"`, one `authorize_role` and `before_action :setup_year` (`?year=` if from the controller's `year_floor` to the present year, else the present year). Top-level classes in `app/lib/reports/` hold the logic (own autoload root: `FlakeReport`, not `Reports::FlakeReport`). Person links use `LinkHelper#can_view_person_page?`, since some readers lack `PersonConcern::VIEW_ROLES`.

### Shift Lead Report
Reach it: `GET /scheduling/shift-lead` → Scheduling › Forecast Reports › Shift Lead Report; live `GET /scheduling/shift-lead?mode=on-duty`; print `GET /scheduling/shift-lead/print`
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/shift_lead_controller.rb` (`index`, `print_sheet`; filters and sorts inline)
Owner: `ShiftLeadReport` (`app/lib/reports/shift_lead_report.rb`), `OnDutyShiftLeadReport` (`app/lib/reports/on_duty_shift_lead_report.rb`), `Slot.retrieve_dirt_times` (`app/models/slot.rb`)
Touches: `slot`, `person_slot`, `person`, `position`, `person_position`, `certification`, `person_certification`, `person_event`, `trainee_status`, `trainer_status`, `timesheet`
Verify: `test/controllers/scheduling/shift_lead_controller_test.rb`, `test/lib/reports/shift_lead_report_test.rb`, `test/lib/reports/on_duty_shift_lead_report_test.rb`, `test/lib/scheduling_menu_test.rb`, `test/lib/summarize_gender_test.rb`
Trap: `?year=` only fills the shift picker — `?mode=on-duty` runs `OnDutyShiftLeadReport.execute` at `Current.time`, and the scheduled report takes its year from the picked slot's `begins`, not `@year`.
Trap: `ShiftLeadReport.below_min_for` (short-staffed list) compares the denormalized `slot.signed_up` counter with `slot.min`, not `person_slot` rows — a test creating `PersonSlot` rows must also set `signed_up`.

### Schedule by Callsign
Reach it: `GET /scheduling/schedule-by-callsign` → Scheduling › Forecast Reports › Schedule by Callsign; person `GET /scheduling/schedule-by-callsign/person/:person_id` (both also `.csv`)
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`; `person` also bounces readers outside `PersonConcern::VIEW_ROLES` when the person has no sign-ups that year (`hidden_person_redirect`)
Controller: `app/controllers/scheduling/schedule_by_callsign_controller.rb` (`index`, `person`)
Owner: `ScheduleByCallsignReport` (`app/lib/reports/schedule_by_callsign_report.rb`)
Touches: `person_slot`, `slot`, `person`, `position`
Verify: `test/controllers/scheduling/schedule_by_callsign_controller_test.rb`, `test/lib/scheduling_menu_test.rb`
Trap: `hidden_person_redirect` answers an empty year with the unknown-id "could not be found" wording so Edit Slots cannot confirm an account exists — do not "simplify" it into an empty state.
Trap: The `MIN(slot.begins)`/`MAX(slot.ends)` plucks arrive in the host zone — keep `.in_time_zone`; both exports write `iso8601` in `Time.zone`, not `getlocal` like No Shows/Shift Drop, so page and CSV agree near midnight.

### Schedule by Position
Reach it: `GET /scheduling/schedule-by-position` → Scheduling › Forecast Reports › Schedule by Position; position `GET /scheduling/schedule-by-position/position/:position_id` (also `.csv`)
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/schedule_by_position_controller.rb` (`index`, `position`), `PositionLookupConcern`
Owner: `ScheduleByPositionReport` (`app/lib/reports/schedule_by_position_report.rb`), `PositionLineup.retrieve_associated_positions` (`app/models/position_lineup.rb`)
Touches: `slot`, `person_slot`, `person`, `position`, `position_lineup_member`
Verify: `test/controllers/scheduling/schedule_by_position_controller_test.rb`
Trap: The index counts switched-off shifts but `Detail#empty_shift_count` skips them and counts a shift covered when its sub-shift (child slot) has sign-ups — differing from Shift Sign-Ups by design; don't reconcile them.

### Shift Coverage
Reach it: `GET /scheduling/shift-coverage` → Scheduling › Forecast Reports › Shift Coverage (`?type=` shift type, `?day=`, also `.csv`)
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/shift_coverage_controller.rb` (`index`)
Owner: `ShiftCoverageReport` (`app/lib/reports/shift_coverage_report.rb`), `Scheduling::ShiftCoverageHelper` (`app/helpers/scheduling/shift_coverage_helper.rb`); the shift types and posts it reads are `ShiftCoverageGroup` (`app/models/shift_coverage_group.rb`) and `ShiftCoveragePosition` (`app/models/shift_coverage_position.rb`) rows
Touches: `slot`, `person_slot`, `person`, `shift_coverage_group`, `shift_coverage_position`
Verify: `test/controllers/scheduling/shift_coverage_controller_test.rb`, `test/models/shift_coverage_group_test.rb`, `test/models/shift_coverage_position_test.rb`
Trap: Rows come only from the shift type's `base_position_ids` shifts, rounded to the nearest hour (`round_to_hour`); shift types and their posts (columns) are `shift_coverage_group`/`shift_coverage_position` rows in `sort_index` order, and `ShiftCoverageReport.type_for` turns a slug into one: an unknown or non-String `?type=` silently becomes `command`, or the first shift type when no row is slugged `command`, and with none set up the page says so and the export is a header row. A shift type with no posts yet reads as an empty report too ("<Title> has no posts set up yet.", no grid, no export link). `set_type` reads the shift types once and builds the Shift Type menu (`@type_options`) from the same rows. The controller's `@type` is the slug `type_for` answered with, not the one asked for.
Trap: `period_bounds` and `shift_scope` read `Slot.for_year` without `active`, so switched-off shifts still draw rows and fill cells — unlike the HQ forecast and Shift Sign-Ups (`Slot.active`).

### Shift Sign-Ups
Reach it: `GET /scheduling/shift-signups` → Scheduling › Forecast Reports › Shift Sign-Ups; position `GET /scheduling/shift-signups/position/:position_id` (both also `.csv`)
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/shift_signups_controller.rb` (`index`, `position`), `PositionLookupConcern`
Owner: `ShiftSignupsReport` (`app/lib/reports/shift_signups_report.rb`)
Touches: `slot`, `person_slot`, `position`
Verify: `test/controllers/scheduling/shift_signups_controller_test.rb`
Trap: Sign-ups count `person_slot` rows on `Slot.active` shifts, never `slot.signed_up` (only `Scheduling::Signup` keeps it current); `Shift#empty?` ignores a staffed sub-shift, unlike `empty_shift_count`.
Trap: `Fill` divides by raw `slot.max` (not `Scheduling::SlotCapacity#effective_max`); a `max` of 0 (no limit) adds no seats but its sign-ups count, so a position can top 100% — do not clamp it.

### HQ Check In/Out Forecast (hq forecast)
Reach it: `GET /scheduling/hq-forecast` → Scheduling › Forecast Reports › HQ Check In/Out Forecast (also `.csv`); burn perimeters `GET /scheduling/hq-forecast/burn-perimeters`; dialogs `GET /scheduling/hq-forecast/people`, `GET /scheduling/hq-forecast/shifts/:slot_id`
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/hq_forecast_controller.rb` (`index`, `burn_perimeters`, `people`, `shift`)
Owner: `HqForecastReport` (`app/lib/reports/hq_forecast_report.rb`), `Scheduling::HqForecastHelper` (`app/helpers/scheduling/hq_forecast_helper.rb`)
Touches: `slot`, `person_slot`, `person`
Verify: `test/controllers/scheduling/hq_forecast_controller_test.rb`, `test/lib/reports/hq_forecast_report_test.rb`, `test/lib/scheduling_menu_test.rb`
Trap: `floor_to` cuts periods on a Unix-epoch grid (`time.to_i % seconds`), not from local midnight, so 180- and 360-minute periods start on offset hours.
Trap: Traffic excludes HQ's own desks, `TRAINING_POSITION_IDS` and shifts not wholly inside HQ hours; a period is "unstaffed" only when `hq_open` (an HQ shift is scheduled) and no lead, short or window is on (`COVERAGE_KEYS`; runners never count).

### Sandman Qualifications (sandman qualified)
Reach it: `GET /scheduling/sandman-qualified` → Scheduling › Forecast Reports › Sandman Qualifications (`?show=` filter, also `.csv`)
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/sandman_qualified_controller.rb` (`index`)
Owner: `SandmanQualifiedReport` (`app/lib/reports/sandman_qualified_report.rb`)
Touches: `person`, `person_position`, `setting`, `slot`, `trainee_status`, `trainer_status`, `person_event`, `timesheet`, `person_slot`
Verify: `test/controllers/scheduling/sandman_qualified_controller_test.rb`, `test/lib/scheduling_menu_test.rb`
Trap: A blank `SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS` reads as 0 via `Setting.get_value`, so the experience check stays on (viewed year as cutoff); affidavit/experience rules mirror `SignInBlocker` (`app/lib/sign_in_blocker.rb`) — change both.
Trap: `sandpeople` is today's `Person::ACTIVE` Sandman-position holders, so an earlier year shows today's sandmen against that year's training, affidavit and sign-ups.

### Early Arrivals
Reach it: `GET /scheduling/early-arrivals` → Scheduling › Forecast Reports › Early Arrivals (filters `?sap=`, `?arrival=`, `?shift=`, `?shift_date=`, `?agreement=`, `?site=`; also `.csv`)
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/scheduling/early_arrivals_controller.rb` (`index`; filtering inline)
Owner: `EarlyArrivalReport` (`app/lib/reports/early_arrival_report.rb`), `AccessDocument.retrieve_saps_prior_to` (`app/models/access_document.rb`), `Scheduling::EarlyArrivalsHelper` (`app/helpers/scheduling/early_arrivals_helper.rb`)
Touches: `event_dates`, `access_document`, `person_slot`, `slot`, `position`, `person`, `bmid`, `provision`, `person_asset`, `asset`, `person_event`
Verify: `test/controllers/scheduling/early_arrivals_controller_test.rb`
Trap: Passes (`access_document`), radios (`provision`) and `person.on_site` load only when `live = (year == Current.year)`; earlier years use shifts alone and ignore `sap`/`arrival`/`site`; no `event_dates` row shows a callout and the CSV redirects.
Trap: On an earlier year the "No pre-event shift" box is always 0 and the "Has none" filter empty, yet neither is gated by `live?` (owner ruling 2026-10-02) — do not hide them.

### Flake Report
Reach it: `GET /scheduling/flake-report` → Scheduling › Shift Change Reports › Flake Report; position `GET /scheduling/flake-report/position/:position_id`
Gate: `ADMIN`, `EDIT_SLOTS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/flake_report_controller.rb` (`index`, `position`), `PositionLookupConcern`
Owner: `FlakeReport` (`app/lib/reports/flake_report.rb`), `ShiftAttendance` (`app/lib/reports/shift_attendance.rb`)
Touches: `slot`, `position`, `person_slot`, `timesheet`, `person`
Verify: `test/controllers/scheduling/flake_report_controller_test.rb`, `test/lib/reports/flake_report_test.rb`
Trap: The "did they ranger it" rule (`scanned_slots`, `without_honored_shifts`, `covers?`, 14-day `MAX_SHIFT_LOOKBACK`) lives in shared `ShiftAttendance` — edit there; `scanned_slots` keeps begun active shifts minus training and `not_timesheet_eligible` positions.
Trap: `FlakeReport.summary` counts rogue timesheet rows, not (slot, person) pairs, as the drill-down lists every row — deduping makes the index badge disagree with the page.

### Shift Drop Report
Reach it: `GET /scheduling/shift-drop` → Scheduling › Shift Change Reports › Shift Drop Report (`?hours=` window, also `.csv`); position `GET /scheduling/shift-drop/position/:position_id`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/shift_drop_report_controller.rb` (`index`, `position`), `PositionLookupConcern`
Owner: `ShiftDropReport` (`app/lib/reports/shift_drop_report.rb`), `ActionLog.slot_id_from_data` (`app/models/action_log.rb`)
Touches: `slot`, `action_logs`, `position`, `person`
Verify: `test/controllers/scheduling/shift_drop_report_controller_test.rb`, `test/lib/reports/shift_drop_report_test.rb`
Trap: A drop is a `person-slot-remove` `action_logs` row (the `person_slot` is gone), matched to its shift via `ActionLog.slot_id_from_data`, which coerces Laravel's String slot ids — never match `data["slot_id"]` raw.
Trap: `year_slots` (`Slot.for_year(year).active`, no `begins <= now` bound) includes unstarted shifts, unlike Flake/No Shows; `@hours` must ride every link via `@index_params` or drill-downs fall back to 12 hours.

### No Shows Report
Reach it: `GET /scheduling/no-shows-report` → Scheduling › Shift Change Reports › No Shows Report; position `GET /scheduling/no-shows-report/position/:position_id` (also `.csv`)
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/no_shows_report_controller.rb` (`index`, `position`), `PositionLookupConcern`
Owner: `NoShowReport` (`app/lib/reports/no_show_report.rb`), `ShiftAttendance` (`app/lib/reports/shift_attendance.rb`)
Touches: `slot`, `position`, `person_slot`, `timesheet`, `person`
Verify: `test/controllers/scheduling/no_shows_report_controller_test.rb`
Trap: Every flake is a no-show, not the reverse: `FlakeReport` first excuses sign-ups whose timesheet names the slot, `NoShowReport` runs `without_honored_shifts` over all — so a linked timesheet outside the shift's hours is a no-show only, by design.
Trap: The position CSV writes `slot.begins.getlocal.iso8601` (host zone, like Shift Drop); Schedule by Callsign/Position and Shift Sign-Ups use `iso8601` in `Time.zone` — read each export's comment and tests before copying either way.

### Event Statistics (event stats)
Reach it: `GET /scheduling/event-stats` → Scheduling › Event Reports › Event Statistics
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/scheduling/event_stats_controller.rb` (`index`)
Owner: `EventStatsReport` (`app/lib/reports/event_stats_report.rb`)
Touches: `timesheet`, `position`, `person_slot`, `slot`, `person_mentor`, `person_status`, `trainee_status`, `trainer_status`, `person`
Verify: `test/controllers/scheduling/event_stats_controller_test.rb`, `test/lib/reports/event_stats_report_test.rb`, `test/lib/scheduling_menu_test.rb`
Trap: Type filters use `NON_TRAINING_TYPES` (includes `nil`), not `where.not(type: Position::TYPE_TRAINING)`, which drops untyped positions; `signup_scope` counts switched-off slots while training rows count only `active` session slots.
Trap: The on-site count reads live `person.on_site` only when `year == Current.year`; earlier years get `nil`, not 0.

## Shift Operations

Pages live under `/shift-operations` in the `shift_operations` layout (except ROC Photo Board), each with one `authorize_role` that must equal its menu item's `visible_if` (`test/lib/shift_operations_menu_test.rb`) — change both, and never put a category-level `visible_if` back on `Menus::SHIFT_OPERATIONS`. Only Cruise Direction and Missing Paycom Employee IDs read a viewed year (`setup_year`, `year_floor = 2023`); the rest act on now or typed dates.

### Bulk Sign In/Out
Reach it: `GET /shift-operations/bulk-sign-in-out` → Shift Operations › Shift Operations Menu › Bulk Sign In/Out; preview `POST /shift-operations/bulk-sign-in-out/preview`; back to form `POST /shift-operations/bulk-sign-in-out/edit`; apply `POST /shift-operations/bulk-sign-in-out`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/shift_operations/bulk_sign_in_out_controller.rb` (`index`, `preview`, `apply`)
Owner: `BulkSignInOut` (`app/lib/bulk_sign_in_out.rb`), `ShiftManage.convert_inactive_to_active` (`app/lib/shift_manage.rb`) (not the `BulkUploadPage` concern)
Touches: `timesheet` (w), `timesheet_log` (w), `action_logs` (w), `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_pod` (w), `pod` (w), `position`, `slot`, `person_slot`
Verify: `test/controllers/shift_operations/bulk_sign_in_out_controller_test.rb`, `test/lib/bulk_sign_in_out_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `BulkSignInOut.persist_entry` skips `TimesheetManagement.unconfirm_timesheet` (unlike `ShiftManage.sign_in`/`sign_off`/`resignin`) yet runs `ShiftManage.convert_inactive_to_active` on `:out` lines — both on purpose; don't align with the HQ window.
Trap: `BulkSignInOut.process` is all-or-nothing (`ActiveRecord::Rollback`, unlike bulk uploads) and feeds `ActionLog.record` `Entry#to_log`, which drops `:person` — `entries.map(&:to_h)` would dump whole `person` rows into `action_logs.data`.

### Cruise Direction
Reach it: `GET /shift-operations/cruise-direction` → Shift Operations › Shift Operations Menu › Cruise Direction; new pod `GET /shift-operations/cruise-direction/pods/new` + `POST /shift-operations/cruise-direction/pods`; drag `PATCH /shift-operations/cruise-direction/pods/:id/position`; add people `GET /shift-operations/cruise-direction/pods/:pod_id/people/new` + `POST /shift-operations/cruise-direction/pods/:pod_id/people`; move `PATCH /shift-operations/cruise-direction/pods/:pod_id/people/:person_id`; take out `DELETE /shift-operations/cruise-direction/pods/:pod_id/people/:person_id`; change pod `GET /shift-operations/cruise-direction/pods/:id/edit` + `PATCH /shift-operations/cruise-direction/pods/:id`; delete pod `DELETE /shift-operations/cruise-direction/pods/:id`
Gate: `ADMIN`, `POD_MANAGEMENT`
Controller: `app/controllers/shift_operations/cruise_direction_controller.rb` (`index`), `app/controllers/shift_operations/cruise_direction/pods_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`, `position`), `app/controllers/shift_operations/cruise_direction/people_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`); base `app/controllers/shift_operations/cruise_direction/base_controller.rb` (gate, viewed year, `load_slot`/`load_pod`, `render_board`, `render_refusal`)
Owner: `CruiseDirectionBoard` (`app/lib/cruise_direction_board.rb`), `Pod` (`app/models/pod.rb`) (not `AlphaPodBoard`)
Touches: `pod` (w), `person_pod` (w), `action_logs` (w), `slot`, `timesheet`, `position`, `person`, `person_photo`
Verify: `test/controllers/shift_operations/cruise_direction_controller_test.rb`, `test/lib/cruise_direction_board_test.rb`, `test/models/pod_test.rb`, `test/system/shift_operations/cruise_direction_drag_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `pods#position` and `Pod#move_to!` take a 1-based place in `Pod.shift_pods_for(slot)`'s line, never a `sort_index` — Laravel-shared `sort_index` has gaps and repeats; `PodsController#load_line_position` counts along the line.
Trap: `CruiseDirectionBoard.positions` must pass one positional hash, `Position.find_for_query({ cruise_direction: true, active: true })` — bare keywords raise `ArgumentError`, since its only keyword is `is_admin:`.

### Mass Sign-Out
Reach it: `GET /shift-operations/mass-signout` → Shift Operations › Shift Operations Menu › Mass Sign-Out; sweep `POST /shift-operations/mass-signout`
Gate: `ADMIN`
Controller: `app/controllers/shift_operations/mass_signout_controller.rb` (`index`, `create`)
Owner: `MassSignoutReport` (`app/lib/reports/mass_signout_report.rb`), `ShiftManage.sign_off` (`app/lib/shift_manage.rb`) (not `OnDutyReport`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_event` (w), `person_pod` (w), `pod` (w), `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `action_logs` (w), `position`, `position_credit`
Verify: `test/controllers/shift_operations/mass_signout_controller_test.rb`, `test/lib/reports/mass_signout_report_test.rb`, `test/system/shift_operations/mass_signout_select_all_test.rb`, `test/lib/shift_manage_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `MassSignoutReport.open_entries` (`Timesheet.on_duty_now`) has no year bound on purpose and `create` accepts stale rows, recording years-long shifts — stale rows only render unchecked, outside select-all, named in a callout.
Trap: `sign_off_all` has no transaction on purpose — each `ShiftManage.sign_off` stands alone and may queue an `AutomaticActiveConversionMailer` email, so one failure must not undo the earlier ones.

### ROC Photo Board
Reach it: `GET /shift-operations/roc-photo-board` → Shift Operations › Shift Operations Menu › ROC Photo Board; timed refresh `GET /shift-operations/roc-photo-board/board`
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/shift_operations/roc_photo_board_controller.rb` (`index`, `board`)
Owner: `RocPhotoBoardReport` (`app/lib/reports/roc_photo_board_report.rb`), `photo_board` Stimulus controller (`app/javascript/controllers/photo_board_controller.js`, extends `app/javascript/controllers/kiosk_controller.js`)
Touches: `timesheet`, `position`, `person`, `person_photo`, `active_storage_attachments`, `active_storage_blobs`
Verify: `test/controllers/shift_operations/roc_photo_board_controller_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: the `photo-board` frame in `app/views/shift_operations/roc_photo_board/index.html.erb` starts without `src` and `board.html.erb` must never name its own address — Turbo empties a self-answered frame; the `kiosk_controller.js` timer sets `src`.
Trap: the page uses `app/views/layouts/photo_board.html.erb` (dark via `class="dark"` + `data-theme="dark"`; no navbar, modal frame or toasts) and skips `build_menu_items`, so toast streams, flash and modal dialogs never render.

### Roll Call (rollcall)
Reach it: `GET /shift-operations/rollcall` → Shift Operations › Shift Operations Menu › Roll Call; rosters `GET /shift-operations/rollcall/sign-in`, `GET /shift-operations/rollcall/sign-out`; taps `POST /shift-operations/rollcall/check-in`, `POST /shift-operations/rollcall/check-out`, `POST /shift-operations/rollcall/resume`
Gate: `ADMIN`, `SHIFT_MANAGEMENT`
Controller: `app/controllers/shift_operations/rollcall_controller.rb` (`index`, `sign_in`, `sign_out`, `check_in`, `check_out`, `resume`)
Owner: `Rollcall` (`app/lib/rollcall.rb`), `ShiftManage` (`app/lib/shift_manage.rb`), `ShiftOperations::RollcallHelper` (`app/helpers/shift_operations/rollcall_helper.rb`) (not `Slot.retrieve_sign_ups`)
Touches: `timesheet` (w), `timesheet_log` (w), `person_event` (w), `person_pod` (w), `pod` (w), `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `action_logs` (w), `slot`, `person_slot`, `position`, `person_photo`
Verify: `test/controllers/shift_operations/rollcall_controller_test.rb`, `test/lib/rollcall_test.rb`, `test/lib/shift_manage_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `Rollcall.mode_from` recognises only `"sign_out"`; the route spelling `sign-out` or anything else silently reads as `:sign_in`, so a tap's streamed row and count come back in the wrong mode.
Trap: `Rollcall.on_duty_scope` (and `Timesheet.find_person_on_duty`, used by `ShiftManage.sign_in`) is present-year only on purpose — a past event's open entry belongs to Mass Sign-Out; don't widen the sign-out roster.

### Missing Paycom Employee IDs (payroll missing id)
Reach it: `GET /shift-operations/payroll-missing-id` → Shift Operations › Payroll › Missing Paycom Employee IDs; CSV: same route + `.csv`
Gate: `ADMIN`, `PAYROLL`
Controller: `app/controllers/shift_operations/payroll_missing_id_controller.rb` (`index`; CSV rows in private `csv_rows`)
Owner: `PayrollMissingIdReport` (`app/lib/reports/payroll_missing_id_report.rb`), `ShiftOperations::PayrollMissingIdHelper#payroll_missing_id_callsign` (`app/helpers/shift_operations/payroll_missing_id_helper.rb`)
Touches: `person_slot`, `slot`, `position`, `person`
Verify: `test/controllers/shift_operations/payroll_missing_id_controller_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `PayrollMissingIdReport.execute` splits `employee_id` `[nil, ""]` from `"0"` (`Person::UNPAID_EMPLOYEE_ID`: cleared to take paid shifts unpaid) in SQL so MariaDB collation decides padded values — don't re-split in Ruby (`strip`/`blank?`).
Trap: `Person#employee_id=` trims through `StripAttributes.strip` (blank → nil, `"0 "` → `"0"`), so a test needing a blank or `"0 "` id must write it with `update_column`.

### Payroll Export
Reach it: `GET /shift-operations/payroll-export` → Shift Operations › Payroll › Payroll Export; downloads: same route + `.csv` and `variant=adjusted|unadjusted|table|without-ids`
Gate: `ADMIN`, `PAYROLL`
Controller: `app/controllers/shift_operations/payroll_export_controller.rb` (`index`; punch-file/table CSV rows in private `punch_rows`/`table_rows`, via `CsvExportConcern`)
Owner: `PayrollExportReport` (`app/lib/reports/payroll_export_report.rb`), `PayrollExportForm` (`app/forms/payroll_export_form.rb`), `ShiftOperations::PayrollExportHelper` (`app/helpers/shift_operations/payroll_export_helper.rb`)
Touches: `timesheet`, `person`, `position`
Verify: `test/controllers/shift_operations/payroll_export_controller_test.rb`, `test/lib/reports/payroll_export_report_test.rb`, `test/lib/shift_operations_menu_test.rb`
Trap: `PayrollExportReport.entries_in_window` binds the pay window as `wall_clock` strings, never `Time` — the column is machine-local wall clock, so a `Time` bound shifts an hour when that zone and `Time.zone` disagree, dropping the period's last hour.
Trap: `payroll_export_link` must not use `data-turbo-confirm` — Turbo turns the link into a form submission and discards the file; the `download-confirm` Stimulus controller asks, then navigates.

## Timesheets

All controllers inherit `ApplicationController`, use `layout "timesheets"` and gate with one `authorize_role` matching its `Menus::TIMESHEETS` item's `visible_if`; `app/lib/reports/` classes are top-level (`OnDutyReport`, not `Reports::OnDutyReport`). All but On Duty and Top Hour Earners read `?year=` via `setup_year`, whose `year_floor` admits 2020–2021 though every hero `year_selector` but Slot Repair's passes `skip_pandemic: true`, so `?year=2020` heads the page 2020, the selector another year.

### On Duty
Reach it: `GET /timesheets/on-duty` → Timesheets › Reports › On Duty (`?duty_date=`, `?excessive_only=`)
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/on_duty_controller.rb` (`index`)
Owner: `OnDutyReport` (`app/lib/reports/on_duty_report.rb`)
Touches: `timesheet`, `person`, `position`, `slot`
Verify: `test/controllers/timesheets/on_duty_controller_test.rb`, `test/lib/reports/on_duty_report_test.rb`
Trap: `OnDutyReport.timesheets` bounds `on_duty` by `MAX_SHIFT_LOOKBACK` (14 days), not `Timesheet.for_year`, whose machine-zone `where_year` drops an open shift begun New Year's Eve; the constant also moves `MassSignoutReport.band_for` and `RocPhotoBoardReport`.
Trap: `build_entry` clamps elapsed time to `as_of`, not `Timesheet#duration` (measured to now), and entries group by `position_id`, not the `position` association, which reads nil for a deleted position.

### Forced Shift Starts (forced shift start)
Reach it: `GET /timesheets/forced-shift-start` → Timesheets › Reports › Forced Shift Starts; CSV `GET /timesheets/forced-shift-start.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`, `EVENT_MANAGEMENT`
Controller: `app/controllers/timesheets/forced_shift_start_controller.rb` (`index`)
Owner: `ForcedShiftStartReport` (`app/lib/reports/forced_shift_start_report.rb`), `TimesheetLog#decode_data` (`app/models/timesheet_log.rb`, pre-2025 blockers only)
Touches: `timesheet`, `timesheet_log`, `person`, `position`
Verify: `test/controllers/timesheets/forced_shift_start_controller_test.rb`, `test/lib/reports/forced_shift_start_report_test.rb`
Trap: `timesheet_blocker_label` (`app/helpers/person/timesheets_helper.rb`) also labels `common/shift_manage/_blocked_modal`, `shift_operations/rollcall/_blocked_dialog` and the person timesheet log — rewording a Blockers label rewords the live sign-in UI.
Trap: The CSV writes `entry.on_duty.iso8601` without `getlocal`, so Shift Start carries the `Time.zone` offset, unlike siblings' `getlocal.iso8601` or `strftime("%FT%T")`; no test pins it.

### Early / Late Check-Ins
Reach it: `GET /timesheets/early-late-checkins` → Timesheets › Reports › Early / Late Check-Ins; CSV `GET /timesheets/early-late-checkins.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/early_late_checkins_controller.rb` (`index`)
Owner: `EarlyLateCheckInReport` (`app/lib/reports/early_late_check_in_report.rb`)
Touches: `setting`, `slot`, `position`, `timesheet`, `timesheet_log`, `person`
Verify: `test/controllers/timesheets/early_late_checkins_controller_test.rb`, `test/lib/reports/early_late_check_in_report_test.rb`
Trap: `slots_by_position` compares `slot.begins`/`ends` against `on_duty` — never the `begins_time`/`ends_time` epoch columns, which Laravel and Rails wrote on different clocks and drift an hour off-season.
Trap: `ShiftCheckInEarlyPeriod` or `ShiftCheckInLatePeriod` at 0 switches that side off rather than tightening it; with both at 0 `execute` returns an empty report without querying.

### Hours & Credits
Reach it: `GET /timesheets/hours-credits` → Timesheets › Reports › Hours & Credits; CSV `GET /timesheets/hours-credits.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/hours_credits_controller.rb` (`index`)
Owner: `HoursCreditsReport` (`app/lib/reports/hours_credits_report.rb`), `EventSummary` (`app/lib/event_summary.rb`)
Touches: `event_dates`, `person`, `timesheet`, `position`, `position_credit`
Verify: `test/controllers/timesheets/hours_credits_controller_test.rb`, `test/lib/reports/hours_credits_report_test.rb`, `test/lib/timesheets_menu_test.rb`
Trap: Bulk `EventSummary.new` callers must pass `year_credits:` as `HoursCreditsReport.build_row` does, or each ranger's summary re-reads the year's `position_credit` rates via `PositionCredit.year_credits`.
Trap: Total Hours (`Row#counted_duration`) omits `count_hours` false positions though their credits count, and a year without usable `EventDate` start/end returns an empty report (`event_dates?` false), not zeros.

### Timesheets by Callsign
Reach it: `GET /timesheets/timesheets-by-callsign` → Timesheets › Reports › Timesheets by Callsign; drill-down `GET /timesheets/timesheets-by-callsign/person/:person_id`; both `.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`, `EVENT_MANAGEMENT` (`FULL_REPORT_ACCESS` alone does not open it)
Controller: `app/controllers/timesheets/timesheets_by_callsign_controller.rb` (`index`, `person`), `app/controllers/concerns/callsign_status_filter_concern.rb`, `app/controllers/concerns/person_lookup_concern.rb`
Owner: `TimesheetByCallsignReport` (`app/lib/reports/timesheet_by_callsign_report.rb`), `TimesheetYearReport` (`app/lib/reports/timesheet_year_report.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`)
Touches: `timesheet`, `person`, `position`, `slot`, `position_credit`, `team`, `person_team`, `team_manager`
Verify: `test/controllers/timesheets/timesheets_by_callsign_controller_test.rb`, `test/lib/reports/timesheet_by_callsign_report_test.rb`
Trap: Only `TimesheetYearReport::FULL_ACCESS_ROLES` (`ADMIN`, `FULL_REPORT_ACCESS`) see every position; others see their Cadre, Delegation or managed teams' positions — query via `visible_scope`/`entries(viewer:)`, never `Timesheet.for_year`.
Trap: `TimesheetYearReport` is included on the instance side, so a bare constant inside the reports' `class << self` raises NameError — qualify it (`TimesheetYearReport::NO_MEMBERSHIP`).

### Timesheet by Position
Reach it: `GET /timesheets/timesheet-by-position` → Timesheets › Reports › Timesheet by Position; drill-down `GET /timesheets/timesheet-by-position/position/:position_id`; both `.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`, `EVENT_MANAGEMENT` (`FULL_REPORT_ACCESS` alone does not open it)
Controller: `app/controllers/timesheets/timesheet_by_position_controller.rb` (`index`, `position`), `app/controllers/concerns/position_lookup_concern.rb`
Owner: `TimesheetByPositionReport` (`app/lib/reports/timesheet_by_position_report.rb`), `TimesheetYearReport` (`app/lib/reports/timesheet_year_report.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`)
Touches: `timesheet`, `person`, `position`, `slot`, `position_credit`, `team`, `person_team`, `team_manager`
Verify: `test/controllers/timesheets/timesheet_by_position_controller_test.rb`, `test/lib/reports/timesheet_by_position_report_test.rb`
Trap: The drill-down gates on `TimesheetByPositionReport.position(...).readable` (team-owned position ids), not an empty result like by-callsign's `hidden_person_redirect` — a scoped reader may open their own position in a year with no entries.
Trap: The index CSV ("Export All to CSV") ignores the title/active filters and exports the whole visible year.

### Timesheet Totals (timesheet totals report)
Reach it: `GET /timesheets/timesheet-totals-report` → Timesheets › Reports › Timesheet Totals; drill-down `GET /timesheets/timesheet-totals-report/person/:person_id`; CSV on the index only
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/timesheet_totals_report_controller.rb` (`index`, `person`), `app/controllers/concerns/callsign_status_filter_concern.rb`, `app/controllers/concerns/person_lookup_concern.rb`
Owner: `TimesheetTotalsReport` (`app/lib/reports/timesheet_totals_report.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`) (not `TimesheetYearReport`: no team scoping)
Touches: `timesheet`, `position`, `person`, `position_credit`
Verify: `test/controllers/timesheets/timesheet_totals_report_controller_test.rb`, `test/lib/reports/timesheet_totals_report_test.rb`
Trap: `TimesheetTotalsReport.load_rows` inner-joins `Position.where(count_hours: true)`, dropping non-hour positions and entries whose position is gone, so totals won't match Timesheets by Callsign.
Trap: `Timesheet#credits` in a loop re-reads the year's whole cached credit hash per call via `PositionCredit.find_for_year_position` — price rows with `TimesheetCredits.credits_by_id`.

### Top Hour Earners
Reach it: `GET /timesheets/top-hour-earners` → Timesheets › Reports › Top Hour Earners (`?start_year=`, `?end_year=`, `?limit=`); CSV `GET /timesheets/top-hour-earners.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/top_hour_earners_controller.rb` (`index`)
Owner: `TopHourEarnersReport` (`app/lib/reports/top_hour_earners_report.rb`), `EventYearSpan` (`app/lib/event_year_span.rb`)
Touches: `timesheet`, `position`, `person`
Verify: `test/controllers/timesheets/top_hour_earners_controller_test.rb`, `test/lib/reports/top_hour_earners_report_test.rb`, `test/helpers/timesheets/top_hour_earners_helper_test.rb`, `test/lib/event_year_span_test.rb`, `test/lib/timesheets_menu_test.rb`
Trap: No `setup_year`, so `?year=` is ignored; rangers rank by best single year (`top_duration`), not span total (`Row#total_duration` is read by tests only).
Trap: `counted_shifts` keeps only closed entries (`with_off_duty`) on `count_hours` positions — an open entry is valued up to now, so a sign-in left open since January would rank first.

### Correction Requests
Reach it: `GET /timesheets/correction-requests` → Timesheets › Timesheet Wrangling › Correction Requests (`?letter=`); CSV `GET /timesheets/correction-requests.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/correction_requests_controller.rb` (`index`)
Owner: `CorrectionRequestsReport` (`app/lib/reports/correction_requests_report.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`)
Touches: `timesheet`, `timesheet_missing`, `timesheet_note`, `timesheet_missing_note`, `person`, `position`, `position_credit`
Verify: `test/controllers/timesheets/correction_requests_controller_test.rb`
Trap: `Timesheet` and `TimesheetMissing` ids collide (separate sequences) — price with `TimesheetCredits.credits_by_collection` (one hash per table) and key DOM ids with `Entry#dom_key`, never one merged id-keyed hash.
Trap: `csv_timestamp` writes the stored wall clock with `strftime("%FT%T")` (the controller test pins it) — `getlocal` or `iso8601` would export a different hour than the row on screen.

### Correction Statistics (correction stats)
Reach it: `GET /timesheets/correction-stats` → Timesheets › Timesheet Wrangling › Correction Statistics
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/correction_stats_controller.rb` (`index`)
Owner: `CorrectionStatsReport` (`app/lib/reports/correction_stats_report.rb`)
Touches: `timesheet_log`, `timesheet`, `timesheet_missing`, `person`, `position`
Verify: `test/controllers/timesheets/correction_stats_controller_test.rb`, `test/lib/reports/correction_stats_report_test.rb`
Trap: Corrections and deletions count by `timesheet_log.created_at` year, missing-entry requests by the shift's `on_duty` year (`timesheet_log.year`, the event year, is unused) — changing either side restates every historical number.
Trap: `missing_scope`'s `reviewer_person_id != person_id` is NULL-unsafe like upstream's, dropping unassigned requests; the top-20 lists read one lower per row than Clubhouse 2 (upstream's off-by-one fixed deliberately).

### Unconfirmed Timesheets (timesheet unconfirmed)
Reach it: `GET /timesheets/timesheet-unconfirmed` → Timesheets › Timesheet Wrangling › Unconfirmed Timesheets; CSV `GET /timesheets/timesheet-unconfirmed.csv`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/timesheet_unconfirmed_controller.rb` (`index`)
Owner: `UnconfirmedTimesheetsReport` (`app/lib/reports/unconfirmed_timesheets_report.rb`)
Touches: `person`, `timesheet`, `person_event`
Verify: `test/controllers/timesheets/timesheet_unconfirmed_controller_test.rb`, `test/lib/reports/unconfirmed_timesheets_report_test.rb`
Trap: Only `person_event.timesheet_confirmed` decides inclusion (`unverified_count` may be 0); count with `OPEN_REVIEW` (unverified/rejected), not `Timesheet.count_unverified_for_person_year`, which counts every non-verified status and drops open entries.
Trap: Page and CSV show name (`desired_full_name`), email and home phone with no `Current.can_view_pii?`/`can_view_email?` check — any role added to `authorize_role` gets that contact data.

### Timesheets › Sanity Checker
Reach it: `GET /timesheets/sanity-checker` → Timesheets › Timesheet Wrangling › Sanity Checker; drill-down `GET /timesheets/sanity-checker/:check` (dasherized key, also `.csv`)
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/sanity_checker_controller.rb` (`index`, `check`)
Owner: `TimesheetSanityCheckReport` (`app/lib/reports/timesheet_sanity_check_report.rb`), `Timesheets::SanityCheckerHelper` (`app/helpers/timesheets/sanity_checker_helper.rb`), `TimesheetCredits` (`app/lib/reports/timesheet_credits.rb`)
Touches: `timesheet`, `slot`, `person`, `position`, `position_credit`
Verify: `test/controllers/timesheets/sanity_checker_controller_test.rb`, `test/lib/reports/timesheet_sanity_check_report_test.rb`
Trap: A new check needs both `TimesheetSanityCheckReport::CHECKS` and the helper's `CHECK_META` (read with `fetch`, so a missing key raises); keep the `timesheet_check_` helper prefix — shorter names silently replaced `Bmid::SanityCheckHelper#sanity_check_meta`.
Trap: `no_credits` (`DEFERRED_KEY`) is left out of `summary` because it prices the whole year; its HTML page caps at the controller's `PAGE_LIMIT` (500), its CSV does not.

### Slot Repair (timesheet slot repair)
Reach it: `GET /timesheets/timesheet-slot-repair` → Timesheets › Timesheet Wrangling › Slot Repair; apply `POST /timesheets/timesheet-slot-repair/apply`
Gate: `ADMIN`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/timesheets/timesheet_slot_repair_controller.rb` (`index`, `apply`)
Owner: `TimesheetSlotRepair` (`app/lib/reports/timesheet_slot_repair.rb`)
Touches: `timesheet` (w), `timesheet_log` (w), `action_logs` (w), `slot`, `person_slot`, `person`, `position`
Verify: `test/controllers/timesheets/timesheet_slot_repair_controller_test.rb`, `test/lib/reports/timesheet_slot_repair_test.rb`
Trap: `TimesheetSlotRepair.write` uses `update_column(:slot_id, …)`, skipping `Timesheet` callbacks (`adjust_roles`, `rebuild_awards_and_years`, `log_updates`), so it writes the `timesheet_log`/`action_logs` rows itself.
Trap: `MATCH_WINDOW` must stay `Scheduling::LOCATE_SHIFT_START_WITHIN`, or the repair undoes the links `Timesheet#associate_slot` makes on save.
Trap: `apply` re-scans the year, writes only submitted ids still in the fresh preview (the rest count as skipped), then renders `index` at 422, not a redirect, since results can't be re-derived after the fix.

## People, Certificates & Agreements

Each page is gated by one class-level `authorize_role` (refusal redirects to /me). Only People by Location and Unified Flagging take a viewed year (`setup_year`); Status Change Recommendations takes `period`, the rest `Current.year` or no year. The bulk paste tools share `BulkUploadPage` over `BulkUpload::Batch`: re-rendering POSTs answer 422 on purpose, locked accounts are refused unless the handler opts out, and each apply writes one `bulk-upload` row to `action_logs`.

### Bulk Lookup
Reach it: `GET /people/bulk-lookup` → People › People Menu › Bulk Lookup; lookup `POST /people/bulk-lookup` (CSV: same POST as `.csv` with `subset=found|not_found`)
Gate: `ADMIN`
Controller: `app/controllers/people/bulk_lookup_controller.rb` (`index`, `lookup`)
Owner: `BulkLookupReport` (`app/lib/reports/bulk_lookup_report.rb`)
Touches: `person`
Verify: `test/controllers/people/bulk_lookup_controller_test.rb`, `test/lib/people_menu_test.rb`
Trap: Results exist only as the POST's response — export buttons (`people/bulk_lookup/_export_form`) re-POST the pasted `lines` with a `subset` (other subsets 400, a refused list 422); never make an export a GET link.
Trap: `BulkLookupReport.matches_for` groups on `callsign_normalized.downcase` and `email.downcase` (stored case varies); a line matching two people lands in `ambiguous`, exported with the not-found CSV, never a guess.

### Create Account
Reach it: `GET /people/create-account` → People › People Menu › Create Account; create `POST /people/create-account` (redirects to `/person/:id`)
Gate: `ADMIN`
Controller: `app/controllers/people/create_account_controller.rb` (`new`, `create`)
Owner: `CreateAccountForm` (`app/forms/create_account_form.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `action_logs` (w), `position`, `role`
Verify: `test/controllers/people/create_account_controller_test.rb`, `test/forms/create_account_form_test.rb`, `test/lib/person_status_management_test.rb`, `test/models/person_test.rb`, `test/lib/people_menu_test.rb`
Trap: `Person#log_status_change` returns early on `previously_new_record?`, so a bare `Person.create` gets no `person_status` row, positions or roles — use `CreateAccountForm#save`, which calls `PersonStatusManagement.change` in the same transaction.

### Languages Known
Reach it: `GET /people/languages-known` → People › People Menu › Languages Known; language `GET /people/languages-known/*language`
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/people/languages_known_controller.rb` (`index`, `show`)
Owner: `LanguagesKnownReport` (`app/lib/reports/languages_known_report.rb`), `People::LanguagesKnownHelper` (`app/helpers/people/languages_known_helper.rb`)
Touches: `person_language`, `person`, `timesheet`, `position`, `person_asset`, `asset`
Verify: `test/controllers/people/languages_known_controller_test.rb`, `test/lib/reports/languages_known_report_test.rb`, `test/lib/people_menu_test.rb`
Trap: `person.on_site`, selected through the `person_language` join, arrives as integer 0 (truthy in Ruby) — read the report's `on_site?` cast (`ActiveModel::Type::Boolean`), never the raw attribute.
Trap: A typed-in language stores `PersonLanguage::LANGUAGE_NAME_CUSTOM` in `language_name` and the name in `language_custom` — match `language_name` only on unmarked rows and search `language_custom` separately, as `LanguagesKnownReport.matching`/`.named` do.

### People by Location
Reach it: `GET /people/people-by-location` → People › People Menu › People by Location; country `GET /people/people-by-location/country/:country` (each level exports `.csv`)
Gate: `ADMIN`, `MENTOR`, `TRAINER`, `VC`
Controller: `app/controllers/people/people_by_location_controller.rb` (`index`, `country`)
Owner: `PeopleByLocationReport` (`app/lib/reports/people_by_location_report.rb`), `People::PeopleByLocationHelper` (`app/helpers/people/people_by_location_helper.rb`)
Touches: `person`, `person_slot`, `slot`, `timesheet`
Verify: `test/controllers/people/people_by_location_controller_test.rb`, `test/lib/reports/people_by_location_report_test.rb`, `test/lib/people_menu_test.rb`
Trap: Only Signed Up and Rangered follow `@year` (Alpha slots never count as sign-ups); addresses are today's and `OPTIONAL_STATUSES` stay hidden unless `?statuses[]=` restores them — totals are not `Person.count`.
Trap: Blank states and countries bucket under `NO_STATE = "no-state"` and `NO_COUNTRY = "no-country"` (a dash is a stored state) — compare through `Row#state_key` and `Row#country_key`, never a dash or empty string.

### People by Status
Reach it: `GET /people/people-by-status` → People › People Menu › People by Status; status `GET /people/people-by-status/:status`
Gate: `ADMIN`
Controller: `app/controllers/people/people_by_status_controller.rb` (`index`, `show`)
Owner: `PeopleByStatusReport` (`app/lib/reports/people_by_status_report.rb`)
Touches: `person`
Verify: `test/controllers/people/people_by_status_controller_test.rb`, `test/lib/reports/people_by_status_report_test.rb`, `test/lib/people_menu_test.rb`
Trap: The `:status` segment is `PeopleByStatusReport.slug(status)` (`past-prospective`), not the stored value — a raw `"past prospective"` link redirects to the index with "That is not a status the Clubhouse assigns."

### People Search
Reach it: `GET /people/search` → People › People Menu › People Search (criteria as `filter[...]`; CSV is the same GET as `.csv`; no status checked runs only with `confirmed=1`)
Gate: `ADMIN`, `VC`
Controller: `app/controllers/people/search_controller.rb` (`index`)
Owner: `PeopleSearchReport` (`app/lib/reports/people_search_report.rb`), `PersonSearchForm` (`app/forms/person_search_form.rb`), `People::SearchHelper` (`app/helpers/people/search_helper.rb`) (not `PersonSearch` in `app/lib/person_search.rb`, the fuzzy autocomplete)
Touches: `person`, `person_status`, `person_photo`, `person_online_course`, `person_event`, `person_slot`, `slot`, `trainee_status`, `trainer_status`, `access_document`
Verify: `test/controllers/people/search_controller_test.rb`, `test/lib/people_menu_test.rb`
Trap: "Updated During YEAR" moves only the `person_status` lookup; online course, in-person training and ticketing criteria and columns always judge `Current.year` (`online_courses_by_person`, `person_events_by_person`, `signups_by_person`).
Trap: `PeopleSearchReport.trainee_verdict` passes `Time.zone.now` to `Training.time_within_grace_period?`, ignoring the Groundhog Day clock — pass `Current.time` if you touch it.
Trap: Pagy pages the match in memory (the report filters in Ruby, so all of it is loaded anyway): 100 a page, a page past the last reads as the last, and `ui_pager` draws only past one page, as the "Result pages" navigation landmark it has always been; tests pin both. The CSV carries every match, whatever the page.

### Retention Report
Reach it: `GET /people/retention-report` → People › People Menu › Retention Report (CSV: same GET as `.csv`, filtered like the page)
Gate: `ADMIN`, `VC`
Controller: `app/controllers/people/retention_report_controller.rb` (`index`)
Owner: `RetentionReport` (`app/lib/reports/retention_report.rb`), `EventYearSpan` (`app/lib/event_year_span.rb`)
Touches: `person`, `timesheet`
Verify: `test/controllers/people/retention_report_controller_test.rb`, `test/lib/reports/retention_report_test.rb`, `test/lib/event_year_span_test.rb`, `test/lib/people_menu_test.rb`
Trap: `RetentionReport.rangered_in` (non-echelon timesheets outside Alpha, Training and Deep Freeze, five events to the present year) picks who is listed; First, Last and Total come from `person.years_as_ranger` — they disagree on purpose, don't reconcile.
Trap: `YearsManagement` is stubbed to no-ops in `test/test_helper.rb`, so test Timesheets never update `years_as_ranger` — set it via `PersonTestFactory#create_person(years:)` or `update_columns`.

### People › Unified Flagging
Reach it: `GET /people/unified-flagging` → People › People Menu › Unified Flagging (year-scoped; `?person=:id` fills the read-only review pane; `?section=` narrows to one group; CSV: same GET as `.csv`, filtered and ordered like the page)
Gate: `ADMIN`
Controller: `app/controllers/people/unified_flagging_controller.rb` (`index`; no `#detail` route — the pane loads through the index)
Owner: `Intake` (`app/lib/intake.rb`, `retrieve_recorded_for_year`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`), `People::UnifiedFlaggingHelper` (`app/helpers/people/unified_flagging_helper.rb`)
Touches: `person`, `person_fka`, `person_intake`, `person_intake_note`, `person_mentor`, `trainee_note`, `trainee_status`, `slot`, `person_slot`, `person_status`, `trainer_status`, `timesheet`
Verify: `test/controllers/people/unified_flagging_controller_test.rb`, `test/lib/intake_test.rb` (`IntakeRetrieveRecordedForYearTest`), `test/lib/people_menu_test.rb`
Trap: The year's facts (`year_notes`, `year_ranks`) are read off the rows the line and pane are built from (`Intake.year_facts_for`), and a person is listed only when they hold one — a trainer's note or rank counts only on an ended session the person still has a sign-up for, as the pane shows it. `year_bonk` is the year's verdict from `PersonMentor.retrieve_all_mentors_for_ids` (`PersonMentor.year_verdict` when the rows disagree), the same one the pane's history and the bonk chip read. The lines, chips and groups read the latest-to-date facts as on `/vc/unified-flagging`; only `?rank=`, `?notes=`, the CSV and the line's trainer-note word (`_line_training_note`) read the year's.
Trap: `training_status` is nil for anyone listed who had no session that year and was not in its intake pipeline (`clear_training_status_outside_pipeline`): the shared `_list_row` and `_signal_line` print no training word for nil, `?training=` never matches it, and the CSV cell is blank.
Trap: The list is one roster by callsign, sorted in `Intake.retrieve_recorded_for_year`, and the CSV reads the same rows. The tiles and Section select read `unified_flagging_group_meta`, which this controller overrides to retitle the third group "Everyone else"; the `?section=` tokens stay Intake's groups.
Trap: A pane request (`Turbo-Frame: uf-pane`) builds the roster for the one person it names (`person_ids:`), then runs the filters on it, so a person the filters hide still selects nothing.
Trap: The year queries lean on the year-leading indexes of `db/migrate/20261017000001_add_unified_flagging_year_indexes.rb`; a database without them scans each table.
Trap: Read-only for an Admin too (`unified_flagging_read_only?`), so no `ORIGIN_RETURNS` token exists for it — notes are filed from Person › Unified Flagging or VC › Unified Flagging.

### Bulk Change Status
Reach it: `GET /people/bulk-status` → People › Account Maintenance › Bulk Change Status; preview `POST /people/bulk-status/preview`; apply `POST /people/bulk-status`; back to form `POST /people/bulk-status/edit`
Gate: `ADMIN`
Controller: `app/controllers/people/bulk_status_controller.rb` (`ACTIONS`; `index`, `preview`, `apply` from `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::StatusHandler` (`app/lib/bulk_upload/status_handler.rb`), `BulkUpload::PersonFlagHandler` (`app/lib/bulk_upload/person_flag_handler.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_team` (w), `person_team_log` (w), `action_logs` (w), `position`, `role`
Verify: `test/controllers/people/bulk_status_controller_test.rb`, `test/lib/person_status_management_test.rb`, `test/lib/people_menu_test.rb`
Trap: `StatusHandler#apply` only sets `person.status` and `audit_reason`, then `save!(validate: false)`: `Person#log_status_change` (after_save) runs `PersonStatusManagement.change` — calling it from the handler too doubles history rows, grants and strips.
Trap: `StatusHandler#refuses_locked_statuses?` is false — unlike every other bulk handler it moves deceased, dismissed, resigned, suspended and uberbonked accounts, since reinstatements start there.

### Status Change Recommendations
Reach it: `GET /people/status-change-recommendations` → People › Account Maintenance › Status Change Recommendations; group `GET /people/status-change-recommendations/:group` (exports `.csv`, filtered like the page); convert `POST /people/status-change-recommendations/:group`
Gate: `ADMIN`
Controller: `app/controllers/people/status_change_recommendations_controller.rb` (`index`, `show`, `convert`)
Owner: `RecommendStatusChangeReport` (`app/lib/reports/recommend_status_change_report.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `timesheet`, `person_status` (w), `person_position` (w), `person_position_log` (w), `person_role` (w), `person_team` (w), `person_team_log` (w), `person_slot` (w), `slot` (w), `person_fka` (w), `action_logs` (w)
Verify: `test/controllers/people/status_change_recommendations_controller_test.rb`, `test/lib/reports/recommend_status_change_report_test.rb`, `test/lib/person_status_management_test.rb`, `test/lib/people_menu_test.rb`
Trap: `RecommendStatusChangeReport.year_for` turns `?period=current-date|next-event` into `Current.year` or `Current.year + 1`; there is no viewed year, so `?year=` is ignored.
Trap: `RecommendStatusChangeReport.rangered_since` bounds `timesheet.on_duty` with `Time.local(year)`, not `Time.zone` — timesheets store machine-local wall-clock time, and a zoned boundary drags in the previous year's last hour.

### Certificates Report
Reach it: `GET /certificates/certificates-report` → Certificates › Certificates Menu › Certificates Report; roster `GET /certificates/certificates-report/:id` (both export `.csv`)
Gate: `ADMIN`, `CERTIFICATION_MGMT`
Controller: `app/controllers/certificates/certificates_report_controller.rb` (`index`, `show`)
Owner: inline in controller — queries `Certification`, `PersonCertification`
Touches: `certification`, `person_certification`, `person`
Verify: `test/controllers/certificates/certificates_report_controller_test.rb`, `test/lib/certificates_menu_test.rb`
Trap: Counts cover only `Person::ACTIVE_STATUSES` holders (`active_holders`); `Certification#total_people` counts every `person_certification` row whatever the holder's status — never swap it in.
Trap: Names (roster and both CSVs) need `Current.can_view_pii?` and emails (CSVs only) `Current.can_view_email?`, set by `set_visible_columns` as `@show_names`/`@show_emails`; `ADMIN` grants both, `CERTIFICATION_MGMT` alone neither.

### Bulk Record Certifications
Reach it: `GET /certificates/bulk-record` → Certificates › Certificates Menu › Bulk Record Certifications; preview `POST /certificates/bulk-record/preview`; apply `POST /certificates/bulk-record`; back to form `POST /certificates/bulk-record/edit`
Gate: `ADMIN`
Controller: `app/controllers/certificates/bulk_record_controller.rb` (`bulk_actions`, built from `Certification` per request; `index`, `preview`, `apply` from `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::CertificationHandler` (`app/lib/bulk_upload/certification_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`)
Touches: `certification`, `person`, `person_certification` (w), `action_logs` (w)
Verify: `test/controllers/certificates/bulk_record_controller_test.rb`, `test/lib/certificates_menu_test.rb`
Trap: `PersonCertification` is not an audit model, so `audit_reason =` in `CertificationHandler#apply` records nothing — a new record keeps only `recorder_id`; an update's only trail is the batch's `bulk-upload` row in `action_logs`.
Trap: `test/controllers/certificates/bulk_record_controller_test.rb` assumes nobody holds `certification(:cpr)` as `auditor_ranger` — a `person_certification` fixture for that pair breaks it; give new fixtures other people.

### Bulk Record a Signature (Bulk Record a Signed Agreement)
Reach it: `GET /agreements/bulk-signature` → Agreements › Agreements Menu › Bulk Record a Signature; preview `POST /agreements/bulk-signature/preview`; apply `POST /agreements/bulk-signature`; back to form `POST /agreements/bulk-signature/edit`
Gate: `ADMIN`
Controller: `app/controllers/agreements/bulk_signature_controller.rb` (`ACTIONS`; `index`, `preview`, `apply` from `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::AgreementSignatureHandler` (`app/lib/bulk_upload/agreement_signature_handler.rb`), `Agreements.admin_set_signature` (`app/lib/agreements.rb`)
Touches: `person`, `person_event` (w), `action_logs` (w)
Verify: `test/controllers/agreements/bulk_signature_controller_test.rb`, `test/lib/agreements_test.rb`
Trap: Signatures always land in the present year (`BulkUpload::Handler#year` is `Current.year`, announced via `year_scoped: true`) — this page cannot record another year.
Trap: Never set `person_event.sandman_affidavit` directly — `Agreements.admin_set_signature` writes the per-person `agreement-signature` row in `action_logs`, and `person_event` keeps no history.

## Teams & Positions

All twelve controllers inherit `ApplicationController` directly with `layout "teams_positions"`; none uses the viewed year (Special Teams Hours takes its own start and end years, the Shiny Pennies check reads `Current.year`). Bulk preview/apply, Roster Management preview and Position Sanity Checker repair render at 422, not redirect (Turbo drops a 200 form answer). Each apply rebuilds its change from its own params, never trusting the preview.

### Team Records
Reach it: `GET /teams-positions/team-records` → Teams & Positions › Administration › Team Records; `GET /teams-positions/team-records/new`; `GET /teams-positions/team-records/:id/edit`; `POST /teams-positions/team-records`; `PATCH /teams-positions/team-records/:id`; `DELETE /teams-positions/team-records/:id`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/teams_positions/team_records_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `TeamManagement` (`app/lib/team_management.rb`), `Membership.update_team_roles` (`app/lib/membership.rb`)
Touches: `team` (w), `team_role` (w), `role`, `team_manager` (w), `person_team` (w), `person_team_log` (w), `person_award` (w), `person` (w), `position` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/team_records_controller_test.rb`, `test/models/person_team_test.rb`
Trap: `team.destroy` deletes positions (`has_many :position, dependent: :destroy`) — use `TeamManagement.destroy`, which nulls `position.team_id`, clears child tables and lets `team.destroy!` destroy the memberships (a membership owns no team roles: they are the team's, `TeamRole` by `team_id`). It leaves messages' `sender_team_id`, `recipient_team_id` and member marks in place; the mailbox names a deleted team by id.
Trap: `TeamManagement.save(..., is_tech_ninja:)` silently ignores posted `team[role_ids]` unless the actor holds `TECH_NINJA`, and Admin does not imply it (`RoleManager#has_role?` is a plain set intersection).

### Position Records
Reach it: `GET /teams-positions/position-records` → Teams & Positions › Administration › Position Records; `GET /teams-positions/position-records/new`; `GET /teams-positions/position-records/:id/edit`; `POST /teams-positions/position-records`; `PATCH /teams-positions/position-records/:id`; `DELETE /teams-positions/position-records/:id`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/teams_positions/position_records_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PositionManagement` (`app/lib/position_management.rb`), `Membership.update_position_roles` (`app/lib/membership.rb`)
Touches: `position` (w), `position_role` (w), `role`, `team`, `slot` (w), `person_slot` (w), `trainee_status` (w), `trainer_status` (w), `person_position` (w), `person_award` (w), `person` (w), `position_lineup_member` (w), `position_credit` (w), `person_online_course` (w), `online_course` (w), `survey` (w), `shift_coverage_group` (w), `shift_coverage_position` (w), `timesheet` (w), `timesheet_missing`, `action_logs` (w)
Verify: `test/controllers/teams_positions/position_records_controller_test.rb`, `test/lib/position_management_test.rb`, `test/models/role_cache_invalidation_test.rb`, `test/models/position_test.rb` (the ART mentoring rules and the sign-up page headers)
Trap: Only a Tech Ninja may set `role_ids`, `require_training_for_roles` and `require_signin_for_roles` (`position_params` strips the flags, `PositionManagement.save` ignores `role_ids`); Admin does not imply `TECH_NINJA`.
Trap: `ranger_scheduling_header` and `applicant_scheduling_header` are the editor's HTML, stored as typed (a header with no words normalizes to nil, `Position` caps each at 65,535 characters) and sanitized only on render (`rich_text` on the sign-up page) — never print them `html_safe`.
Trap: The ART mentoring flags (`has_art_mentoring` on the training, `is_art_mentor` / `is_art_mentee` on two positions) pair positions by team, so `Position#validate_art_mentoring` requires a team and allows one of each per team, and only an ART training (`Training.training_position?` and `Training.art?`: not a trainer position, not In-Person Training) may carry `has_art_mentoring`. Never link a mentor or mentee position through its Training position instead: that field also makes every holder need the ART's pass to sign in (`SignInBlocker#check_for_training`), and Troubleshooter Training records no passes. Migration `20261021000001` seeded Green Dot (101/40/50) and Troubleshooter (94/128/127) by literal id.
Trap: `PositionManagement.destroy` refuses positions named by `timesheet`/`timesheet_missing` rows (`deletable?`), cascades slots itself, then calls `position.delete` — `position.destroy` would rerun `dependent: :destroy` on the slots.
Trap: `PositionManagement.destroy` also strips the id from `shift_coverage_group.base_position_ids` and `shift_coverage_position.position_ids` (JSON lists, so no foreign key does it) with `validate: false` (`ShiftCoverageGroup.remove_position`, `ShiftCoveragePosition.remove_position`), logged as "Position deletion"; a list it empties stays and reads nothing. The delete confirmation names them through `child_counts` (`shift_coverage_type_count`, `shift_coverage_post_count`, found by `listing_position` on each model).

### Position Lineups
Reach it: `GET /teams-positions/position-lineups` → Teams & Positions › Administration › Position Lineups; `GET /teams-positions/position-lineups/new`; `GET /teams-positions/position-lineups/:id/edit`; `POST /teams-positions/position-lineups`; `PATCH /teams-positions/position-lineups/:id`; `DELETE /teams-positions/position-lineups/:id`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/teams_positions/position_lineups_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `PositionLineupManagement` (`app/lib/position_lineup_management.rb`)
Touches: `position_lineup` (w), `position_lineup_member` (w), `position`, `action_logs` (w)
Verify: `test/controllers/teams_positions/position_lineups_controller_test.rb`, `test/lib/position_lineup_management_test.rb`
Trap: `position_lineup_member.position_id` is UNIQUE; `PositionLineupManagement.validate_positions` names the conflicting lineup and `save` rescues `RecordNotUnique` — never revert to upstream's insert-or-ignore, which dropped positions silently.
Trap: `parse_position_ids` reads an absent `position_lineup[position_ids][]` as nil (keep the members) — a form or test must post the blank hidden field `_form.html.erb` sends, or clearing every box keeps the old members.

### Membership Report
Reach it: `GET /teams-positions/membership-report` → Teams & Positions › Teams & Positions Menu › Membership Report; team roster `GET /teams-positions/membership-report/:team_id`
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/teams_positions/membership_report_controller.rb` (`index`, `show`)
Owner: inline in controller: `Team`, `PersonTeam`, `TeamManager`, `Person.basic_info` (not `TeamMembershipReport`, the Roster Management grid)
Touches: `team`, `person_team`, `team_manager`, `person`
Verify: `test/controllers/teams_positions/membership_report_controller_test.rb`
Trap: Only active teams are listed; `set_team` sends an inactive team's roster back to the index with a notice, not a 404.
Trap: `apply_filters` adds `select(:id, :title, :type)` only where rows load — `select` appends, so narrowing the base `active` scope makes the `active.select(:id)` subquery multi-column, which MySQL rejects.

### Position Grants
Reach it: `GET /teams-positions/position-grants` → Teams & Positions › Teams & Positions Menu › Position Grants; roster `GET /teams-positions/position-grants/:position_id` (CSV with `.csv`)
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/teams_positions/position_grants_controller.rb` (`index`, `show` html + csv via `CsvExportConcern`)
Owner: inline in controller: `PersonPosition`, `Person`, `Position` (the old People By Position report)
Touches: `position`, `person_position`, `person`
Verify: `test/controllers/teams_positions/position_grants_controller_test.rb`
Trap: `status_param` defaults to `STATUS_RANGERING`, not "all", so a link that drops `status=` silently narrows the roster — `current_index_params` always emits it.
Trap: The "missing" pools (`unassigned_pool`) ignore the status filter on purpose and test `new_user_eligible` before `all_rangers`, so a position with both flags uses the wider non-excluded pool.

### Special Teams Hours
Reach it: `GET /teams-positions/special-teams-hours` → Teams & Positions › Teams & Positions Menu › Special Teams Hours (CSV with `.csv`)
Gate: `ADMIN`, `EVENT_MANAGEMENT`
Controller: `app/controllers/teams_positions/special_teams_hours_controller.rb` (`index` html + csv via `CsvExportConcern`)
Owner: `SpecialTeamsHoursReport` (`app/lib/reports/special_teams_hours_report.rb`), `SpecialTeamsHoursForm` (`app/forms/special_teams_hours_form.rb`), `EventYearSpan` (`app/lib/event_year_span.rb`)
Touches: `position`, `team`, `timesheet`, `slot`, `person_slot`, `person_position`, `person`
Verify: `test/controllers/teams_positions/special_teams_hours_controller_test.rb`, `test/lib/reports/special_teams_hours_report_test.rb`, `test/lib/event_year_span_test.rb`, `test/lib/position_groups_test.rb`
Trap: Positions travel as top-level `ids[]` (`SpecialTeamsHoursForm::IDS_PARAM`), not in `report[...]`, so a Select All URL fits nginx's 8 KB request line — don't move them into `scoped_params`.
Trap: `SpecialTeamsHoursReport.signups_by_person_year` counts only ended shifts (`where(ends: ..Current.time)`); the page stops at `ROW_LIMIT` (500) but the CSV is uncapped, adding Name and Email only for `Current.can_view_pii?` / `can_view_email?`.

### Roster Management
Reach it: `GET /teams-positions/roster-management` → Teams & Positions › Teams & Positions Menu › Roster Management; team grid `GET /teams-positions/roster-management/:team_id`; preview `POST /teams-positions/roster-management/:team_id/preview`; apply `POST /teams-positions/roster-management/:team_id/apply`
Gate: `Team.manageable_by?` — `ADMIN`, `EVENT_MANAGEMENT` or `TECH_NINJA`, plus a `team_manager` row for that team unless `ADMIN`/`TECH_NINJA`
Controller: `app/controllers/teams_positions/roster_management_controller.rb` (`index`, `show`, `preview`, `apply`)
Owner: `TeamMembershipReport` (`app/lib/reports/team_membership_report.rb`), `RosterAction` (`app/lib/roster_action.rb`), `Team.manageable_by` (`app/models/team.rb`)
Touches: `team`, `team_manager`, `team_role`, `position`, `position_role`, `role`, `person` (w), `timesheet`, `trainee_status`, `trainer_status`, `person_team` (w), `person_team_log` (w), `person_position` (w), `person_position_log` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/roster_management_controller_test.rb`, `test/lib/reports/team_membership_report_test.rb`
Trap: No `authorize_role`: the unconditional `require_roster_manager` and the `Team.manageable_by` scope in `set_team` are the whole gate, so Event Management alone opens nothing without a `team_manager` row.
Trap: `PersonTeam.remove_person` and `PersonPosition.remove_ids_from_person` lack the Admin/Tech Ninja guard that `add_person` and `add_ids_to_person` carry — a new remover must reapply `RosterManagementController#guarded_roles_lacked`.

### Team Resources
Reach it: `GET /teams-positions/team-resources` → Teams & Positions › Teams & Positions Menu › Team Resources; read `GET /teams-positions/team-resources/:team_id`; editor `GET /teams-positions/team-resources/:team_id/edit`; save `POST`/`PATCH /teams-positions/team-resources/:team_id`; delete `DELETE /teams-positions/team-resources/:team_id`
Gate: `Team.resource_manageable_by?` — first `EVENT_MANAGEMENT` or `VEHICLE_INFO_UPDATE` (`Team::RESOURCE_ACCESS_ROLES`, of everyone, Admins included: upstream's Ember `ops` route), then `ADMIN` (every team) or `TEAM_RESOURCE_MANAGEMENT` (132, granted through `team_role`) plus a `team_manager` row for that team; Tech Ninja adds nothing. Reading and writing are one permission here
Controller: `app/controllers/teams_positions/team_resources_controller.rb` (`index`, `show`, concern hooks), `app/controllers/concerns/resource_document_crud_concern.rb` (`edit`, `create`, `update`, `destroy`)
Owner: `ResourceDocumentCrudConcern`, `Document.resource_tag` / `Document.listed_by_pointer` (`app/models/document.rb`), `Team.resource_manageable_by` and `Team#build_resource_tag` (`app/models/team.rb`); the editor and the read page's `_document` partial are shared with Trainer Resources in `app/views/common/resource_documents/`
Touches: `document` (w), `team` (w), `team_manager`, `action_logs` (w)
Verify: `test/controllers/teams_positions/team_resources_controller_test.rb`, `test/models/team_test.rb`, `test/models/document_test.rb`
Trap: A team's `resource_tag` is typed in Team Records, so it is followed only through `Document.resource_tag`: stripped, never a `Document::*_TAG` document or a `bookmark-` page, never a tag no document could have. A pointer that fails gives way to `build_resource_tag` on the first save (which repoints the team), and the read page says so. Look tags up through it, or `Document.listed_by_pointer` for a list: the column compares without case and trailing spaces, a Ruby hash does not.
Trap: `include ResourceDocumentCrudConcern` sits below the controller's gates only so their messages answer first; `resource_entity` is a memoized lookup, so the concern's own gate works wherever it runs. An Admin who asks for a missing team is sent to the index ("That team no longer exists."); anyone else is not told whether it exists.
Trap: The index looks documents up with `Document::LIST_COLUMNS` — never select `document.body` on a list: the Mentor Team document runs to megabytes (dev, 2026-10-26).
Trap: `Team.resource_manageable_by` is not the roster rule (`Team.manageable_by` admits Tech Ninja to every team); members read their team's document nowhere on `main` yet — upstream showed it on Teams & Positions and me/agreements — so the editor says only managers and Admins can read it.

### Bulk Position Grant / Revoke
Reach it: `GET /teams-positions/bulk-positions` → Teams & Positions › Teams & Positions Menu › Bulk Position Grant / Revoke; preview `POST /teams-positions/bulk-positions/preview`; apply `POST /teams-positions/bulk-positions`; back to edit `POST /teams-positions/bulk-positions/edit`
Gate: `Team.manageable_by?` — `ADMIN`, `EVENT_MANAGEMENT` or `TECH_NINJA`, plus a `team_manager` row unless `ADMIN`/`TECH_NINJA`
Controller: `app/controllers/teams_positions/bulk_positions_controller.rb` (`index`, `preview`, `apply`)
Owner: `TeamManagement::BulkPositionChange` (`app/lib/team_management/bulk_position_change.rb`), `PersonPosition.add_ids_to_person` / `remove_ids_from_person` (`app/models/person_position.rb`)
Touches: `position`, `position_role`, `team`, `team_manager`, `person` (w), `person_position` (w), `person_position_log` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/bulk_positions_controller_test.rb`, `test/lib/team_management/bulk_position_change_test.rb`
Trap: A position whose `position_role` carries Admin or Tech Ninja is never granted here, even by an Admin (`refuse_guarded_grant`), and only a holder of that role may revoke it (`reject_guarded`).
Trap: This page and Bulk Team Grant / Revoke duplicate each other on purpose and stay off `BulkUploadPage` (ruling in `app/controllers/concerns/bulk_upload_page.rb`) — don't fold either into a shared base class or that concern in an unrelated change.

### Bulk Team Grant / Revoke
Reach it: `GET /teams-positions/bulk-teams` → Teams & Positions › Teams & Positions Menu › Bulk Team Grant / Revoke; preview `POST /teams-positions/bulk-teams/preview`; apply `POST /teams-positions/bulk-teams`; back to edit `POST /teams-positions/bulk-teams/edit`
Gate: `Team.manageable_by?` — `ADMIN`, `EVENT_MANAGEMENT` or `TECH_NINJA`, plus a `team_manager` row unless `ADMIN`/`TECH_NINJA`
Controller: `app/controllers/teams_positions/bulk_teams_controller.rb` (`index`, `preview`, `apply`)
Owner: `TeamManagement::BulkTeamChange` (`app/lib/team_management/bulk_team_change.rb`), `PersonTeam.add_person` / `remove_person` (`app/models/person_team.rb`), `PersonPosition.add_ids_to_person` / `remove_ids_from_person` (`app/models/person_position.rb`)
Touches: `team`, `team_role`, `team_manager`, `position`, `position_role`, `role`, `person` (w), `person_team` (w), `person_team_log` (w), `person_position` (w), `person_position_log` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/bulk_teams_controller_test.rb`, `test/lib/team_management/bulk_team_change_test.rb`
Trap: A grant adds only the team's `all_members` Recommended positions but a revoke strips `all_members` plus `optional` (`TeamMembershipReport::REVOCABLE_CATEGORIES`) — ask `BulkTeamChange#moved_positions`, don't respell the categories.
Trap: `BulkTeamChange#build_entries` loads only `id`, `callsign`, `callsign_normalized` and `status` from `person`, so any other `Entry#person` attribute raises `MissingAttributeError` — add the column to that `select`.

### Bulk Membership History
Reach it: `GET /teams-positions/bulk-membership-history` → Teams & Positions › Teams & Positions Menu › Bulk Membership History; preview `POST /teams-positions/bulk-membership-history/preview`; apply `POST /teams-positions/bulk-membership-history`; back to edit `POST /teams-positions/bulk-membership-history/edit`
Gate: `ADMIN`, or any `team_manager` row (`is_admin? || is_team_manager?`)
Controller: `app/controllers/teams_positions/bulk_membership_history_controller.rb` (`index`; `preview`, `apply` from `BulkUploadPage` in `app/controllers/concerns/bulk_upload_page.rb`; views `app/views/common/bulk_upload/`)
Owner: `BulkUpload::MembershipHistoryHandler` (`app/lib/bulk_upload/membership_history_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`)
Touches: `team`, `team_manager`, `person`, `person_team_log` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/bulk_membership_history_controller_test.rb`
Trap: It writes only `person_team_log`, never `person_team`, so today's roster is unchanged (Bulk Team Grant / Revoke owns it), and `MembershipHistoryHandler#decide` refuses any date not exactly `YYYY-MM-DD` (`DATE_PATTERN`).
Trap: The gate is wider than the sibling bulk pages' on purpose (no Event Management), and `team_scope` gives every team only to an Admin — not `Team.manages_every_team?`, which also admits Tech Ninja and splits gate from scope.

### Position Sanity Checker
Reach it: `GET /teams-positions/position-sanity-checker` → Teams & Positions › Administration › Position Sanity Checker; one check `GET /teams-positions/position-sanity-checker/:check`; repair `POST /teams-positions/position-sanity-checker/:check/repair`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/teams_positions/position_sanity_checker_controller.rb` (`index`, `check`, `repair`)
Owner: `PositionSanityCheck` (`app/lib/position_sanity_check.rb`), `PositionSanityCheck::Base` (`app/lib/position_sanity_check/base.rb`), one class per check in `app/lib/position_sanity_check/`
Touches: `person` (w), `position`, `team`, `position_role`, `team_role`, `timesheet`, `person_mentor`, `person_position` (w), `person_team` (w), `person_role` (w), `person_position_log` (w), `person_team_log` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/teams_positions/position_sanity_checker_controller_test.rb`
Trap: `PositionSanityCheck::Base.repair` accepts only finding keys and re-runs `findings` to decide what to grant or revoke — never act on browser-posted position or team ids (a crafted POST could grant anything).
Trap: Checks are class-level singletons (`class << self`), so an instance-variable memo leaks between requests — pass sets down as `ShinyPennies.findings` does; register a new check as a class plus a `PositionSanityCheck::CHECKS` row.

## Volunteer Coordinators

Controllers subclass `ApplicationController`, use `layout "vc"` and one `authorize_role` with `ADMIN`; `Menus::VC` (`app/lib/menus.rb`) has no category gate, so each item's `visible_if` repeats its controller's roles (`test/lib/vc_menu_test.rb` enforces). Year: `?year=` via `ApplicationController#setup_year` (default: present year). `app/lib/reports/` is an autoload root, so owners there are top-level (`SpigotFlowReport`, not `Reports::SpigotFlowReport`).

### VC › Applications (Prospective Applications)
Reach it: `GET /vc/applications` (html + csv) → Volunteer Coordinator › Applications › Applications; search `GET /vc/applications/search`
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/applications_controller.rb` (`index` html + csv via `CsvExportConcern`, `search`)
Owner: `ProspectiveApplication` (`app/models/prospective_application.rb`), `Vc::ApplicationFilterForm` (`app/forms/vc/application_filter_form.rb`) (not `Person::ApplicationsController`, the read-only one-person list)
Touches: `prospective_application`, `person`, `person_position`
Verify: `test/controllers/vc/applications_controller_test.rb`, `test/models/prospective_application_test.rb`, `test/lib/vc_menu_test.rb`
Trap: `Vc::ApplicationFilterForm` defaults `status` to `pending`, so bare `/vc/applications` and its CSV list only the viewed year's "Awaiting Review" rows — pass `filter[status]=all` for the whole year.
Trap: `volunteer_coordinators` (the "Assigned To" filter and Assign dialog) lists Volunteer Coordinator position holders via `PersonPosition.retrieve_grants(Position::VOLUNTEER_COORDINATOR)`, not `VC` role holders.

### VC › Application review (Application A-<id>)
Reach it: `GET /vc/applications/:id` → Edit on Prospective Applications; Application Search and Person › Applications via `Vc::ApplicationsHelper#application_link`; status `POST /vc/applications/:id/status`; edit `GET /vc/applications/:id/edit-details` / `GET /vc/applications/:id/edit-personal-info`, saved by `PATCH /vc/applications/:id`; AI handle extract `POST /vc/applications/:id/extract_handles`; dialogs `GET /vc/applications/:id/dialog/:dialog`; email `POST /vc/applications/:id/send_email`; notes `POST /vc/applications/:application_id/notes`
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/applications_controller.rb` (`show`, `edit_details`, `edit_personal_info`, `dialog`, `update`, `destroy`, `status`, `problem_review`, `preview_email`, `send_email`, `extract_handles`), `app/controllers/vc/application_notes_controller.rb` (`create`, `update`, `destroy`)
Owner: `ProspectiveApplication` (`app/models/prospective_application.rb`), `Vc::ReviewStages` (`app/lib/vc/review_stages.rb`), `ProspectiveApplicationStatusMail` (`app/lib/prospective_application_status_mail.rb`)
Touches: `prospective_application` (w), `prospective_application_log` (w), `prospective_application_note` (w), `mail_log` (w), `action_logs` (w), `person`, `person_position`, `handle_reservation`, `setting`
Verify: `test/controllers/vc/applications_controller_test.rb`, `test/models/prospective_application_test.rb`, `test/lib/vc/review_stages_test.rb`, `test/lib/prospective_application_status_mail_test.rb`, `test/helpers/vc/applications_helper_test.rb`, `test/mailers/prospective_application_mailer_test.rb`
Trap: The "Adjust Status" dialog PATCHes `update`, an emergency path with no email or rejected-handle record — real status changes POST `status` (`ProspectiveApplicationStatusMail.execute`; `ProspectiveApplication#record_rejections` for More Handles).
Trap: the applicant mailers' `mail_log` rows come from `ApplicationMailer#record_mail_log` as the email is delivered, under the application (`@prospective_application_id`) and the signed-in VC; `ProspectiveApplicationStatusMail.deliver_and_log` writes only the "emailed" `prospective_application_log` entry. It keeps `deliver_now`, and the entry reads the delivered message's subject. The mail log no longer needs it: a queued email gets its rows too, under SES's id through `:ses_mail`, given `.with(sender_id:)` to keep the VC (see Transactional mail), so nothing has to switch either way. There is one row per To address, so RRN check mail to a several-address `RRN_EMAIL`, or applicant mail while `PROSPECTIVE_APPLICATION_MAIL_SANDBOX` lists several, shows in the Mail Log section once per address. While production sends by SMTP (until `RANGER_CLUBHOUSE_SES_MAIL_LIVE`) the rows keep the mail gem's own Message-ID, so a bounce report never stamps them (see MailLog).
Trap: every personal-info save (`save(context: :personal_info)`) holds the email to the address rule (`EmailAddresses.sendable?`, said as `Person::EMAIL_MESSAGE`), changed or not, so an application imported with an address the rule refuses (Import saves without the context) must have its email fixed before anything else on that form saves. Create Prospectives would refuse that address anyway.

### Application Import (Salesforce Application Import)
Reach it: `GET /vc/application-import` → Volunteer Coordinator › Applications › Application Import; preview `POST /vc/application-import/preview`; commit `POST /vc/application-import/commit`
Gate: `ADMIN`, `SALESFORCE_IMPORT`
Controller: `app/controllers/vc/application_import_controller.rb` (`index`, `preview`, `commit`; both POSTs re-render `index` at 422)
Owner: `ProspectiveApplicationImport` (`app/lib/prospective_application_import.rb`), `Salesforce` (`app/lib/salesforce.rb`)
Touches: `prospective_application` (w), `prospective_application_log` (w), `prospective_application_note` (w), `action_logs` (w), `error_logs` (w), `person`, `setting`
Verify: `test/controllers/vc/application_import_controller_test.rb`, `test/lib/prospective_application_import_test.rb`, `test/lib/salesforce_test.rb`
Trap: Preview is not offline: it runs the same SOQL pull through `Salesforce.connector`, hitting real Salesforce unless `Rails.env.development?` and `ENV["SF_MOCK_DATA"]` select `Salesforce::MockConnector`.
Trap: `ProspectiveApplicationImport#import_application` always sets `year = Current.year`, ignoring `VC_Event_Year__c`, and dedupes only in app code on (present year, `salesforce_name`) via `existing_applications_by_name` — no unique index.

### Create Prospectives (Create Prospective Accounts)
Reach it: `GET /vc/create-prospectives` → Volunteer Coordinator › Applications › Create Prospectives; preview `POST /vc/create-prospectives/preview`; commit `POST /vc/create-prospectives/commit`
Gate: `ADMIN`, `SALESFORCE_IMPORT`
Controller: `app/controllers/vc/create_prospectives_controller.rb` (`index`, `preview`, `commit`; `load_settings` reads `SEND_WELCOME_EMAIL` and `SF_ENABLE_WRITEBACKS`)
Owner: `ProspectiveClubhouseAccountFromApplication` (`app/lib/prospective_clubhouse_account_from_application.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`), `Salesforce` (`app/lib/salesforce.rb`)
Touches: `prospective_application` (w), `person` (w), `person_fka` (w), `person_status` (w), `person_role` (w), `person_position` (w), `person_position_log` (w), `person_intake_note` (w), `email_history` (w), `action_logs` (w), `error_logs` (w), `prospective_application_note`, `handle_reservation`, `setting`
Verify: `test/controllers/vc/create_prospectives_controller_test.rb`, `test/lib/prospective_clubhouse_account_from_application_test.rb`, `test/lib/salesforce_test.rb`, `test/lib/person_status_management_test.rb`
Trap: `ProspectiveClubhouseAccountFromApplication.execute` contacts Salesforce only on commit with `SF_ENABLE_WRITEBACKS` on; `sync_salesforce` writes `Ranger__c` in each account's transaction, so a failed writeback rolls that account back.
Trap: `ProspectiveApplication.retrieve_approved` returns only the present year's `approved` rows, so an earlier year's approved application never reaches preview or commit.
Trap: preview and commit both build the account the commit would save (`build_account`) and run `Person#valid?` on it (`verify_account`), so the page's "exact same checks" promise holds, column limits apart. An application `Person` refuses (a phone `PhoneFormatter` can't read, an email the address rule `EmailAddresses.sendable?` refuses, a name over 25 characters, or a converted account's own stored value) ends `invalid`, listed under Missing or Invalid Fields with the application's field named ("Phone must be ...", or "Existing account #id: ..." for the account's own value), never `create-failed`; a commit writes no `ErrorLog` row for it and the application stays approved. A callsign `:taken` is set aside (`detect_exact_callsign_holder`) only when no account but the one being reassigned holds the exact callsign, because neither `callsign_normalized` nor `bpguid` is unique; another exact holder is a callsign conflict naming that holder. Column limits tighter than `Person`'s validations (`street1`, `city`, `state`, `zip`, `country`: 191 against 128, 50, 128, 10 and 25) still preview ready and end `create-failed` with "SQL Error: ...".

### BPGUID Lookup (Link a Burner Profile)
Reach it: `GET /vc/bpguid` → Volunteer Coordinator › VC Menu › BPGUID Lookup; callsign `GET /vc/bpguid?callsign=` (302 to the person); person `GET /vc/bpguid/:person_id`; search `POST /vc/bpguid(/:person_id)/search` (answers two turbo-stream updates at 200); link `PATCH /vc/bpguid/:person_id` (303 back on success, one turbo-stream update at 200 on a refusal)
Gate: `ADMIN`, `VC`; the search refused on the Groundhog Day Server (`prevent_if_ghd_server`)
Controller: `app/controllers/vc/bpguid_controller.rb` (`index`, `show`, `search`, `update`)
Owner: `SalesforceContactSearch` (`app/lib/salesforce_contact_search.rb`; the search, the floor that refuses a broad one before signing in, and the signed row link `link_token`/`verified_link`), `Salesforce` (`app/lib/salesforce.rb`, `sosl_escape`), `Vc::BpguidController#find_by_callsign` (the exact callsign, then `Person.retrieve_by_callsign` in `app/models/person.rb`) (not `Person::ExternalIdsController`, the Admin-only free-text edit of the same column)
Touches: `person` (w), `action_logs` (w), `error_logs` (w), `person_photo`, `active_storage_attachments`, `active_storage_blobs`, `setting`
Verify: `test/controllers/vc/bpguid_controller_test.rb`, `test/lib/salesforce_contact_search_test.rb`, `test/lib/salesforce_test.rb`, `test/lib/salesforce/mock_connector_test.rb`, `test/lib/vc_menu_test.rb`, `test/system/vc/bpguid_test.rb`
Trap: Both forms are on every page (`show` renders `index`), so a search can run with no person shown — it then has no Actions column and no buttons (`SalesforceContactSearch#linkable?` is false without a person) and its Action Log row has no target.
Trap: Not offline in development: `Salesforce.connector` reaches the live org with the dev database's production credentials unless `Rails.env.development?` and `ENV["SF_MOCK_DATA"]` select `Salesforce::MockConnector` — the Salesforce Accounts heading then shows a Mock Data badge; no badge, no Search.
Trap: Nothing answers 422 on purpose — `RequestLogger` keeps a 422's params and whole page in `request_log`, and this page holds a person's address and phones plus other people's Salesforce Accounts; don't "fix" `search` to 422 or `update` to re-render.
Trap: `update` never reads a typed `bpguid` — it writes only the value in the row's signed `link_token` (person, contact BPGUID, the person's BPGUID when the row rendered; 2 hours), and refuses a forged, expired, other-person or stale one; don't add a `bpguid` param "for convenience".
Trap: `update` redirects with `status: :see_other` on success — the row button is a Turbo method link sending a real PATCH, and fetch follows a 302 by repeating the PATCH; a refusal answers 200 with a turbo stream into `#vc-bpguid-notice` so the results stay, and its `scroll-to-element` marker brings that slot (above the table) into view.
Trap: A PATCH that meets an inherited 302 (sign-in, role, unknown person) is repeated against a GET-only path and ends on the 404 page — accepted, since only a stale tab or a hand-made request gets there.
Trap: `person.bpguid` has no unique index, yet Create Prospectives and `ProspectiveApplication#bpguid_person` treat it as an identity key — `update` refuses a BPGUID another account holds (case-insensitive, by collation).
Trap: The link is audited only by the automatic `person-update` row (`audit_reason` labels it), which only Admin › Action Logs shows; `update_column` would write none, and `update` would run every Person validation and rewrite legacy phones.
Trap: Searches are org-wide (any Contact the integration user can read, not only Rangers), and `sosl_escape` keeps `*` and leaves `OR` an operator, so `SalesforceContactSearch#refusal` refuses before signing in: over 80 characters, a word with `*` and fewer than 3 other characters (`sm*`; `smi*` and `*tone` pass), or a standalone `OR` in any case. Each search, refused or not, writes one `salesforce-contact-search` Action Log row with the text, targeted at the person.
Trap: The owner's FIND names one object with no WHERE or ORDER BY, so Salesforce stops at 250 contacts without saying so; the page warns when 250 come back, in a callout and in `summary`, the live region's sentence (the callout arrives already holding its words, so it is not read out).
Trap: `Salesforce::MockConnector#sosl_search` answers a statement holding `RETURNING Contact (` with its own contacts, filtered by the unescaped term; any other FIND keeps the Salesforce Query page's mixed list, which `mock_connector_test.rb` pins.
Trap: The callsign lookup tries the exact callsign first because `Person.retrieve_by_callsign` matches the normalized callsign, which is not unique, and it skips that fallback when the text normalizes to `""` (punctuation only); never `Person.by_callsign`, whose `normalize_callsign` is defined nowhere.
Trap: The card resolves a country stored by name to its code (`CountryStateHelper::COUNTRY_LABELS.key`) before `country_has_states?`, so it shows the state for "United States" where Person › `_contact_details` hides it; a blank country prints nothing, never `COUNTRY_LABELS[""]` ("Choose Country").

### Handle Checker
Reach it: `GET /vc/handle-checker` → Volunteer Coordinator › VC Menu › Handle Checker
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/handle_checker_controller.rb` (`index`)
Owner: `HandleChecker` (`app/lib/handle_checker.rb`), `Vc::HandleCheckerForm` (`app/forms/vc/handle_checker_form.rb`)
Touches: `person`, `handle_reservation`
Verify: `test/controllers/vc/handle_checker_controller_test.rb`, `test/lib/handle_checker_test.rb`, `test/helpers/vc/handle_checker_helper_test.rb`
Trap: `HandleChecker#check` runs enabled rules against the whole pool and filters only in `show?` (a vintage callsign reports even with its status type unchecked, unless `include_vintage` is off) — narrowing the pool changes results.
Trap: `HandleChecker#rules` builds only the enabled rules on purpose: `Vc::HandleCheckerForm` re-checks up to 25 history names per GET, and the eye-rhyme rules' per-syllable index of every handle is most of a check's cost.

### Photo Review
Reach it: `GET /vc/photos-review` → Volunteer Coordinator › VC Menu › Photo Review; approve `PATCH /vc/photos-review/:id/approve`; reject `PATCH /vc/photos-review/:id/reject`; re-crop `GET /vc/photos-review/:id/crop` + `PATCH /vc/photos-review/:id/crop`
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/photos_review_controller.rb` (`index`, `approve`, `reject_dialog`, `reject`, `reject_preview`, `info`; `crop`, `crop_save`, `destroy` from `PhotoUploadConcern` in `app/controllers/concerns/photo_upload_concern.rb`)
Owner: `PersonPhoto` (`app/models/person_photo.rb`), `PhotoUploadConcern` (`app/controllers/concerns/photo_upload_concern.rb`), `PhotoRejectedMailer` (`app/mailers/photo_rejected_mailer.rb`)
Touches: `person_photo` (w), `active_storage_attachments` (w), `active_storage_blobs` (w), `mail_log` (w), `action_logs` (w), `person`
Verify: `test/controllers/vc/photos_review_controller_test.rb`, `test/models/person_photo_crop_test.rb`
Trap: `PersonPhoto#cleanup_photos` only sets the person's other `approved` photos to `archived`, keeping rejected and pending rows — its comment wrongly says approval deletes every other photo.
Trap: The controller's `set_person_photo` override (unscoped `PersonPhoto.find`, re-registered `except: :index`) must stay: the concern's version calls `subject_person`, which here reads `@person_photo`, breaking `crop`, `crop_save` and `destroy`.

### VC › Photos (Clubhouse Photos)
Reach it: `GET /vc/photos` → Volunteer Coordinator › VC Menu › Photos
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/photos_controller.rb` (`index`)
Owner: `PersonPhoto.find_for_query` (`app/models/person_photo.rb`)
Touches: `person_photo`, `person`, `active_storage_attachments`, `active_storage_blobs`
Verify: `test/controllers/vc/photos_controller_test.rb`, `test/lib/vc_menu_test.rb`
Trap: Thumbnails, approved ones included, open `Vc::PhotosReviewController#info` (`vc_photos_review_info_path`), so scoping that controller's `set_person_photo` to submitted photos breaks this page.
Trap: `find_for_query` returns `{ person_photo:, pagy: }` and the page draws `ui_pager` above and below the table (2026-10-26, SMS Management issue 18). A page past the last is not held to the last: it is an empty table under "Page 99 of 1", and Previous goes to page 98, as before Pagy. Photo Review reads the same Pagy's count.

### Reserved Handles
Reach it: `GET /vc/reserved-handles` → Volunteer Coordinator › VC Menu › Reserved Handles; create `POST /vc/reserved-handles`; expire `POST /vc/reserved-handles/expire`; bulk upload `GET /vc/reserved-handles/upload`; verify/commit `POST /vc/reserved-handles/upload`
Gate: `ADMIN`, `VC`, `EDIT_HANDLE_RESERVATIONS` to view; writes need `authorize_ability :manage_reserved_handles` (`ADMIN`, `EDIT_HANDLE_RESERVATIONS`; a VC-only reader is redirected to the index)
Controller: `app/controllers/vc/reserved_handles_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `expire`, `upload`, `upload_run`)
Owner: `HandleReservation` (`app/models/handle_reservation.rb`), `HandleReservationUpload` (`app/lib/handle_reservation_upload.rb`), `Vc::ReservedHandleUploadForm` (`app/forms/vc/reserved_handle_upload_form.rb`)
Touches: `handle_reservation` (w), `action_logs` (w)
Verify: `test/controllers/vc/reserved_handles_controller_test.rb`, `test/lib/handle_reservation_upload_test.rb`, `test/models/handle_reservation_test.rb`, `test/jobs/expire_handle_reservations_job_test.rb`
Trap: `HandleReservation.expire_handles!` destroys rows, not flags them; `ExpireHandleReservationsJob` runs it daily at 5am in production (`config/recurring.yml`), so "Expired" and Delete Expired Handles normally find only rows lapsed since.
Trap: Commit in `app/views/vc/reserved_handles/upload.html.erb` is a second hidden-field form (each `id: nil`) re-posting verified values — merged into the textarea form it commits post-verify edits; without `id: nil` Turbo empties it.

### Spigot Flow Report
Reach it: `GET /vc/spigot-flow-report` → Volunteer Coordinator › VC Menu › Spigot Flow Report
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/spigot_flow_report_controller.rb` (`index` html + csv)
Owner: `SpigotFlowReport` (`app/lib/reports/spigot_flow_report.rb`)
Touches: `prospective_application`, `person_status`, `person`, `action_logs`, `person_photo`, `person_online_course`, `slot`, `person_slot`, `trainee_status`
Verify: `test/controllers/vc/spigot_flow_report_controller_test.rb`, `test/lib/reports/spigot_flow_report_test.rb`
Trap: The cohort source switches at `SpigotFlowReport::SALESFORCE_CUTOVER_YEAR` (2025): before, `person_status` (Imported = Created); from 2025, Imported = every `prospective_application` created that year, Created = status `created` only.
Trap: The view hard-codes `min_year: 2010` but the controller keeps the 1998 `year_floor`, so `?year=2005` passes `setup_year` — set `self.year_floor` and pass `min_year: year_floor`, as `Vc::ThankYouCardsController` does.

### VC › Unified Flagging
Reach it: `GET /vc/unified-flagging` → Volunteer Coordinator › VC Menu › Unified Flagging; `?person=:id` selects the line whose history the review pane shows (`?section=` narrows to one group); detail frame `GET /vc/unified-flagging/:person_id`; notes `POST /person/:person_id/unified-flagging/notes`
Gate: `ADMIN`, `VC`, `INTAKE`; a note write also needs that team's role (`Person::IntakeNotesController#check_intake_permissions!`)
Controller: `app/controllers/vc/unified_flagging_controller.rb` (`index`, `detail` from `UnifiedFlaggingConcern` in `app/controllers/concerns/unified_flagging_concern.rb`), `app/controllers/person/intake_notes_controller.rb` (note CRUD, `origin: "vc"`)
Owner: `Intake` (`app/lib/intake.rb`), `UnifiedFlaggingConcern` (`app/controllers/concerns/unified_flagging_concern.rb`), `IntakeNoteForm` (`app/forms/intake_note_form.rb`)
Touches: `person_status`, `person`, `person_fka`, `person_intake` (w), `person_intake_note` (w), `action_logs` (w), `person_mentor`, `slot`, `person_slot`, `trainee_status`, `trainee_note`, `trainer_status`, `timesheet`
Verify: `test/controllers/vc/unified_flagging_controller_test.rb`, `test/system/vc/unified_flagging_review_test.rb` (the pane swap, focus kept on the line, Back, the phone placement and scroll, the selected line's mark on a hand-typed URL), `test/lib/intake_test.rb`, `test/controllers/person/intake_notes_controller_test.rb`, `test/controllers/training/unified_flagging_controller_test.rb`
Trap: `Intake.retrieve_all_for_year` defaults to `only_flagged: true` (adverse marks only); its roster is the viewed year's Prospective/Alpha `person_status` rows (no fixtures) — tests call `place_in_pipeline` (`test/support/intake_test_helper.rb`).
Trap: `Person::IntakeNotesController#build_form` falls back to `Current.year`, so add-note links need `year: @year` and the `origin_year` token (see `app/views/common/unified_flagging/_note_buttons.html.erb`) or past-year notes land in the present year.
Trap: `UnifiedFlaggingConcern#review_selection` selects only among the rows shown, so a `?person=` the filters hide shows the pane's empty state, not that person's history.

### VC › Maintenance (Volunteer Coordinator Maintenance Functions)
Reach it: `GET /vc/maintenance` → Volunteer Coordinator › Post-Event › Maintenance; preview `GET /vc/maintenance/preview-pnvs` / `GET /vc/maintenance/preview-past-prospectives`; commit `POST /vc/maintenance/reset-pnvs` / `POST /vc/maintenance/reset-past-prospectives`
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/maintenance_controller.rb` (`index`, `preview_pnvs`, `preview_past_prospectives`, `reset_pnvs`, `reset_past_prospectives`)
Owner: inline in controller (`reset_callsigns`) — `Person#reset_callsign` (`app/models/person.rb`), `PersonStatusManagement` (`app/lib/person_status_management.rb`)
Touches: `person` (w), `person_fka` (w), `person_status` (w), `person_role` (w), `person_position` (w), `person_position_log` (w), `person_team` (w), `person_team_log` (w), `person_slot` (w), `slot` (w), `action_logs` (w)
Verify: `test/controllers/vc/maintenance_controller_test.rb`, `test/lib/person_status_management_test.rb`
Trap: `reset_callsigns` must call `person.reset_callsign(taken:)` before flipping status: B and (NR) suffixes come from the old status, and the resulting `callsign_changed?` stops `Person#handle_past_prospective_status` making a second callsign.
Trap: `reset_pnvs` and `reset_past_prospectives` answer success with 422 on purpose: Turbo drops a 200 form response, and disabling Turbo on the form would also lose the confirmation modal.

### Shiny Penny Report
Reach it: `GET /vc/shiny-penny-report` → Volunteer Coordinator › Post-Event › Shiny Penny Report
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/shiny_penny_report_controller.rb` (`index` html + csv)
Owner: `ShinyPennyReport` (`app/lib/reports/shiny_penny_report.rb`)
Touches: `timesheet`, `person_status`, `person`
Verify: `test/controllers/vc/shiny_penny_report_controller_test.rb`, `test/lib/reports/shiny_penny_report_test.rb`
Trap: The view hard-codes `min_year: 2010` but the controller keeps the 1998 `year_floor`, so `setup_year` accepts years the selector can't show — pair `self.year_floor` with `min_year: year_floor`, like `Vc::ThankYouCardsController`.
Trap: `ShinyPennyReport.execute` filters `YEAR(on_duty) = ?` (and `YEAR(created_at) = ?` on `person_status`), so the `timesheet` `(position_id, on_duty)` index can't range-scan — use `Timesheet.for_year` / `where_year`, not a `Time.zone` range (an hour off).

### Thank You Cards
Reach it: `GET /vc/thank-you-cards` → Volunteer Coordinator › Post-Event › Thank You Cards
Gate: `ADMIN`, `VC`
Controller: `app/controllers/vc/thank_you_cards_controller.rb` (`index` html + csv; `year_floor = 2008`)
Owner: `ThankYouCardsReport` (`app/lib/reports/thank_you_cards_report.rb`)
Touches: `person`, `timesheet`
Verify: `test/controllers/vc/thank_you_cards_controller_test.rb`, `test/lib/reports/thank_you_cards_report_test.rb`, `test/helpers/vc/thank_you_cards_helper_test.rb`
Trap: `ThankYouCardsReport.execute` selects only `ThankYouCardsReport::COLUMNS`; reading any other `Person` attribute in the view, `Vc::ThankYouCardsHelper` or CSV raises `ActiveModel::MissingAttributeError` — add it to `COLUMNS` first.

## Ticketing

All but Bulk BMID Actions render `app/views/layouts/ticketing.html.erb` (`Menus::TICKETING`) under `authorize_role [ADMIN, EDIT_ACCESS_DOCS]`; none calls `setup_year` — reports and bulk tools use `Current.year`, Un-Submit Provisions `TicketingMaintenance.maintenance_year`, Ticketing Menu pages no year. Bulk pages share `BulkUploadPage`, `BulkUpload::Batch` and `app/views/common/bulk_upload/`: form → preview (writes nothing) → apply (re-decides every line); every POST answers 422.

### Access Document Summary
Reach it: `GET /ticketing/access-documents` → Ticketing › Ticketing Menu › Summary
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/access_documents_controller.rb` (`index`)
Owner: `TicketingManagement` (`app/lib/ticketing_management.rb`), `AccessDocumentSummaryRow` (`app/presenters/access_document_summary_row.rb`), `Ticketing::AccessDocumentsHelper` (`app/helpers/ticketing/access_documents_helper.rb`)
Touches: `access_document`, `person`, `setting`
Verify: `test/controllers/ticketing/access_documents_controller_test.rb`, `test/lib/ticketing_management_test.rb`, `test/presenters/access_document_summary_row_test.rb`
Trap: `TicketingManagement.retrieve_current_by_person` reads `AccessDocument::CURRENT_STATUSES` (submitted included) and drops deceased and dismissed holders — don't swap in upstream's `ACTIVE_STATUSES`, which hides submitted-only holders.
Trap: `TicketingManagement.access_date_problem` (no access date, one before the present year, or a day outside `TAS_SAPDateRange`) also marks TRS Export rows and leaves them out of select-all — loosening it changes what gets exported.

### Current Access Documents (records)
Reach it: `GET /ticketing/access-documents/records` → Ticketing › Ticketing Menu › Current Documents
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/access_documents_controller.rb` (`records`, html + csv)
Owner: `AccessDocument.find_for_query` (`app/models/access_document.rb`), `Ticketing::AccessDocumentsHelper#arrival_label` (`app/helpers/ticketing/access_documents_helper.rb`)
Touches: `access_document`, `person`
Verify: `test/controllers/ticketing/access_documents_controller_test.rb`
Trap: `AccessDocument.find_for_query` splits `type:` only when it is a String (an Array leaves `types` nil and queries `WHERE type IS NULL`), and with `include_person: true` returns a callsign-sorted Array, so nothing can be chained after it.
Trap: a blank `status:` in `find_for_query` excludes only used, cancelled and expired, keeping `turned_down` — `records_query` passes `AccessDocument::CURRENT_STATUSES` explicitly; keep it that way.

### Ticketing › Current Provisions
Reach it: `GET /ticketing/provisions` → Ticketing › Ticketing Menu › Provisions; `GET /ticketing/provisions/:id/edit`, `PATCH /ticketing/provisions/:id`, `DELETE /ticketing/provisions/:id`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/provisions_controller.rb` (`index` html + csv; `edit`, `update`, `destroy` via `app/controllers/concerns/provision_crud_concern.rb`)
Owner: `ProvisionCrudConcern` (`app/controllers/concerns/provision_crud_concern.rb`), `Provision.find_for_query` (`app/models/provision.rb`)
Touches: `provision` (w), `action_logs` (w), `person`
Verify: `test/controllers/ticketing/provisions_controller_test.rb`, `test/controllers/person/provisions_controller_test.rb`, `test/controllers/bmid/provisions_controller_test.rb`
Trap: `ProvisionCrudConcern` and `app/views/common/provisions/` are shared with `Person::ProvisionsController` and `Bmid::ProvisionsController` — edit/update/destroy/form changes hit all three; `new`/`create` aren't routed here (person pages make provisions).
Trap: `Provision.find_for_query` with `include_person: true` returns a callsign-sorted Array, not a relation — add a new filter as a query key (as `is_allocated:` did), never chained onto the result.

### TRS Export
Reach it: `GET /ticketing/trs-export` → Ticketing › Ticketing Menu › TRS Export; `POST /ticketing/trs-export/export`; `POST /ticketing/trs-export/mark-submitted`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/trs_export_controller.rb` (`index`, `export`, `mark_submitted`)
Owner: `TrsExport` (`app/lib/trs_export.rb`), `TicketingManagement` (`app/lib/ticketing_management.rb`)
Touches: `access_document` (w), `access_document_changes` (w), `action_logs` (w), `person`, `setting`
Verify: `test/controllers/ticketing/trs_export_controller_test.rb`, `test/lib/trs_export_test.rb`, `test/lib/ticketing_management_test.rb`
Trap: `TrsExport.export!` only stamps a comment (status stays claimed) and its CSV is a one-time data: URI in the 422 response — submit via the separate `mark_submitted` POST, where `TrsExport.mark_submitted!` acts on the posted claimed ids alone.
Trap: `TrsExport::FILTER_GROUPS` slugs and `NOTE_TYPE_LABELS` strings land in document comments, CSV filenames and the vendor's Notes column — keep them byte-identical, "WAP"/"SOWAP" included.

### Ticketing Statistics
Reach it: `GET /ticketing/statistics` → Ticketing › Ticketing Menu › Statistics
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/statistics_controller.rb` (`index`)
Owner: `TicketingStatistics` (`app/lib/ticketing_statistics.rb`)
Touches: `access_document`, `provision`
Verify: `test/controllers/ticketing/statistics_controller_test.rb`, `test/lib/ticketing_statistics_test.rb`
Trap: `people_counts`' unclaimed and banked counts exclude holders of a claimed document of any type (and, for unclaimed, a banked one), so a claimed gift ticket drops a person from "banked" — matches upstream; don't narrow `holders_of`.

### Claimed, Didn't Ranger (claimed_with_no_signups)
Reach it: `GET /ticketing/claimed-with-no-signups` → Ticketing › Reports › Claimed, Didn't Ranger
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/claimed_with_no_signups_controller.rb` (`index`, html + csv)
Owner: `ClaimedTicketsWithNoSignupsReport` (`app/lib/reports/claimed_tickets_with_no_signups_report.rb`)
Touches: `access_document`, `person`, `person_slot`, `slot`, `position`, `timesheet`, `person_online_course`, `trainee_status`, `trainer_status`
Verify: `test/controllers/ticketing/claimed_with_no_signups_controller_test.rb`
Trap: sign-ups never filter rows (`has_signups` feeds only a column and the Signed up filter): rows are claimed/submitted SPT or Staff Credential holders minus course completers (`completed_at`) with a present-year timesheet, so pre-event all holders show.
Trap: `signed_up_ids` drops training sign-ups by plucked `training_position_ids`, not a `type != 'Training'` join, which also drops every NULL-`type` position (none of `test/fixtures/positions.yml` sets one) — keep it id-based.

### Expiring Tickets
Reach it: `GET /ticketing/expiring` → Ticketing › Reports › Expiring Tickets
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/expiring_controller.rb` (`index`, html + csv)
Owner: `ExpiringTicketsReport` (`app/lib/reports/expiring_tickets_report.rb`)
Touches: `access_document`, `person`
Verify: `test/controllers/ticketing/expiring_controller_test.rb`
Trap: the report takes qualified and banked SPTs and Staff Credentials with `expiry_date` on or before Dec 31 of the present year, so earlier-year lapses stay listed, flagged `expired`, until the Expire Tickets maintenance task changes their status.

### SAP Candidates
Reach it: `GET /ticketing/sap-candidates` → Ticketing › Reports › SAP Candidates
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/sap_candidates_controller.rb` (`index`, html + csv)
Owner: `SapCandidatesReport` (`app/lib/reports/sap_candidates_report.rb`)
Touches: `person`, `timesheet`, `person_slot`, `slot`, `position`, `access_document`
Verify: `test/controllers/ticketing/sap_candidates_controller_test.rb`, `test/lib/ticketing_maintenance_test.rb`, `test/jobs/rangers_who_need_saps_job_test.rb`, `test/mailers/rangers_who_need_saps_mailer_test.rb`
Trap: `SapCandidatesReport` also selects for Grant Ranger SAPs (`TicketingMaintenance::GrantSaps`) and `RangersWhoNeedSapsJob`'s email — changing who appears here changes who is granted a SAP.
Trap: a Staff Credential counts as a SAP and a SAP is never banked, so one list (`AccessDocument::CURRENT_STATUSES`) covers all three types — don't restore upstream's per-type status split.

### Unclaimed w/Sign-Ups
Reach it: `GET /ticketing/unclaimed-with-signups` → Ticketing › Reports › Unclaimed w/Sign-Ups
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/unclaimed_with_signups_controller.rb` (`index`, html + csv)
Owner: `UnclaimedTicketsWithSignupsReport` (`app/lib/reports/unclaimed_tickets_with_signups_report.rb`)
Touches: `access_document`, `person`, `person_slot`, `slot`
Verify: `test/controllers/ticketing/unclaimed_with_signups_controller_test.rb`
Trap: `UnclaimedTicketsWithSignupsReport.signup_cutoff` (Aug 15, `Time.local` because `slot.begins` is system-local) is also read by `ClaimedTicketsWithNoSignupsReport` and `BmidSanityCheckReport` — moving it moves all three.

### Bulk Access Documents
Reach it: `GET /ticketing/bulk-access-documents` → Ticketing › Maintenance › Bulk Access Documents; preview `POST /ticketing/bulk-access-documents/preview`; apply `POST /ticketing/bulk-access-documents`; back to edit `POST /ticketing/bulk-access-documents/edit`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/bulk_access_documents_controller.rb` (`index`, `preview`, `apply` via `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::TicketHandler` (`app/lib/bulk_upload/ticket_handler.rb`), `BulkUpload::SapDateHandler` (`app/lib/bulk_upload/sap_date_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`)
Touches: `person`, `access_document` (w), `access_document_changes` (w), `action_logs` (w), `setting`
Verify: `test/controllers/ticketing/bulk_access_documents_controller_test.rb`
Trap: "Update SAP dates" (`wap`) runs `AccessDocument.update_saps_for_person` on every qualified/claimed/banked SAP and Staff Credential held, but preview sees one `find_sap_for_person_ids` candidate — guard all, like `@any_time` in `SapDateHandler#preload`.
Trap: CRED/SPT/VP lines missing a source year (CRED/SPT: expiry year) take `BulkUpload::Handler.default_years`, which rolls over in September (before: source = present year − 1, expiry = present year + 3) — test against `default_years`, not hard-coded years.

### Bulk Provisions (hero: Bulk Grant Provisions)
Reach it: `GET /ticketing/bulk-provisions` → Ticketing › Maintenance › Bulk Provisions; preview `POST /ticketing/bulk-provisions/preview`; apply `POST /ticketing/bulk-provisions`; back to edit `POST /ticketing/bulk-provisions/edit`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/bulk_provisions_controller.rb` (`index`, `preview`, `apply` via `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::ProvisionHandler` (`app/lib/bulk_upload/provision_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`), `BulkUpload::Handler` (`app/lib/bulk_upload/handler.rb`)
Touches: `person`, `provision` (w), `action_logs` (w)
Verify: `test/controllers/ticketing/bulk_provisions_controller_test.rb`
Trap: there is no "no change" verdict: each matching current provision (meal passes match all three period flags plus `is_allocated`) is cancelled with `save!(validate: false)` and replaced, so re-running a list re-creates instead of skipping.
Trap: the action ids in `ACTIONS` (`alloc_*`, the doubled `event_post_event_eat_pass`) key the existing history rows — never rename them.

### Bulk BMID Actions (hero: Bulk Badge Actions)
Reach it: `GET /ticketing/bulk-bmid` → BMID › BMID Menu › Bulk BMID Actions; preview `POST /ticketing/bulk-bmid/preview`; apply `POST /ticketing/bulk-bmid`; back to edit `POST /ticketing/bulk-bmid/edit`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/ticketing/bulk_bmid_controller.rb` (`index`, `preview`, `apply` via `app/controllers/concerns/bulk_upload_page.rb`)
Owner: `BulkUpload::BmidSubmitHandler` (`app/lib/bulk_upload/bmid_submit_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`)
Touches: `person`, `bmid` (w), `action_logs` (w)
Verify: `test/controllers/ticketing/bulk_bmid_controller_test.rb`
Trap: despite `/ticketing` and `Ticketing::`, it gates on `EDIT_BMIDS` and renders `layout "bmid"` — keep it in `Menus::BMID`; TICKETING's `[ADMIN, EDIT_ACCESS_DOCS]` gate would hide it from Edit BMIDs holders and show it to people the controller refuses.
Trap: only present-year badges in `issues` or `ready_to_print` can be submitted, and a person with no `bmid` row reads as `in_prep` and is refused, so apply never creates a badge.

### Ticketing Maintenance Tasks
Reach it: `GET /ticketing/maintenance` → Ticketing › Maintenance › Maintenance Tasks; preview `GET /ticketing/maintenance/:task`; commit `POST /ticketing/maintenance/:task`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`; blocked until set: `TAS_DefaultWAPDate` (Grant Ranger SAPs, Set Staff Credential Access Dates), `TAS_DefaultAlphaWAPDate` (Grant Alpha SAPs)
Controller: `app/controllers/ticketing/maintenance_controller.rb` (`index`, `preview`, `commit`)
Owner: `TicketingMaintenance` (`app/lib/ticketing_maintenance.rb`: registry `GROUPS`, slug lookup `find`), `TicketingMaintenance::Base` (`app/lib/ticketing_maintenance/base.rb`), `TicketingMaintenance::GrantTask` (`app/lib/ticketing_maintenance/grant_task.rb`)
Touches: `access_document` (w), `access_document_changes` (w), `provision` (w), `action_logs` (w), `person`, `setting`, `bmid`, `timesheet`, `person_asset`, `asset`, `person_slot`, `slot`, `position`
Verify: `test/controllers/ticketing/maintenance_controller_test.rb`, `test/lib/ticketing_maintenance_test.rb`
Trap: preview and commit share `execute` (`commit:` false/true); commit saves each row via `save(validate: false)`, no transaction (a failed save shows in the ledger's error column), and renders `results` with a 422 — assert `:unprocessable_entity` on success.
Trap: `TicketingMaintenance.maintenance_year`, `ExpireTickets.scope` and `ExpireProvisions.scope` read `Date.current`, not `Current.today`, so the Groundhog Day clock doesn't move them (grant tasks use `Current.year`) — tests use `travel_to`.

### Un-Submit Provisions
Reach it: `GET /ticketing/unsubmit-provisions` → Ticketing › Maintenance › Un-Submit Provisions (also a card on Maintenance Tasks); commit `POST /ticketing/unsubmit-provisions`
Gate: `ADMIN`, `EDIT_ACCESS_DOCS`
Controller: `app/controllers/ticketing/unsubmit_provisions_controller.rb` (`index` html + csv, `commit`)
Owner: `UnsubmitProvisionsReport` (`app/lib/reports/unsubmit_provisions_report.rb`), `TicketingMaintenance::UnsubmitProvisions` (`app/lib/ticketing_maintenance/unsubmit_provisions.rb`)
Touches: `provision` (w), `action_logs` (w), `person`, `timesheet`, `access_document`, `bmid`, `person_slot`, `slot`, `position`
Verify: `test/controllers/ticketing/unsubmit_provisions_controller_test.rb`, `test/lib/reports/unsubmit_provisions_report_test.rb`, `test/lib/ticketing_maintenance_test.rb`
Trap: `TicketingMaintenance.maintenance_year` (last year until August) scopes only rangered/BMID/sign-up checks — `TicketingMaintenance::UnsubmitProvisions.unsubmit` makes every earned claimed/submitted provision of checked people available, any source year.
Trap: `commit` never re-runs `UnsubmitProvisionsReport` and resets whatever `person_ids` are posted — put any new eligibility guard in `TicketingMaintenance::UnsubmitProvisions.unsubmit` too, not only the report.

## BMID

Every `app/controllers/bmid/` controller renders in `layouts/bmid` behind `authorize_role [ADMIN, EDIT_BMIDS]`. Manage, the badge editor, the provision dialog and Export include `BmidYearConcern` (`setup_year`: `?year=`, floor 2017, else present year); Sanity Check and Set BMID Titles always use the present year. `Bmid.find_for_person_ids` synthesizes an unsaved in-prep `Bmid` for anyone without one, so rows and form keys are person ids, never bmid ids. `Bmid` is the model class, not a module: new code under `app/controllers/bmid` or `app/helpers/bmid` must be written `class Bmid::XController` — `module Bmid` raises "Bmid is not a module".

### Manage BMIDs
Reach it: `GET /bmid/manage` → BMID › BMID Menu › Manage BMIDs; Edit Mode `GET /bmid/manage?mode=edit`; bulk save `PATCH /bmid/manage`; CSV `GET /bmid/manage.csv`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/manage_controller.rb` (`index`, `update`), `app/controllers/concerns/bmid_year_concern.rb`
Owner: `BmidManagement` (`app/lib/bmid_management.rb`), `Bmid` (`app/models/bmid.rb`), `BmidRelationshipLoader` (`app/lib/bmid_relationship_loader.rb`)
Touches: `bmid` (w), `access_document` (w), `access_document_changes` (w), `action_logs` (w), `person`, `person_photo`, `person_event`, `person_slot`, `slot`, `provision`, `setting`
Verify: `test/controllers/bmid/manage_controller_test.rb`, `test/lib/bmid_management_test.rb`, `test/models/bmid_test.rb`
Trap: `update` saves only fields `row_changes` finds differ from the loaded badge — never trust the browser's dirty marking, or a JavaScript-broken Save INSERTs a badge and `action_logs` row for every synthesized person.
Trap: `bmid.meals`/`bmid.showers` don't print, despite the `app/models/bmid.rb` comment — `EventreeBmidExport#csv_row` prints `meals_granted`/`showers_granted` from live provisions; the columns only feed Specials (`BmidManagement.badge_person_ids`).

### Manage BMIDs › Edit badge (single-badge editor)
Reach it: `GET /bmid/manage/badges/:person_id/edit` → Manage BMIDs row Edit link; save `PATCH /bmid/manage/badges/:person_id`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/badges_controller.rb` (`edit`, `update`), `app/controllers/concerns/bmid_year_concern.rb`
Owner: `Bmid` (`app/models/bmid.rb`), `BmidRelationshipLoader` (`app/lib/bmid_relationship_loader.rb`), `AccessDocument.update_saps_for_person` (`app/models/access_document.rb`) (not `Person::BmidsController`)
Touches: `bmid` (w), `access_document` (w), `access_document_changes` (w), `action_logs` (w), `person`, `person_photo`, `person_event`, `person_slot`, `slot`, `provision`, `setting`
Verify: `test/controllers/bmid/badges_controller_test.rb`, `test/models/bmid_test.rb`, `test/helpers/bmid_helper_test.rb`
Trap: `Person::BmidsController` (`/person/:person_id/bmid`) always loads `Current.year` and snapshots `load_provision_package` — point roster edits at this editor, which takes the viewed year and round-trips `Bmid::ManageHelper::VIEW_PARAMS`.
Trap: this form must keep `data: { turbo: false }`, or Turbo drops the `#bmid-row-N` fragment from the redirect back to the roster.
Trap: `badge_params` drops `admission_date` whenever `Bmid#sap_disabled?` (true for any non-present-year badge) — `AccessDocument.find_sap_for_person_ids` isn't year-scoped, so a past-year badge would rewrite the live SAP date via `Bmid#update_sap`.

### Manage BMIDs › Meals & Showers provision dialog
Reach it: `GET /bmid/manage/provisions` → meals/showers cells in Manage BMIDs Edit Mode and the badge editor; add `GET /bmid/manage/provisions/new` + `POST /bmid/manage/provisions`; edit `GET /bmid/manage/provisions/:id/edit` + `PATCH /bmid/manage/provisions/:id`; delete `DELETE /bmid/manage/provisions/:id`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/provisions_controller.rb` (`index`, `create`, `update`, `destroy`; `new`, `edit` from `app/controllers/concerns/provision_crud_concern.rb`), `app/controllers/concerns/bmid_year_concern.rb`
Owner: `ProvisionCrudConcern` (`app/controllers/concerns/provision_crud_concern.rb`), `Provision` (`app/models/provision.rb`)
Touches: `provision` (w), `action_logs` (w), `person`
Verify: `test/controllers/bmid/provisions_controller_test.rb`, `test/controllers/bmid/manage_controller_test.rb`, `test/controllers/bmid/badges_controller_test.rb`
Trap: a provision save must never write the badge or reload the grid, which holds unsaved edits — it turbo_streams only that person's `bmid/manage/_meals_cell` and `_showers_cell`, drawn from a fresh unsaved `Bmid` in `badge_row`.
Trap: the `layout` lambda serves `turbo_rails/frame` to frame requests — hard-coding `layout "bmid"` rebuilds the sidebar on every open and returns two turbo-frames with id `modal`.

### Export BMIDs (Eventree export)
Reach it: `GET /bmid/export` → BMID › BMID Menu › Export BMIDs; export `POST /bmid/export`; un-submit a batch `DELETE /bmid/export/:id`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/export_controller.rb` (`index`, `create`, `unsubmit`), `app/controllers/concerns/bmid_year_concern.rb`
Owner: `EventreeBmidExport` (`app/lib/eventree_bmid_export.rb`), `BmidExport` (`app/models/bmid_export.rb`), `BmidManagement` (`app/lib/bmid_management.rb`)
Touches: `bmid` (w), `provision` (w), `bmid_export` (w), `active_storage_attachments` (w), `active_storage_blobs` (w), `action_logs` (w), `person`, `person_photo`, `person_event`, `access_document`, `person_slot`, `slot`, `setting`
Verify: `test/controllers/bmid/export_controller_test.rb`, `test/lib/eventree_bmid_export_test.rb`, `test/models/bmid_export_test.rb`, `test/lib/bmid_management_test.rb`, `test/jobs/delete_bmid_exports_job_test.rb`
Trap: `create` and `unsubmit` render success at 422 because Turbo drops a 200 form response, and tests assert `:unprocessable_entity` — don't "fix" them to 200 or a redirect.
Trap: `unsubmit` finds batches only in `BmidExport.for_year(current_year)`, which filters `created_at` on the present year, not the viewed year.
Trap: the CSV is stored at `exports/<filename>` (`AttachmentKey`), and the filename is the key, so it carries the second and takes `Time.current`, never `Current.time`, which stands still on the training server. Two exports in one second fail the save, which rolls the whole batch back.
Trap: `EventreeBmidExport.unsubmit!` reverts badges to `in_prep` (pre-export status isn't recorded) and returns only provisions matching `Provision::BMID_EXPORT_COMMENT` plus an `updated_at` fence.

### BMID Sanity Check
Reach it: `GET /bmid/sanity-check` → BMID › BMID Menu › BMID Sanity Check
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/sanity_check_controller.rb` (`index`)
Owner: `BmidSanityCheckReport` (`app/lib/reports/bmid_sanity_check_report.rb`)
Touches: `person`, `person_slot`, `slot`, `position`, `access_document`, `setting`
Verify: `test/controllers/bmid/sanity_check_controller_test.rb`, `test/lib/reports/bmid_sanity_check_report_test.rb`
Trap: `index` ignores `params[:year]` and always checks `current_year` (no `BmidYearConcern`, no year selector) — every check compares against today's access documents and the single `TAS_BOX_OFFICE_OPEN_DATE` setting.
Trap: `BmidSanityCheckReport` never reads the `bmid` table, and check 3 (`shifts_no_wap`) deliberately treats a banked or dateless SAP/Staff Credential as no usable SAP (ruled deviation from upstream), so nobody lands in both checks 1 and 3.

### BMID Titles (Badge Titles)
Reach it: `GET /bmid/titles` → BMID › BMID Menu › BMID Titles; add `GET /bmid/titles/new` + `POST /bmid/titles`; edit `GET /bmid/titles/:id/edit` + `PATCH /bmid/titles/:id`; delete `DELETE /bmid/titles/:id`; reorder `PATCH /bmid/titles/:id/move`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/titles_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `move`)
Owner: `BmidTitle` (`app/models/bmid_title.rb`)
Touches: `bmid_title` (w), `action_logs` (w), `position`
Verify: `test/controllers/bmid/titles_controller_test.rb`, `test/models/bmid_title_test.rb`
Trap: editing or deleting a `BmidTitle` changes no badge — `bmid.title1`–`title3` are copied strings with no link to `bmid_title`; only Set BMID Titles (or a hand edit of the badge) rewrites them.
Trap: `BmidTitle#move!` renumbers the whole line's `sort_index` instead of swapping two values (equal and gapped numbers are legal); the lowest `sort_index` on a line wins for a person with several title-earning positions.

### Set BMID Titles
Reach it: `GET /bmid/titles/set` → BMID Titles › Set BMID Titles button; commit `POST /bmid/titles/set`
Gate: `ADMIN`, `EDIT_BMIDS`
Controller: `app/controllers/bmid/titles_controller.rb` (`set`, `apply`)
Owner: `BmidTitleAssignment` (`app/lib/bmid_title_assignment.rb`), `BmidTitle` (`app/models/bmid_title.rb`), `BmidRelationshipLoader` (`app/lib/bmid_relationship_loader.rb`)
Touches: `bmid` (w), `action_logs` (w), `bmid_title`, `position`, `person_position`, `person`, `person_event`, `access_document`, `person_slot`, `slot`, `provision`
Verify: `test/lib/bmid_title_assignment_test.rb`, `test/controllers/bmid/titles_controller_test.rb`, `test/models/bmid_title_test.rb`
Trap: `Bmid::TitlesController` `set` and `apply` always use `current_year`, never a viewed year (no `BmidYearConcern`; the menu item is not `year_scoped`), and `apply` renders success at 422.
Trap: `BmidTitleAssignment.apply` re-derives candidates via `preview` (no departed or `not_qualified_to_print?` people), ignores posted rows outside it, keeps the proposed title for a missing or malformed cell, and never inserts an all-blank synthesized badge.

## Assets & Vehicles

Asset Management controllers include `AssetYearScopeConcern`: the year comes from `asset.year` values (`resolve_selected_year`, never `setup_year`), and Assets Outstanding, Asset History and Radio Checkout Report override `default_year` to the newest active year. Routes sit under `/asset-management` because Propshaft owns `/assets`. Vehicle Registry and Vehicle Paperwork use `setup_year` (`year_floor = 2019`); Bulk Vehicle Paperwork always writes the present year.

### Asset Search
Reach it: `GET /asset-management/search` → Asset Management › Asset Management Menu › Asset Search; check in `PATCH /asset-management/search/:asset_id/check-in`
Gate: `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/asset_management/search_controller.rb` (`index`, `check_in`), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: `Asset` (`app/models/asset.rb`, `find_for_query(include_history: true)`), `PersonAsset` (`app/models/person_asset.rb`, `find_checked_out_person`); check-in write inline in controller
Touches: `asset`, `person_asset` (w), `person`, `asset_attachment`, `action_logs` (w)
Verify: `test/controllers/asset_management/search_controller_test.rb`, `test/models/asset_test.rb`, `test/models/person_asset_test.rb`
Trap: `index` takes `Asset.find_for_query(barcode:, year:).first`, but `asset_year_barcode_index` is not unique (only the model validates it), so a duplicated barcode silently shows just one of its assets.
Trap: `check_in` writes `person_asset` behind the read gate `:read_assets` on purpose (upstream lets `EVENT_MANAGEMENT` check in) and is the namespace's only check-in — do not move it behind `EDIT_ASSETS`.

### Asset Inventory (records)
Reach it: `GET /asset-management/records` → Asset Management › Asset Management Menu › Asset Inventory; type list `GET /asset-management/records/type/:type`; record `GET /asset-management/records/:id` (also the search bar's `#barcode` result, `Autocomplete::AssetAdapter`); create `GET /asset-management/records/new` → `POST /asset-management/records`; edit `GET /asset-management/records/:id/edit` → `PATCH /asset-management/records/:id`; delete `DELETE /asset-management/records/:id`
Gate: read (`index`, `type`, `show`): `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`; write (`new`, `create`, `edit`, `update`, `destroy`): `ADMIN`, `EDIT_ASSETS` (denied reader → inventory, anyone else → `/me`)
Controller: `app/controllers/asset_management/records_controller.rb` (`index`, `type`, `show`, `new`, `create`, `edit`, `update`, `destroy`; CSV on `index` and `type`), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: `AssetManagement::Records::CreateForm` (`app/forms/asset_management/records/create_form.rb`), `Asset` (`app/models/asset.rb`), `AssetManagement::RecordsHelper` (`app/helpers/asset_management/records_helper.rb`)
Touches: `asset` (w), `person_asset` (w), `person`, `asset_attachment`, `action_logs` (w)
Verify: `test/controllers/asset_management/records_controller_test.rb`, `test/forms/asset_management/records/create_form_test.rb`, `test/models/asset_test.rb`, `test/services/autocomplete/asset_adapter_test.rb`, `test/system/search_bar_hotkey_test.rb`
Trap: `create` merges `year: Current.year` into `CreateForm`, so a new asset (and every `copies` copy) lands in the present year whatever year the inventory was showing.
Trap: `destroy!` cascades via `Asset has_many :asset_history, dependent: :delete_all`, deleting every `person_asset` row in SQL past `PersonAsset`'s audit callbacks — the `asset-delete` action_logs row is the only trace.

### Assets Outstanding
Reach it: `GET /asset-management/assets-outstanding` → Asset Management › Asset Management Menu › Assets Outstanding
Gate: `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/asset_management/assets_outstanding_controller.rb` (`index`, CSV), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: inline in controller: `Asset.find_for_query(checked_out: true)` (`app/models/asset.rb`), `PersonAsset` for `default_year`
Touches: `asset`, `person_asset`, `person`, `asset_attachment`
Verify: `test/controllers/asset_management/assets_outstanding_controller_test.rb`, `test/models/asset_test.rb`
Trap: `EDIT_ASSETS` passes every asset gate but is not in `PersonConcern::VIEW_ROLES`, so it cannot open `/person/:id` — render asset holders with `person_display_link`, never a bare `callsign_link`, here and on sibling pages.
Trap: there is no `person_asset` fixture (only `test/fixtures/asset.yml`) and `asset_attachment` has no auto-increment `id` (`db/schema.rb`) — build a checkout with `PersonAsset.create!` and pass an explicit `id:` to `AssetAttachment.create!`.

### Asset History
Reach it: `GET /asset-management/asset-history` → Asset Management › Asset Management Menu › Asset History
Gate: `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/asset_management/asset_history_controller.rb` (`index`, CSV), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: inline in controller: `Asset.find_for_query(include_history: true, exclude:)` (`app/models/asset.rb`), `PersonAsset` (`app/models/person_asset.rb`), `AssetManagement::AssetHistoryHelper` (`app/helpers/asset_management/asset_history_helper.rb`)
Touches: `asset`, `person_asset`, `person`, `asset_attachment`
Verify: `test/controllers/asset_management/asset_history_controller_test.rb`, `test/models/asset_test.rb`, `test/models/person_asset_test.rb`
Trap: `DEFAULT_EXCLUDED_TYPE = Asset::TYPE_RADIO` hides radios by default, so `?type=radio` widens the ledger rather than narrowing it, and `default_year`/`checkout_years` ignore radio checkouts — an empty page may be a radios-only year.
Trap: `PersonAsset#duration` measures an open checkout to `Current.time`, so a past year's unreturned asset reads as years — blank it when `checked_in` is nil, as the table and CSV do.
Trap: Pagy pages the ledger in memory, since `Asset.natural_sort` orders it in Ruby: 100 a page, a page past the last reads as the last, and `ui_pager` draws only past one page.

### Radio Assets
Reach it: `GET /asset-management/radio-assets` → Asset Management › Asset Management Menu › Radio Assets (range summary via `?view=summary`)
Gate: `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/asset_management/radio_assets_controller.rb` (`index`, CSV), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: `RadioAssetRanges` (`app/lib/reports/radio_asset_ranges.rb`, top-level: `app/lib/reports` is an autoload root), `Asset` (`app/models/asset.rb`, `find_for_query(type: radio)`); filtering inline in controller
Touches: `asset`
Verify: `test/controllers/asset_management/radio_assets_controller_test.rb`, `test/lib/reports/radio_asset_ranges_test.rb`
Trap: for radios `perm_assign` means Event vs Shift (`asset_duration_label`), not permanent/temporary — filter with `?duration=event|shift`, never the raw boolean (`"false"` arrives as a truthy string).
Trap: `Asset.natural_sort` interleaves sequences sharing a prefix (`100, 100A, 101, 101A`), so a neighbour walk never pairs 100 with 101 — `RadioAssetRanges` groups by run key before chunking.
Trap: Pagy pages whichever table is on screen, in memory (`Asset.natural_sort` orders in Ruby): 100 a page, a page past the last reads as the last, and in the summarized view `ui_pager` counts barcode ranges, not radios.

### Radio Checkout Report
Reach it: `GET /asset-management/radio-checkout` → Asset Management › Asset Management Menu › Radio Checkout Report (after-action audit via `?view=summary`)
Gate: `ADMIN`, `EDIT_ASSETS`, `EVENT_MANAGEMENT`
Controller: `app/controllers/asset_management/radio_checkout_controller.rb` (`index`, CSV), `app/controllers/concerns/asset_year_scope_concern.rb`
Owner: `RadioCheckoutReport` (`app/lib/reports/radio_checkout_report.rb`, top-level), `PersonAsset` (`app/models/person_asset.rb`, `duration`)
Touches: `person_asset`, `asset`, `person`, `provision`
Verify: `test/controllers/asset_management/radio_checkout_controller_test.rb`, `test/lib/reports/radio_checkout_report_test.rb`
Trap: `RadioCheckoutReport#eligible_person_ids` deliberately disagrees with HQ's `PersonEventInfo#radio_max` on event-radio eligibility at the edges (used-this-year provisions, `BANKED`) — change both or neither.
Trap: `?view=summary` widens the set (`reportable?` admits every still-out radio, ignoring the 14-hour limit) — any "overdue" or "more than 14 hours" heading or count must branch on `@summary_view`.

### Vehicle Registry
Reach it: `GET /vehicles/registry` → Vehicles › Vehicles Menu › Vehicle Registry; add `GET /vehicles/registry/new` → `POST /vehicles/registry`; edit `GET /vehicles/registry/:id/edit` → `PATCH /vehicles/registry/:id`; driving permit `GET /vehicles/registry/:id/permit` → `PATCH /vehicles/registry/:id/permit`; delete `DELETE /vehicles/registry/:id`
Gate: view and permit: `ADMIN`, has_event_management? (`EVENT_MANAGEMENT`, `EVENT_MANAGEMENT_ON_PLAYA`); `new`/`create`/`edit`/`update` add `VEHICLE_INFO_UPDATE` (or `ADMIN`); `destroy`: `ADMIN` only
Controller: `app/controllers/vehicles/registry_controller.rb` (`index` with CSV, `new`, `create`, `edit`, `update`, `destroy`, `permit`, `update_permit`)
Owner: `VehicleRegistry` (`app/lib/vehicle_registry.rb`), `Vehicle` (`app/models/vehicle.rb`), `Vehicles::RegistryHelper` (`app/helpers/vehicles/registry_helper.rb`)
Touches: `vehicle` (w), `person`, `person_event`, `access_document`, `team`, `person_team`, `position`, `person_position`, `person_slot`, `slot`
Verify: `test/controllers/vehicles/registry_controller_test.rb`, `test/models/vehicle_test.rb`, `test/lib/vehicles_menu_test.rb`
Trap: `:view_registry` has no `only:` and runs before `:edit_registry`, so a `VEHICLE_INFO_UPDATE` holder without event management is bounced to `/me` — editing needs both.
Trap: `VehicleRegistry.for_year` enriches rows (Setup Access Pass arrival, MVR/PVR teams, positions, sign-ups) only for `Current.year`; other years leave them empty with `enriched?` false — show "not checked", not "none".

### Vehicle Paperwork
Reach it: `GET /vehicles/paperwork` → Vehicles › Vehicles Menu › Vehicle Paperwork
Gate: `ADMIN`, `EVENT_MANAGEMENT`, `VEHICLE_INFO_UPDATE`
Controller: `app/controllers/vehicles/paperwork_controller.rb` (`index`, CSV)
Owner: `VehiclePaperworkReport` (`app/lib/reports/vehicle_paperwork_report.rb`, top-level), `Vehicles::PaperworkHelper` (`app/helpers/vehicles/paperwork_helper.rb`)
Touches: `person_event`, `person_team`, `team`, `person_position`, `position`, `person_slot`, `slot`, `person`
Verify: `test/controllers/vehicles/paperwork_controller_test.rb`, `test/lib/reports/vehicle_paperwork_report_test.rb`, `test/lib/vehicles_menu_test.rb`
Trap: `person_team` and `person_position` have no year column, so `build_rows` reads memberships and granted positions only for `Current.year`; other years are empty with `memberships_checked?` false — render "not checked", not absence.
Trap: MVR positions are held grants (`granted_mvr_positions_by_person_id`, `person_position`), PVR positions the year's sign-ups (`signup_positions_by_person_id`, `person_slot`) — never swap in `Position.vehicle_eligible_for_person` for PVR.

### Bulk Vehicle Paperwork
Reach it: `GET /vehicles/bulk-paperwork` → Vehicles › Vehicles Menu › Bulk Vehicle Paperwork; preview `POST /vehicles/bulk-paperwork/preview`; apply `POST /vehicles/bulk-paperwork`; back to form `POST /vehicles/bulk-paperwork/edit`
Gate: `ADMIN`, `VEHICLE_MANAGEMENT`
Controller: `app/controllers/vehicles/bulk_paperwork_controller.rb` (`index`, `preview`, `apply` from `BulkUploadPage`; own `ACTIONS` list), `app/controllers/concerns/bulk_upload_page.rb` (every POST renders 422)
Owner: `BulkUpload::EventFlagHandler` (`app/lib/bulk_upload/event_flag_handler.rb`), `BulkUpload::Batch` (`app/lib/bulk_upload/batch.rb`), `BulkUploadPage` (`app/controllers/concerns/bulk_upload_page.rb`)
Touches: `person`, `person_event` (w), `action_logs` (w)
Verify: `test/controllers/vehicles/bulk_paperwork_controller_test.rb`, `test/lib/vehicles_menu_test.rb`
Trap: `EventFlagHandler#apply` only sets flags to true, on the `Current.year` `person_event` row (`BulkUpload::Handler#year`) — clear flags on Person › Vehicles (`PATCH /person/:person_id/vehicles/update_mvr_flags` and siblings).
Trap: `PersonEvent` is not an `audit_model`, so the single `bulk-upload` action_logs row written by `Batch#record_commit` is the whole audit trail of a run.

## Pogs

Controllers inherit `ApplicationController` directly, render in `app/views/layouts/pogs.html.erb` (`Menus::POGS` sidebar) and gate with one `authorize_role [ADMIN, POG_MANAGEMENT]` matching both menu items. Both take a viewed year (`setup_year`, `year_floor = 2023`, the first event with pog tracking) and scope it on `person_pog.issued_at` through `PersonPog.issued_in`. Role row 133 comes from `db/migrate/20261013000001_add_pog_management_role.rb`; until that runs on a database, Pog Management cannot be granted there, though Admin still gets in. Its `down` purges the role cache (`RoleManager.purge_all`), as deleting a permission on Admin › Permissions does.

### Pog Dashboard
Reach it: `GET /pogs/dashboard` → Pogs › Pogs Menu › Pog Dashboard
Gate: `ADMIN`, `POG_MANAGEMENT`
Controller: `app/controllers/pogs/dashboard_controller.rb` (`index`)
Owner: `PogStatsReport` (`app/lib/reports/pog_stats_report.rb`) over `PersonPog.issued_in` (`app/models/person_pog.rb`)
Touches: `person_pog`, `person`
Verify: `test/lib/reports/pog_stats_report_test.rb`, `test/controllers/pogs/dashboard_controller_test.rb`, `test/lib/pogs_menu_test.rb`
Trap: The year is the one a pog was issued in (`issued_at`), while Person › Pogs scopes by `created_at` (`PersonPog.find_for_query`). The two agree for every dev row today; a pog whose row was written in a later year lands in different years on the two pages.
Trap: Cancelled pogs count only in the Cancelled tile and column. Every other number (types, days, both top-ten lists, Linked to a shift) reads issued and redeemed pogs, and a redeemed pog counts as issued. A year whose pogs were all cancelled still shows the page; its by-day section says nothing was issued.
Trap: Every section reads the same rows: those whose `pog` and `status` PersonPog knows (Clubhouse 2 stored both unchecked). Grouped values are matched to the constants case- and space-insensitively, as the columns' collation compares them.
Trap: Shares round to whole percents but never to 0% while there is something, nor to 100% while something is missing.
Trap: A day is `DATE(issued_at)` on the stored clock, not `Time.zone`. Rows are written in the process zone (`default_timezone = :local`), so the dates are right only while the server runs in the event's zone. `docker-compose.yml` sets `TZ=America/Phoenix` for that (unverified on beta); the `Dockerfile` sets none.
Trap: Each top-ten name links to Pog Administration for the year, filtered to that person's issued pogs (issuers by `filter[issued_by_id]`, recipients by `filter[person_callsign]`, both with `filter[status]=issued`), so the list holds exactly the pogs counted. Never a person page: Pog Management alone may not open those. A deleted person stays plain text.
Trap: Event Management is deliberately not in the gate — it keeps Person › Pogs and the HQ window.

### Pog Administration
Reach it: `GET /pogs/administration` → Pogs › Pogs Menu › Pog Administration; filtered `GET /pogs/administration?year=Y&filter[person_callsign|issued_by_id|day|pog|status|page]=…`, also linked from every Pog Dashboard top-ten name; edit `GET /pogs/administration/:id/edit` → `PATCH /pogs/administration/:id`; delete `DELETE /pogs/administration/:id` (from the edit page)
Gate: `ADMIN`, `POG_MANAGEMENT`
Controller: `app/controllers/pogs/administration_controller.rb` (`index`, `edit`, `update`, `destroy`)
Owner: `PogFilterForm` (`app/forms/pog_filter_form.rb`) over `PersonPog.issued_in` (`app/models/person_pog.rb`); options, chips and the delete confirmation in `Pogs::AdministrationHelper` (`app/helpers/pogs/administration_helper.rb`)
Touches: `person_pog` (w), `action_logs` (w), `person`, `timesheet`, `position`
Verify: `test/controllers/pogs/administration_controller_test.rb`, `test/lib/pogs_menu_test.rb`
Trap: Same year rule as Pog Dashboard: `issued_at` here, `created_at` on Person › Pogs.
Trap: The recipient filter is a callsign text field, not the person search: `/autocomplete/search` answers only to Event Management. It finds the callsign's exact holder; failing that, everyone whose callsign matches once spaces and punctuation are dropped ("firefly" finds "Fire-Fly"), never one of them picked at random as `Person.find_id_by_callsign` would. A callsign no one holds lists no pogs and keeps its chip. Any typed value is a filter, `all` included.
Trap: Status is not the stored status: Issued means handed over, a redeemed pog included, as the Pog Dashboard counts it; Cancelled is cancelled.
Trap: Issued By, Day, Type and Status offer only what the viewed year holds, an issuer whose person row is gone included ("Deleted #12"). Any other value reads as All with no chip. The year selector carries the filters, so changing the year can silently drop one the new year lacks.
Trap: The options carry no counts. A count would have to promise the rows the choice shows under the other filters (the `filter_status_options` rule), which the Pog Dashboard already answers.
Trap: Pages hold `PAGE_SIZE` (100) pogs, newest first, through Pagy; a page past the last reads as the last (Pagy answers it empty, so `index` asks again for its last page, as Request Log does). The pager shows on a single page too: its summary is where an unfiltered list's total reads.
Trap: Rows offer Edit only. Delete is on the edit page, because a confirmation per row is a whole dialog per row, a hundred to a page. Its confirmation is the destructive "Delete Pog" button, and its message's time is plain `strftime(MONTH_DAY_TIME_YEAR)`, since `datetime_format`'s span would print as markup in an attribute.
Trap: The list's edit links and the edit page (form, cancel, back link, delete, redirects) carry the list's year, filters and page (`return_params`), so a save or a delete lands back where the reader was. A save that makes a filter untrue drops the row from that list.
Trap: The edit form changes type, status and notes only, never `issued_at`, and saves any type/status pair, as Person › Pogs does. HQ's rules (only an issued 1/2 Meal pog can be redeemed, a cancelled pog is final, a cancellation needs a note) live in `Hq::ShiftManageController` and are not enforced here.

## Quartermaster

Controllers inherit `ApplicationController` directly, render in `app/views/layouts/quartermaster.html.erb` (`Menus::QUARTERMASTER` sidebar) and gate with one `authorize_role` matching the menu's `visible_if`. `app/lib/reports/` classes are top-level (`EventsRangeredReport`, not `Reports::EventsRangeredReport`). Only Potential Shirts and Swag Distribution take a viewed year (`setup_year`); the rest use `Current.year` only for CSV filenames and Signed Up columns.

### Alpha Shirts
Reach it: `GET /quartermaster/alpha-shirts` → Quartermaster › Shifts/Swag Reports › Alpha Shirts; size-run CSV `GET /quartermaster/alpha-shirts/counts`
Gate: `ADMIN`, `QUARTERMASTER`, `MENTOR`
Controller: `app/controllers/quartermaster/alpha_shirts_controller.rb` (`index`, `counts`); filters: `app/controllers/concerns/shirt_filter_concern.rb`
Owner: `ShirtTotals` (`app/lib/shirt_totals.rb`); roster query inline in the controller (`Person`)
Touches: `person`, `swag`
Verify: `test/controllers/quartermaster/alpha_shirts_controller_test.rb`, `test/lib/shirt_totals_test.rb`
Trap: Both CSVs deliberately ignore the filters — `roster_rows` reads `@people`, not `@filtered_people` — unlike the Events Rangered, Potential Swag and Potential Shirts exports.
Trap: Not year-scoped: `?year=` is ignored, the roster is whoever holds Alpha or Prospective status now, and `Current.year` only names the CSV files.

### Potential Shirts
Reach it: `GET /quartermaster/potential-shirts` → Quartermaster › Shifts/Swag Reports › Potential Shirts; order-line CSV `GET /quartermaster/potential-shirts/counts`
Gate: `ADMIN`, `QUARTERMASTER`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/quartermaster/potential_shirts_controller.rb` (`index`, `counts`); filters: `app/controllers/concerns/shirt_filter_concern.rb`; `setup_year` with `year_floor = 2010`
Owner: `PotentialShirtsReport` (`app/lib/reports/potential_shirts_report.rb`), `ShirtTotals` (`app/lib/shirt_totals.rb`), `Setting` thresholds (`app/models/setting.rb`)
Touches: `setting`, `person`, `swag`, `person_slot`, `slot`, `position`, `timesheet`
Verify: `test/controllers/quartermaster/potential_shirts_controller_test.rb`, `test/lib/shirt_totals_test.rb`
Trap: `load_report`'s `Setting.get_value(..., throw_on_empty: true)` never raises for the two shirt thresholds (`default: 0` in `Setting::DESCRIPTIONS`) — with no `setting` row everyone has earned; check rows, not exceptions.
Trap: `PotentialShirtsReport.execute` drops anyone with an Alpha timesheet entry that year and earns on closed, counted entries all calendar year, so it disagrees with `TicketsAndProvisionsProgress` near a threshold — upstream parity, not a bug.

### Potential Swag
Reach it: `GET /quartermaster/potential-swag` → Quartermaster › Shifts/Swag Reports › Potential Swag
Gate: `ADMIN`, `QUARTERMASTER`, `EDIT_SWAG`
Controller: `app/controllers/quartermaster/potential_swag_controller.rb` (`index`); signed-up filter: `app/controllers/concerns/signed_up_filter_concern.rb`
Owner: `PotentialSwagReport` (`app/lib/reports/potential_swag_report.rb`), `RosterRollup` (`app/lib/reports/roster_rollup.rb`)
Touches: `person`, `person_slot`, `slot`, `position`
Verify: `test/controllers/quartermaster/potential_swag_controller_test.rb`, `test/lib/reports/potential_swag_report_test.rb`
Trap: `PotentialSwagReport.signed_up_ids` excludes Training with `where.not(slot: { position_id: Position.by_type(...).select(:id) })` — a `position.type != 'Training'` join drops sign-ups whose nullable `type` is NULL.

### Swag Distribution
Reach it: `GET /quartermaster/swag-distribution` → Quartermaster › Shifts/Swag Reports › Swag Distribution
Gate: `ADMIN`, `QUARTERMASTER`
Controller: `app/controllers/quartermaster/swag_distribution_controller.rb` (`index`); `setup_year` with `year_floor = 2009`, `allow_all_years = true`
Owner: `SwagDistributionReport` (`app/lib/reports/swag_distribution_report.rb`), `PersonSwag.find_for_query` (`app/models/person_swag.rb`)
Touches: `person_swag`, `swag`, `person`
Verify: `test/controllers/quartermaster/swag_distribution_controller_test.rb`
Trap: `@year` is nil in the All view, and `SwagDistributionReport.execute(nil)` drops `person_swag` rows with no `year_issued`, so All totals do not match a raw `person_swag` count.
Trap: A link without `year:` snaps an All or past-year reader back to the present year — build links with `swag_distribution_url` (`app/helpers/quartermaster/swag_distribution_helper.rb`), which always merges it.

### Events Rangered
Reach it: `GET /quartermaster/events-rangered` → Quartermaster › Service Reports › Events Rangered
Gate: `ADMIN`, `QUARTERMASTER`, `TIMESHEET_MANAGEMENT`
Controller: `app/controllers/quartermaster/events_rangered_controller.rb` (`index`); signed-up filter: `app/controllers/concerns/signed_up_filter_concern.rb`
Owner: `EventsRangeredReport` (`app/lib/reports/events_rangered_report.rb`), `RosterRollup` (`app/lib/reports/roster_rollup.rb`), `YearsManagement` (`app/lib/years_management.rb`)
Touches: `person`
Verify: `test/controllers/quartermaster/events_rangered_controller_test.rb`
Trap: A missing `status` param means Active, so removing the status chip silently re-applies it — build every link with `events_rangered_url` (`filter_url(..., always: [:status])`, `app/helpers/quartermaster/events_rangered_helper.rb`).
Trap: Years and Signed Up read stored `person.years_as_ranger` / `years_of_signups` (kept by `YearsManagement`): totals differ from upstream on purpose, and Signed Up counts training sign-ups, unlike Potential Swag's live non-training query.

### Freaking Years
Reach it: `GET /quartermaster/freaking-years` → Quartermaster › Service Reports › Freaking Years; one group `GET /quartermaster/freaking-years/:years`
Gate: `ADMIN`, `QUARTERMASTER`
Controller: `app/controllers/quartermaster/freaking_years_controller.rb` (`index`, `show`)
Owner: `FreakingYearsReport` (`app/lib/reports/freaking_years_report.rb`), `YearsManagement` (`app/lib/years_management.rb`)
Touches: `person`
Verify: `test/controllers/quartermaster/freaking_years_controller_test.rb`
Trap: `FreakingYearsReport.execute` filters `status: Person::ACTIVE` only, not `Person.active` (`ACTIVE_STATUSES`: adds inactive, inactive extension, retired) as Potential Swag and Potential Shirts do.
Trap: Years come from `person.years_of_service` (ranger + award + contributor years, kept by `YearsManagement`), not `years_as_ranger`, so a count here can exceed Events Rangered's.

### Quartermaster › Swag
Reach it: `GET /quartermaster/swag` → Quartermaster › Maintenance › Swag; `GET /quartermaster/swag/type/:type`, `GET /quartermaster/swag/new`, `POST /quartermaster/swag`, `GET /quartermaster/swag/:id/edit`, `PATCH /quartermaster/swag/:id`, `DELETE /quartermaster/swag/:id`
Gate: `ADMIN`, `EDIT_SWAG`
Controller: `app/controllers/quartermaster/swag_controller.rb` (`index`, `type`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `Swag` (`app/models/swag.rb`)
Touches: `swag` (w), `person_swag` (w), `person` (w)
Verify: `test/controllers/quartermaster/swag_controller_test.rb`
Trap: `destroy` deletes all `person_swag` rows; for `dept-shirt`, `Swag#cleanup_person_shirt_references` nulls `person.tshirt_swag_id` / `tshirt_secondary_swag_id` / `long_sleeve_swag_id` via `update_all` — no callbacks or `action_logs` row.
Trap: `cleanup_person_swag_references` is dead code — never registered, and it calls `person_swags`, which `Swag` lacks (its association is `person_swag`).
Trap: Only the controller's `swag_params` blanks `shirt_type` for non-shirt types, not `Swag` (frozen for the translation), so any other path saving a Swag keeps a stale `shirt_type`.

## Communication

Menu `Menus::COMMUNICATION_MANAGEMENT`; every controller in `app/controllers/communication/` uses `layout "communication"` except `MailTemplatesController` (`layout "admin"`). The five RBS controllers share no base, each with its own `authorize_role` over `Rbs` (`app/lib/rbs.rb`). The three survey controllers inherit `Communication::SurveyManagementBaseController` (`Survey.can_manage_any?` gate, `load_survey`, `move_line`, `year_floor` 2012).

### Communication Management › Announcements
Reach it: `GET /communication/announcements` → Communication Management › Announcements; create `POST /communication/announcements`; edit `PATCH /communication/announcements/:id`; delete `DELETE /communication/announcements/:id`; purge `POST /communication/announcements/delete-expired`
Gate: `ADMIN`, `ANNOUNCEMENT_MANAGEMENT`
Controller: `app/controllers/communication/announcements_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `delete_expired`)
Owner: `Motd` (`app/models/motd.rb`) (not `PersonMotd`: read-tracking only)
Touches: `motd` (w), `person_motd` (w), `person`
Verify: `test/controllers/communication/announcements_controller_test.rb`, `test/models/motd_test.rb`, `test/jobs/expire_announcements_job_test.rb`
Trap: `Motd.expired.delete_all` orphans `person_motd` rows (only `has_many :person_motd, dependent: :delete_all` clears them) — remove with `destroy` or `Motd.expire!` (`destroy_all`).
Trap: in production `ExpireAnnouncementsJob` runs `Motd.expire!` daily at 5am (`config/recurring.yml`; not on the Groundhog Day server), so the Expired filter and "Delete expired" see only rows expired since its last run.

### Account Banners
Reach it: `GET /communication/person-banners` → Communication Management › Account Banners
Gate: `ADMIN`, `VC`
Controller: `app/controllers/communication/person_banners_controller.rb` (`index`)
Owner: `PersonBanner.find_for_query` (`app/models/person_banner.rb`); type/year/callsign filters inline in `PersonBannersController#filtered`
Touches: `person_banner`, `person`
Verify: `test/controllers/communication/person_banners_controller_test.rb`
Trap: this page is read-only — add banner write actions to each person's Manage Account Banners page (`app/controllers/person/banners_controller.rb`, `/person/:person_id/banners`), not here.
Trap: the year filter runs in Ruby on purpose — not `PersonBanner.find_for_query(year:)`, whose `where_year` buckets by host clock (`Time.local`) while cards print `created_at` in the Clubhouse zone.

### Email Templates (mail templates)
Reach it: `GET /communication/mail-templates` → Communication Management › Email Templates; edit `GET /communication/mail-templates/:id/edit`; save `PATCH /communication/mail-templates/:id`
Gate: `ADMIN`, `VC`
Controller: `app/controllers/communication/mail_templates_controller.rb` (`index`, `edit`, `update`)
Owner: `MailTemplate` (`app/models/mail_template.rb`), `MailTemplateResolver` (`app/lib/mail_template_resolver.rb`), `MailTemplateSeeds` (`app/lib/mail_template_seeds.rb`)
Touches: `mail_template` (w), `action_logs` (w), `person`
Verify: `test/controllers/communication/mail_templates_controller_test.rb`, `test/models/mail_template_test.rb`, `test/lib/mail_template_seeds_test.rb`
Trap: a template edited here no longer matches its `seeded_digest`, so `MailTemplateSeeds.load!` reports it `:edited` and skips it — later `db/mail_templates/<tag>.yml` changes never reach that row.
Trap: `MailTemplateResolver` caches compiled templates per process under `[tag, format, updated_at]` — a write that skips `updated_at` (e.g. bare `update_columns`) sends the old wording until restart.

### Ranger Broadcast System (RBS launchpad)
Reach it: `GET /communication/rbs` → Communication Management › Ranger Broadcast
Gate: `ADMIN`, `MEGAPHONE`, `MEGAPHONE_TEAM_ONPLAYA`, `MEGAPHONE_EMERGENCY_ONPLAYA`, `TECH_NINJA` (menu: `Rbs::MEGAPHONE_ROLES`, no `TECH_NINJA`); Records section: `ADMIN`, `TECH_NINJA` only
Controller: `app/controllers/communication/rbs_controller.rb` (`index`)
Owner: `Rbs` (`app/lib/rbs.rb`), `RbsSandbox` (`app/lib/rbs_sandbox.rb`), `RbsPhoneNumbers` (`app/lib/rbs_phone_numbers.rb`)
Touches: `broadcast`, `broadcast_message`, `person`, `setting`
Verify: `test/controllers/communication/rbs_controller_test.rb`, `test/lib/rbs_test.rb`, `test/lib/rbs_sandbox_test.rb`
Trap: `Rbs.event_dates`/`during_event?` ("The event has not started" notice, every `on_site` match) span present-year Labor Day −14 to +5 days, not `EventDate` — Administration › Admin Menu › Event Dates edits don't move them.
Trap: `Rbs::ATTRIBUTES` configures `Broadcast::TYPE_SLOT_EDIT`, but despite a comment nothing in `app/` sends it via `Rbs.transmit` and `Rbs::PAGE_TYPES` omits it — no card, and `RbsBroadcastsController#set_type` rejects it.

### RBS › Send a broadcast (rbs_broadcasts)
Reach it: `GET /communication/rbs/broadcasts/:type` → linked from Ranger Broadcast System type cards; redraw `POST /communication/rbs/broadcasts/:type/edit`; review `POST /communication/rbs/broadcasts/:type/review`; send `POST /communication/rbs/broadcasts/:type`
Gate: `ADMIN`, `MEGAPHONE`, `MEGAPHONE_TEAM_ONPLAYA`, `MEGAPHONE_EMERGENCY_ONPLAYA`, then per-type `Rbs::TYPE_ROLES` (`Rbs.type_allowed?`); `Rbs.team_only?` senders limited to managed positions (`TeamManager.manageable_position_ids`, on review and send); refused on Groundhog Day server (`prevent_if_ghd_server`)
Controller: `app/controllers/communication/rbs_broadcasts_controller.rb` (`new`, `review`, `create`)
Owner: `Rbs` (`app/lib/rbs.rb`: `retrieve_recipients`, `unreachable`, `transmit`, `deliver_queued_sms`/`broadcast_email`/`broadcast_message` via `RbsTransmitSmsJob`/`RbsTransmitEmailJob`/`RbsTransmitClubhouseMessageJob`), `RbsBroadcastForm` (`app/forms/rbs_broadcast_form.rb`), `RbsSandbox` (`app/lib/rbs_sandbox.rb`)
Touches: `broadcast` (w), `broadcast_message` (w), `person_message` (w), `mail_log` (w), `error_logs` (w), `person`, `alert`, `person_alert`, `person_position`, `position`, `slot`, `person_slot`, `timesheet`, `trainee_status`, `team_manager`, `email_suppression`, `setting`
Verify: `test/controllers/communication/rbs_broadcasts_controller_test.rb`, `test/lib/rbs_test.rb`, `test/lib/rbs_sandbox_test.rb`, `test/helpers/partials_render_test.rb`
Trap: only `Rbs` reads `BROADCAST_SMS_SANDBOX`, `BROADCAST_MAIL_SANDBOX`, `BROADCAST_CLUBHOUSE_SANDBOX` (`deliver_queued_sms`, `queue_sms`, `email_mode`, `broadcast_message`, `message_notify`, `notify_by_text`) — direct `SmsService`/`RbsMailer`/SES/`PersonMessage` calls send for real.
Trap: `review`, `create` and a POSTed `new` render 422 on purpose (Turbo discards a 200 sent back to a form; tests assert `:unprocessable_entity`) — don't "fix" them to 200.
Trap: a recipient whose address `email_suppression` holds (see the Rbs entry) reads "bounce or spam report on file" in the Email column of the review table (`rbs_channel_cell`) when the broadcast sends email, and of the sent table (`rbs_queued_cell`), from `Communication::RbsHelper::RECIPIENT_BLOCK_REASONS`. One label fits a bounce and a spam report alike: the lookup doesn't say which, and the person banner does. The review callout's "by email" count and `TransmitResult#emails_queued` leave them out. An address suppressed after Send still gets that one email. A channel the broadcast doesn't use prints "not used" in every row of the review table instead (`rbs_not_used`, from `@form.sends_sms?` and `sends_email?`, which `review.html.erb` passes as `_recipients_table`'s `sms:` and `email:` locals), as the sent table prints "not sent" (`rbs_not_sent`): never a reason or a dash, though `Rbs.build_recipient` works out the block reasons for an unused channel too. Only "Text everyone on shift" (its Email column) and a "General broadcast", "Team or position" or "Shift sign-ups" broadcast with a channel unticked have one.
Trap: an emergency lists people no channel reaches (see the Rbs entry), so its pages carry two counts. The reached count, the list less `Rbs.unreachable`, is the form's "People this would reach now" (`Rbs.receiver_estimate`), the review callout's "Sending reaches N", the Send button, the review table's note past the cap (`_recipients_table`'s `reached:` local; "All N" only when everyone is reached) and `common/rbs/_delivery_summary`'s "Broadcast sent to N". The list is "Recipients (N)", "Delivery (N)" and `broadcast.recipient_count`, with everything on the history that reads it. `rbs_unreachable_sentence` counts and names the difference by callsign, last in the review callout and in the sent callout, so the reached count plus its count is the list. The retried page's is always empty: `retry_result` lists only the people it sent to again, with `sent_clubhouse` false. Every other type has none (`retrieve_recipients` drops them), and a Clubhouse message reaches everyone listed, which is why `unreachable` takes `send_clubhouse:` with no default.

### RBS › Broadcast history
Reach it: `GET /communication/rbs/history` → linked from Ranger Broadcast System › Records; detail `GET /communication/rbs/history/:id`; retry `POST /communication/rbs/history/:id/retry`
Gate: `ADMIN`, `TECH_NINJA`; retry `ADMIN` only (`authorize_ability :retry_broadcast`, `admin: false`, same gate as the Retry button); refused on Groundhog Day server
Controller: `app/controllers/communication/rbs_history_controller.rb` (`index`, `show`, `retry`)
Owner: `Broadcast` (`app/models/broadcast.rb`: `find_for_query`, `recipients`, `attempted_counts`, `failed_messages`), `BroadcastMessage.sendable` (`app/models/broadcast_message.rb`), `Rbs.retry_broadcast`/`Rbs.deliver_retried_emails` (`app/lib/rbs.rb`), `RbsRetryEmailJob` (`app/jobs/rbs_retry_email_job.rb`), `RbsTransmitSmsJob` (`app/jobs/rbs_transmit_sms_job.rb`, which sends retried texts as it sends a broadcast's first ones)
Touches: `broadcast` (w), `broadcast_message` (w), `mail_log` (w), `error_logs` (w), `alert`, `person`, `setting`
Verify: `test/controllers/communication/rbs_history_controller_test.rb`, `test/lib/rbs_test.rb`
Trap: `filter_params` defaults `kind` to `broadcast` before `known_filter`, hiding notification rows (`Broadcast::NOTIFICATION_ALERTS`, e.g. `Rbs.message_notify` alerts) — pass `kind=all` or `kind=notification`; list caps at `LIST_LIMIT` (250).
Trap: the `broadcast` table has no type column and `Broadcast#kind` is inferred only from `alert_id` — filtering history by emergency, general, slot etc. needs a migration.
Trap: an email that did not go records why (`Broadcast::EMAIL_FAIL_STATUSES`: SES's own reason lowercased with dashes, `invalid-parameter` for an address never tried, `send-unconfirmed` where SES may have sent it), and `email_failed` / `BroadcastMessage.count_fail` count every one of them (`Broadcast::FAILURE_STATUSES`), so the badge, callout, "With failures" and the daily report see them all. Retry resends only `failed_messages`, exactly the rows it sends: `Broadcast::RETRYABLE_STATUSES` rows (never `invalid-parameter` or `send-unconfirmed`, so no one gets an email twice) whose person can still be messaged that way. One rule, `BroadcastMessage.sendable`, decides that on every read: the person exists and is outside `Person::NO_MESSAGES_STATUSES`; a text also needs `sms_verified`, not `sms_stopped`, and its `address` still `person.sms_number`; an email goes to its row's address, so nothing more is asked. `retryable?`, the controller guard, the button and its confirm count, `retry_broadcast` and the job's per-batch reload all read it through `failed_messages`. A row a Retry won't send keeps its failure status and stays in `email_failed` / `sms_failed` / `count_fail`, so the broadcast still reads as failed and a reinstated Ranger is retryable again. When nothing is left to send, `Broadcast#retryable?` is false: the callout says the failures cannot go again, there is no Retry button, and `RbsHistoryController#retry` guards on `retryable?`. The confirm count and the callout's "can't be sent again" count read the rows, never `sms_failed + email_failed`, which a running retry recounts only when it is done: `failed_messages`, and `Broadcast#unretryable_messages`, every `FAILURE_STATUSES` row outside `failed_messages` (no longer `Broadcast::UNRETRYABLE_STATUSES`), so the two add up to the failures. `rbs_unretryable_sentence` counts messages, texts and emails alike, with one reason for all three causes. The retry result lists only the people sent to again, so no one in it reads "opted out". The per-person cell (`rbs_recorded_cell`) shows each with its label from `Communication::RbsHelper::MESSAGE_STATUS_LABELS`.
Trap: an email SES reported bounced is `bounced` (`Broadcast::STATUS_BOUNCED`, set by the SNS webhook through `BroadcastMessage.mark_email_bounced`, any bounce type; see SES Mail Events), and a bounce is not a failure: `bounced` is in none of `FAILURE_STATUSES`, `UNRETRYABLE_STATUSES` or `RETRYABLE_STATUSES`, and nothing recounts `email_failed`, so `failed?`, `with_failures`, the list's "Delivered" badge, the callout, the Failed stat, Retry and `DailyReportJob#failed_broadcasts` all leave it out. The cell shows it as "Bounced" in the failure look (`rbs_recorded_cell`: `text-error`, `triangle-exclamation`). The Bounced stat counts the rows (`Broadcast#bounced_messages`), as Texts and Emails do (the stat row trap below), not `@recipients`, which stops at `Broadcast::RECIPIENT_LIMIT` (250); it is `:error` above 0 and neutral at 0, never green: 0 can mean no report came, and none comes until SES Bounce notifications publish to `SES_SNS_TOPIC_ARN`.
Trap: an email a send skipped because `email_suppression` holds the address is recorded `suppressed` (`Rbs::EMAIL_STATUS_SUPPRESSED`; never `bounced`, an email SES reported), with the person's own address, as is a new-message alert's email skipped for the same reason (`message_notify`), and the cell shows it muted as "bounce or spam report on file" (`rbs_recorded_cell` → `RECIPIENT_BLOCK_REASONS`), not "opted out"; anyone else the send won't email, a blank address included, is still `no-contact`. An alert to a suppressed address reads Emails 0, not "—" (its `sent_email` is the preference, and `suppressed` is not in `ATTEMPTED_STATUSES`), and Failed 0. The cell reads "no address" for a `no-contact` row whose address is blank (`blank?`, as the review page's `email.blank?` is, so a whitespace-only address stored before `normalizes :email` too) and "opted out" otherwise. The rule is for the email send's skip rows, which keep the person's own address, never a test-mode one: the cell gets only `{ status:, address: }` and can't see the channel, and only `broadcast_email` writes `no-contact` rows. A row whose address was added or changed between Send and the job still reads "opted out", in an emergency too (#10's accepted case). Neither is a failure: in none of `FAILURE_STATUSES` or `RETRYABLE_STATUSES`, so `email_failed`, `failed?`, the Failed stat and the Retry button leave them out. A Retry never asks the record, so a refused row whose address was suppressed since is sent again (accepted: a Retry resends only rows SES refused).
Trap: the stat row's Texts and Emails count what the send tried, from the rows (`Broadcast#attempted_counts`, one `group(:address_type).count` over `Broadcast::ATTEMPTED_STATUSES`: `sent`, held copies included, `bounced`, `blocked` and every `FAILURE_STATUSES`), not `@recipients`, which stops at `Broadcast::RECIPIENT_LIMIT` (250). `no-contact` and `suppressed` stay out, so Emails matches the results page's "Emails queued" (`TransmitResult#emails_queued`), and People minus Emails is how many were not emailed. The list names what counts, so a new skip reason stays out by itself, but whoever writes a new outcome status must add it to the list: `delivered` if `SmsService.process_status_callback` is ever wired, and `blocked`, listed but never yet written, checked to still fit. A channel the broadcast didn't use (`sent_sms` or `sent_email` false) shows "—", as the results page does. No join to `person`: a deleted person's rows count, as in Failed.

### RBS › Message log
Reach it: `GET /communication/rbs/messages` → linked from Ranger Broadcast System › Records
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/communication/rbs_messages_controller.rb` (`index`)
Owner: `BroadcastMessage.find_for_query` (`app/models/broadcast_message.rb`), `RbsMessageLogFilterForm` (`app/forms/rbs_message_log_filter_form.rb`), `Communication::RbsHelper` (`app/helpers/communication/rbs_helper.rb`: `rbs_direction_cell`, `rbs_direction_word`, `rbs_broadcast_link`, `rbs_direction_options`, `rbs_message_filter_chips`, `MESSAGE_STATUS_LABELS`; Administration › SMS Management borrows the direction cell and word for Twilio's log)
Touches: `broadcast_message`, `person`
Verify: `test/controllers/communication/rbs_messages_controller_test.rb`, `test/lib/rbs_test.rb` (the status and label guards)
Trap: `Infrastructure::SmsController` (inbound texts, unknown phones, replies) and `Alerts::SmsPreferencesService` (verify codes) also write `broadcast_message` rows with `broadcast_id` nil — never inner-join the log to `broadcast`.
Trap: `RbsMessageLogFilterForm#status` keeps only `Broadcast::MESSAGE_STATUSES` — add any new status `BroadcastMessage.record` or `BroadcastMessage.record_outbound` (RBS email, from `Rbs.record_email_batch`, or `Rbs.record_retried_batch` on a retry) writes there, or the status filter silently ignores it. Each status also needs a label in `MESSAGE_STATUS_LABELS` (labels must differ, or two filter boxes read the same). `test/lib/rbs_test.rb` checks that every listed status has a label, and that the email send's two skip statuses (`suppressed`, `no-contact`) are listed and are no failures; every other writer is still checked by hand.
Trap: `suppressed` (`Broadcast::STATUS_SUPPRESSED`, which `Rbs::EMAIL_STATUS_SUPPRESSED` names: an email never sent to an address `email_suppression` holds) is in `MESSAGE_STATUSES`. It reads "Bounce or spam report on file" and sits in the Outcome group, not Email Failure Reason, being no failure. `no-contact` (`Broadcast::STATUS_NO_CONTACT`, which `Rbs::EMAIL_STATUS_NO_CONTACT` and `SMS_STATUS_NO_CONTACT` name; a row only the email send writes, for an opt-out or a blank address) is in `MESSAGE_STATUSES` too. It reads "Opted out or no address on file" and sits in the Outcome group after `suppressed`; an empty Address cell tells no address from an opt-out.
Trap: `send-unconfirmed` (`Broadcast::STATUS_SEND_UNCONFIRMED`) is SES's and Twilio's: a broadcast email SES may have sent, or a single text (a verification code, a new-message alert) Twilio may have taken without answering. It reads "May have been sent" and sits in the Outcome group, though `EMAIL_FAIL_STATUSES` still lists it; `rbs_message_status_options` takes it out of Email Failure Reason. A text's `message_id` is the SID Twilio gave it. `queued` (`Broadcast::STATUS_QUEUED`) is a broadcast's text waiting for `RbsTransmitSmsJob`: "Queued", in the Outcome group, never a failure. Twilio's receipts (see Text delivery receipts) move a sent text to `delivered` ("Delivered"), `blocked`, `bounced` or `failed`; `failed` reads "Not delivered" (it was "SES failure", and still stands for any SES reason not listed) and sits in the Outcome group beside `send-unconfirmed`, both now a text's as well as an email's.
Trap: Direction says which way a row points, never whether it went; the Outcome says what became of it. One pair of words names it everywhere: "outgoing" and "incoming" in the Direction column (`rbs_direction_cell`, through `rbs_direction_word`, which SMS Management's export also writes), leading the filter's options and so its chip ("Outgoing from the Clubhouse", "Incoming from phones": `rbs_direction_options`, which `rbs_message_filter_chips` reads through `rbs_label_for`), and on the inbound stat ("Incoming from phones"). Every row the Clubhouse writes for a message it sends or means to send is `outbound` (`BroadcastMessage.record`, `record_outbound`, the column default), so outgoing rows include ones that never went: the failures (`Broadcast::FAILURE_STATUSES`, but for `send-unconfirmed`, which SES may have sent), `suppressed`, `no-contact`, and `sent` rows nothing left for (held and sandboxed copies, and a new-message alert email whose address was suppressed after it was queued, which `SuppressedRecipientsInterceptor` drops; #31). Keep "sent" and "received" off the page as direction words: the hero, the empty state and the RBS page's Records card say "recorded", and beside "outgoing", "received" reads as an outcome.
Trap: the Outcome filter is two checkbox groups sending the one `status[]` list: the email failure reasons (`Broadcast::EMAIL_FAIL_STATUSES`, via `rbs_message_status_options(email_failures: true)`) sit apart from the rest under "Email Failure Reason".

### RBS › Phone numbers
Reach it: `GET /communication/rbs/phone-numbers` → linked from Ranger Broadcast System › Records
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/communication/rbs_phone_numbers_controller.rb` (`index`)
Owner: `RbsPhoneNumbers` (`app/lib/rbs_phone_numbers.rb`)
Touches: `person`
Verify: `test/controllers/communication/rbs_phone_numbers_controller_test.rb`
Trap: `RbsPhoneNumbers.counts` sums `sms_verified` and `sms_stopped` separately, so a confirmed number that replied STOP is both Confirmed and Asked to stop — count textable numbers via `unusable_count` (unconfirmed OR stopped), never `verified - stopped`.

### Survey Management
Reach it: `GET /communication/survey-management` → Communication Management › Survey Management; create `POST /communication/survey-management`; edit `PATCH /communication/survey-management/:id`; delete `DELETE /communication/survey-management/:id`; copy `POST /communication/survey-management/:id/duplicate`
Gate: `Survey.can_manage_any?` (`ADMIN`, `SURVEY_MANAGEMENT_TRAINING`, or any role composed on `SURVEY_MANAGEMENT_BASE`), then per-survey `Survey#can_manage_survey?`
Controller: `app/controllers/communication/surveys_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `duplicate`), `app/controllers/communication/survey_management_base_controller.rb`
Owner: `Survey` (`app/models/survey.rb`: `find_for_query`, `form_positions`, `type_options_for`, `duplicate_into`, `has_role_for_position?`)
Touches: `survey` (w), `survey_group` (w), `survey_question` (w), `survey_answer` (w), `position`, `action_logs` (w)
Verify: `test/controllers/communication/surveys_controller_test.rb`, `test/models/survey_test.rb`, `test/lib/communication_menu_test.rb`
Trap: `create` stamps the viewed year (`@year` from `setup_year`), but `duplicate` always copies into `current_year` — a copy made while viewing 2024 lands in the live year.
Trap: read the survey id only via `survey_id_param` (`SurveysController` overrides it to `params[:id]`) — `params[:survey_id] || params[:id]` lets a query-string `?survey_id=` pick which survey a DELETE removes.

### Survey Management › Survey page (groups & questions)
Reach it: `GET /communication/survey-management/:id` → linked from Survey Management (Manage); add group `POST /communication/survey-management/:survey_id/groups`; add question `POST /communication/survey-management/:survey_id/questions`; reorder `PATCH /communication/survey-management/:survey_id/groups/:id/move`, `PATCH /communication/survey-management/:survey_id/questions/:id/move`
Gate: `Survey.can_manage_any?`, then `load_survey` requires `Survey#can_manage_survey?` (person must manage surveys for its position)
Controller: `app/controllers/communication/surveys_controller.rb` (`show`), `app/controllers/communication/survey_groups_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`, `move`), `app/controllers/communication/survey_questions_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`, `move`), `app/controllers/communication/survey_management_base_controller.rb` (`load_survey`, `move_line`, `survey_page_path`)
Owner: `SurveyGroup` (`app/models/survey_group.rb`), `SurveyQuestion` (`app/models/survey_question.rb`), `SortIndexLine` (`app/models/concerns/sort_index_line.rb`)
Touches: `survey_group` (w), `survey_question` (w), `survey_answer` (w), `survey`, `action_logs` (w)
Verify: `test/controllers/communication/survey_groups_controller_test.rb`, `test/controllers/communication/survey_questions_controller_test.rb`, `test/controllers/communication/surveys_controller_test.rb`, `test/models/survey_group_test.rb`, `test/models/survey_question_test.rb`
Trap: `survey_page_path` passes the saved group as `?group=<id>`, not `#group-<id>`, because Turbo drops a redirect's fragment after a form submit — keep the param (`SurveysController#show` reads it into `@focus_group_id`), not `anchor:`.
Trap: `sort_index` values repeat on real rows — always order with the `ordered` scope (`sort_index, id`); `SortIndexLine#move` renumbers via `update_columns`, skipping validations and writing no `action_logs` row.

## Admin

Every controller inherits `ApplicationController` directly (`layout "admin"`) and gates with `authorize_role` (`app/helpers/authorize_helper.rb`, no Admin pass); `authorize_ability` (`app/lib/authorization/role_gate.rb`) admits Admin unless `admin: false`. Each `Menus::ADMIN` `visible_if` equals its controller's `authorize_role` (`test/lib/admin_menu_test.rb`). Only Online Courses has a viewed year (`setup_year`, `year_floor` 2022, default present year).

### Documents
Reach it: `GET /admin/documents` → Administration › Admin Menu › Documents; preview `GET /admin/documents/:id/body`; new `GET /admin/documents/new`; edit `GET /admin/documents/:id/edit`
Gate: `ADMIN`
Controller: `app/controllers/admin/documents_controller.rb` (`index`, `body`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `Document` (`app/models/document.rb`)
Touches: `document` (w), `action_logs` (w), `person`, `position`, `team`
Verify: `test/controllers/admin/documents_controller_test.rb`, `test/models/document_test.rb`, `test/models/role_cache_invalidation_test.rb`, `test/system/rich_text_editor_test.rb`
Trap: `Document.find_all` omits `body` (`Document::LIST_COLUMNS`), so `.body` on an index row raises `ActiveModel::MissingAttributeError` — load the text through the `body` turbo-frame action.
Trap: Nothing checks tags against `Document.referenced_tags`, so a rename breaks lookups; saving, renaming or deleting `dept-nda` runs `RoleManager.purge_all` (`Rails.cache.clear`) since it gates unsigned Event Managers' roles (`RoleManager#retrieve_roles`).

### Event Dates
Reach it: `GET /admin/event-dates` → Administration › Admin Menu › Event Dates; new `GET /admin/event-dates/new`; edit `GET /admin/event-dates/:id/edit`
Gate: `ADMIN`, `TECH_NINJA`; create/edit `authorize_ability :manage_event_dates` (Admin or `TECH_NINJA`); delete `authorize_ability :delete_event_dates` (`ADMIN` only)
Controller: `app/controllers/admin/event_dates_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `EventDate` (`app/models/event_date.rb`)
Touches: `event_dates` (w), `action_logs` (w)
Verify: `test/controllers/admin/event_dates_controller_test.rb`, `test/models/event_date_test.rb`, `test/lib/admin_menu_test.rb`
Trap: Comments in `Admin::EventDatesController` and `config/routes.rb` say Edit Slots reads this page, but `authorize_role` sends `EDIT_SLOTS` to /me (test-pinned) — widen it and the menu item together.
Trap: `EventDate.find_for_year` keeps only a year's first row, so `event_year_is_not_already_recorded` refuses a second record — correct the existing row instead.

### OAuth Clients
Reach it: `GET /admin/oauth-client` → Administration › Admin Menu › OAuth Clients; new `GET /admin/oauth-client/new`; edit `GET /admin/oauth-client/:id/edit`; Save with New Secret `PATCH /admin/oauth-client/:id` with `new_secret`
Gate: `TECH_NINJA` only (no Admin pass)
Controller: `app/controllers/admin/oauth_clients_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`)
Owner: `OauthClient` (`app/models/oauth_client.rb`)
Touches: `oauth_client` (w), `oauth_code` (w), `action_logs` (w)
Verify: `test/controllers/admin/oauth_clients_controller_test.rb`, `test/models/oauth_client_test.rb`, `test/system/copy_to_clipboard_test.rb`
Trap: `before_validation :generate_secret, on: :create` discards any secret posted to `create` — type one only on an existing client; `update` regenerates for `new_secret` only after `valid?` passes.
Trap: `OauthClient#accepts_redirect_uri?` returns true for a blank `redirect_uri` and its format validation is commented out, so a client saved without one accepts any address.

### Online Courses
Reach it: `GET /admin/online-course` → Administration › Admin Menu › Online Courses; catalog `GET /admin/online-course/moodle-catalog` (rows `GET /admin/online-course/moodle-catalog-courses`); enrollment `GET /admin/online-course/:id/enrollment` (rows `GET /admin/online-course/:id/enrollment-roster`); sync name `POST /admin/online-course/:id/set-name`
Gate: `ADMIN`; the Groundhog Day Server skips live LMS lookups (`moodle_lookup`) but still runs `set_name`
Controller: `app/controllers/admin/online_courses_controller.rb` (`index`, `new`, `create`, `edit`, `update`, `destroy`, `set_name`, `enrollment`, `enrollment_roster`, `moodle_catalog`, `moodle_catalog_courses`)
Owner: `OnlineCourse` (`app/models/online_course.rb`), `Moodle` (`app/lib/moodle.rb`)
Touches: `online_course` (w), `action_logs` (w), `error_logs` (w), `position`, `person`, `setting`
Verify: `test/controllers/admin/online_courses_controller_test.rb`, `test/lib/moodle_test.rb`
Trap: `Moodle.new` raises `RuntimeError` on a blank MoodleDomain/MoodleToken/MoodleServiceName/MoodleStudentRoleID (`throw_on_empty: true`), which `rescue_moodle_errors` shows as "Could not reach the LMS" — check settings before the network.
Trap: `set_name` uses `update_column(:name, ...)`, skipping validations and `audit_model`, so a name sync writes no `online-course-update` row in `action_logs`, unlike every form save.

### Admin › Passkeys
Reach it: `GET /admin/passkeys` → Administration › Admin Menu › Passkeys
Gate: `ADMIN` (not gated on `Passkeys.enabled?`)
Controller: `app/controllers/admin/passkeys_controller.rb` (`index`)
Owner: `PersonPasskey` (`app/models/person_passkey.rb`), `PasskeyFilterForm` (`app/forms/passkey_filter_form.rb`)
Touches: `person_passkey`, `person`
Verify: `test/controllers/admin/passkeys_controller_test.rb`, `test/models/person_passkey_test.rb`
Trap: Read-only on purpose — removal is `Person::PasskeysController#destroy` (`DELETE /person/:person_id/passkeys/:id`) on the person's passkeys page, which each row links to via `person_passkeys_path`.
Trap: "Added by an Admin" reads the `added_by_person_id` column (`PersonPasskey#added_by_admin?`, scope `added_by_an_admin`), never the `added_by` association — the enrolling Admin's account may be gone.

### Permissions
Reach it: `GET /admin/permissions` → Administration › Admin Menu › Permissions; edit `GET /admin/permissions/:id/edit`; Create ART Permissions `GET /admin/permissions/art` → `POST /admin/permissions/art`
Gate: `ADMIN`, `TECH_NINJA` to read; edit, delete and ART creation `authorize_ability :manage_permissions` = `TECH_NINJA` only (`admin: false`)
Controller: `app/controllers/admin/permissions_controller.rb` (`index`, `edit`, `update`, `destroy`, `new_art`, `create_art`)
Owner: `Role` (`app/models/role.rb`), `ArtPermissionForm` (`app/forms/art_permission_form.rb`), `RoleManager` (`app/lib/role_manager.rb`)
Touches: `role` (w), `person_role` (w), `team_role` (w), `position_role` (w), `position`, `team`, `action_logs` (w)
Verify: `test/controllers/admin/permissions_controller_test.rb`, `test/models/role_test.rb`
Trap: Deleting a permission drops its `person_role`, `team_role` and `position_role` rows via `dependent: :delete_all` (unaudited), and every write runs `RoleManager.purge_all` — `Rails.cache.clear`, the whole cache.
Trap: `Role.create_art_roles` raises `ArgumentError` for a non-training, inactive or "Training"-less position — the ART picker must offer `Position.find_for_query({ art_training: true, active: true })` (positional hash, not keywords).

### RBS Alerts
Reach it: `GET /admin/rbs-alerts` → Administration › Admin Menu › RBS Alerts; edit `GET /admin/rbs-alerts/:id/edit`
Gate: `ADMIN`, `TECH_NINJA` to read; edit `authorize_ability :manage_rbs_alerts` = `TECH_NINJA` only (`admin: false`)
Controller: `app/controllers/admin/rbs_alerts_controller.rb` (`index`, `edit`, `update`)
Owner: `Alert` (`app/models/alert.rb`)
Touches: `alert` (w), `action_logs` (w)
Verify: `test/controllers/admin/rbs_alerts_controller_test.rb`, `test/models/alert_test.rb`
Trap: Code keys alerts by id (`Alert::SHIFT_CHANGE` through `Alert::MENTOR_CONTACT`, `sms_only`/`email_only`/`no_opt_out`), so routes are edit-only and a test pins that alerts cannot be created or deleted.
Trap: The edit page says `on_playa` only picks which group lists the alert, but `RbsMailer#broadcast` (`db/mail_templates/rbs_mailer/broadcast.yml`) and `DailyReportMailer#broadcast_alert` print it as "On Playa"/"Pre-Event"; no `Rbs` delivery rule reads it.

### Salesforce Query
Reach it: `GET /admin/salesforce-query` → Administration › Admin Menu › Salesforce Query; run `POST /admin/salesforce-query` (answers two turbo-stream updates at 200)
Gate: `TECH_NINJA` only (no Admin pass); `run` refused on the Groundhog Day Server (`prevent_if_ghd_server`)
Controller: `app/controllers/admin/salesforce_query_controller.rb` (`index`, `run`)
Owner: `SalesforceQuery` (`app/lib/salesforce_query.rb`), `Salesforce` (`app/lib/salesforce.rb`) (not `ProspectiveApplicationImport`, which runs its own fixed queries)
Touches: `action_logs` (w), `error_logs` (w), `setting`
Verify: `test/controllers/admin/salesforce_query_controller_test.rb`, `test/system/admin/salesforce_query_test.rb`, `test/lib/salesforce_query_test.rb`, `test/lib/salesforce/mock_connector_test.rb`, `test/lib/salesforce_test.rb`, `test/lib/admin_menu_test.rb`
Trap: Not offline in development: `Salesforce.connector` reaches the live org with the dev database's production credentials unless `Rails.env.development?` and `ENV["SF_MOCK_DATA"]` select `Salesforce::MockConnector` — the Results heading then shows a Mock Data badge; no badge, no Run.
Trap: `run` answers 200 with turbo streams on purpose — `RequestLogger` keeps a 422's params and page in `request_log`, which Admins without Tech Ninja can read, so the house 422 re-render would store the SOQL and the records; don't "fix" it to 422.
Trap: A statement opening with `FIND` goes to the SOSL search (`Salesforce#sosl_search`, `GET …/search/?q=`), anything else to the SOQL query; the search answer is `searchRecords` only — no `totalSize`, never paged, object types mixed — so the table leads with `attributes.type`.
Trap: Only Salesforce's first batch (up to 2,000 records) is shown — `nextRecordsUrl` is never followed, so `totalSize` can exceed the rows and sorting (in the browser, `table_sort_controller.js`) reorders only the rows shown.
Trap: `soql_query(…, log_rejections: false)` keeps only an HTTP 400 out of `error_logs`; a 401/403/5xx or a timeout still writes `salesforce-query-exception` with the SOQL, an undecodable 200 writes `salesforce-json-exception` (SOQL plus 2,000 characters of body), and a 200 without a records list writes `salesforce-query-failed` (SOQL plus the whole decoded result).

### System Settings
Reach it: `GET /admin/settings` → Administration › Admin Menu › Settings; edit `GET /admin/settings/:id/edit` (`:id` is the setting name)
Gate: `ADMIN`; a credential setting (`Setting#is_credential`) also needs `TECH_NINJA` (`set_setting`)
Controller: `app/controllers/admin/settings_controller.rb` (`index`, `edit`, `update`)
Owner: `Setting` (`app/models/setting.rb`), `SettingsSearchForm` (`app/forms/settings_search_form.rb`)
Touches: `setting` (w)
Verify: `test/controllers/admin/settings_controller_test.rb` (saving an unstored setting, and the error each refusal shows), `test/models/role_cache_invalidation_test.rb`, `test/models/setting_test.rb`, `test/lib/admin_menu_test.rb` (menu gate only)
Trap: An unstored setting is a new record, so its edit form passes `method: :patch` -- without it `form_with` POSTs to `/admin/settings/:id`, which has no route, and the save is lost.
Trap: `Setting` has no `audit_model`, so saves write no `action_logs` row, and the "Setting Changes" filter (`setting-%`) and `DailyReportJob::SETTING_EVENTS` (`setting-update`) find nothing this app writes.
Trap: `Setting.find` never raises (nil if unknown, unsaved `Setting.new` if unstored), and `cache_delete("*")` clears only a key named `*` — the real clear is `Setting#clear_cache` (after_commit; see the Settings (feature switches) trap), plus `RoleManager.purge_all` for `RoleManager::ROLE_SETTINGS`.

### Shift Coverage Management
Reach it: `GET /admin/shift-coverage-management` → Administration › Admin Menu › Shift Coverage Setup; shift type `GET /admin/shift-coverage-management/:id`; new `GET /admin/shift-coverage-management/new`; edit `GET /admin/shift-coverage-management/:id/edit`; reorder `PATCH /admin/shift-coverage-management/:id/move?direction=up|down`; a shift type's posts live under it at `/admin/shift-coverage-management/:shift_coverage_group_id/posts` (new `GET …/posts/new`, edit `GET …/posts/:id/edit`, create `POST`, update `PATCH`, delete `DELETE …/posts/:id`, reorder `PATCH …/posts/:id/move?direction=up|down`)
Gate: `ADMIN`, `TECH_NINJA` (`authorize_role` on `Admin::ShiftCoverageBaseController`, no Admin pass)
Controller: `app/controllers/admin/shift_coverage_groups_controller.rb` (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`, `move`), `app/controllers/admin/shift_coverage_positions_controller.rb` (`new`, `create`, `edit`, `update`, `destroy`, `move`); the move is `LineMoveConcern`, which the survey management pages share
Owner: `ShiftCoverageGroup` (`app/models/shift_coverage_group.rb`), `ShiftCoveragePosition` (`app/models/shift_coverage_position.rb`) (not `PositionLineupManagement`, which groups positions for the Schedule page)
Touches: `shift_coverage_group` (w), `shift_coverage_position` (w), `position`, `action_logs` (w)
Verify: `test/controllers/admin/shift_coverage_groups_controller_test.rb`, `test/controllers/admin/shift_coverage_positions_controller_test.rb`, `test/models/shift_coverage_group_test.rb`, `test/models/shift_coverage_position_test.rb`, `test/lib/admin_menu_test.rb`
Trap: `shift_coverage_position.position_ids` holds `[id]`/`[id, "Label"]` entries, not ids — read it through `position_id_list`/`labels_by_position`; both JSON columns are LONGTEXT + `json_valid`, so the models need `serialize coder: JSON` and fixtures write them as JSON strings, spelled the way the app writes them (no space after a comma) or a loaded row reads as already changed.
Trap: The slug rides in `?type=` and the CSV filename — renaming one breaks saved links; renaming or deleting `command` moves the report's default, and the Scheduling › Shift Coverage sidebar link (it carries no `?type=`), to the first shift type. MariaDB compares the slug case-insensitively, so `Command` also reports "already uses that slug"; `all` is a slug like any other, because the report's link params keep the shift type out of `active_filters`.
Trap: `PositionManagement.destroy` strips a deleted position from both JSON columns; a list it empties stays and reads nothing, and a shift type or a post refuses its next save until a position is chosen.
Trap: A post is only ever found through its shift type (`@group.shift_coverage_positions.find`), so another shift type's post answers 404. A post's title is its column heading: at most 20 characters and unique within its shift type; a shift type's title is unique outright, because the report's menu names it alone. Both titles are trimmed by a `title=` setter (not `normalizes`, which would also rewrite `where` and `update_column`) and compared case-insensitively, as slugs are; labels are at most 20 too.
Trap: `base_position_ids=` keeps ids already stored in their places: the Period Positions boxes post in title order, so without it an untouched save of a list stored in another order (seeded Mentors is `[9, 1]`) rewrote it and logged a change. A headcount post's labels stay stored but are not shown on the shift type page, since the report never prints them.
Trap: The post form sends its rows as two flat lists, `row_position_ids[]` and `row_labels[]`, which `ShiftCoveragePosition.entries_from_rows` pairs. Keep them flat: `params.expect` given a list of hashes in single brackets silently drops the rows. A refused save redraws the rows as sent, and each problem's `errors.details` carries `row:`, which marks that row's controls.
Trap: Reorders renumber with `update_columns` (`SortIndexLine`), so a move writes no `action_logs` row.
Trap: The menu item is "Shift Coverage Setup" while the page is "Shift Coverage Management": the longer label wraps in the 180px sidebar and touches the next header.

### Action Logs
Reach it: `GET /admin/action-logs` → Administration › System Logs › Action Logs
Gate: `ADMIN`
Controller: `app/controllers/admin/action_logs_controller.rb` (`index`)
Owner: `ActionLog` (`app/models/action_log.rb`), `ActionLogFilterForm` (`app/forms/action_log_filter_form.rb`), `Admin::ActionLogsHelper` (`app/helpers/admin/action_logs_helper.rb`)
Touches: `action_logs`, `person`, `slot`, `position`, `role`, `team`
Verify: `test/controllers/admin/action_logs_controller_test.rb`, `test/models/action_log_test.rb`, `test/helpers/admin/action_logs_helper_test.rb`
Trap: Unfiltered, `ActionLog.find_for_query` skips `count`: the total is last id minus first id plus one, with `:approximate_total` set; only a filtered query counts. The page itself is Pagy's countless mode (2026-10-26, SMS Management issue 16): `find_for_query` returns `{ action_logs:, pagy:, total:, approximate_total: }`, the pager reads the Pagy and `action_log_pager_summary` the total, and a callsign no one has runs the same query on `ActionLog.none` (the estimate is asked of the scope, so it finds none). One change from before: a filter with no matches on a hand-typed page past 1 now shows Previous, as an unknown callsign and any other page past the end already did.
Trap: `user_agent` is the raw `User-Agent` header (`ActionLog.record` via `Current.user_agent`) — `Admin::ActionLogsHelper` must return plain strings for the view to escape, never `html_safe`.
Trap: a typed From or Until counts only when it names a whole date (`UiComponents::FilterBarHelper.filter_time`, which every admin log filter and the on-duty page read their times through); `Time.zone.parse` alone reads "26" as the 26th of this month, which this page did until 2026-10-25. A time it cannot read narrows nothing and draws no chip (`ActionLogFilterForm#query_params`).

### Background Jobs
Reach it: `GET /admin/jobs` → Administration › System Logs › Background Jobs; retry `POST /admin/jobs/:id/retry`, delete `DELETE /admin/jobs/:id`, retry all `POST /admin/jobs/retry-all`, delete all failed `DELETE /admin/jobs/failed`
Gate: `TECH_NINJA` only (no Admin pass)
Controller: `app/controllers/admin/jobs_controller.rb` (`index`, `retry`, `destroy`, `retry_all`, `destroy_failed`)
Owner: `BackgroundJobs` (`app/lib/background_jobs.rb`), `JobFilterForm` (`app/forms/job_filter_form.rb`), `Admin::JobsHelper` (`app/helpers/admin/jobs_helper.rb`); the rows are Solid Queue's own models (`SolidQueue::Job`, `SolidQueue::FailedExecution`, `SolidQueue::Process`)
Touches: `solid_queue_jobs` (w), `solid_queue_failed_executions` (w), `solid_queue_ready_executions` (w), `solid_queue_scheduled_executions` (w), `solid_queue_blocked_executions` (w), `solid_queue_claimed_executions`, `solid_queue_processes`, `action_logs` (w)
Verify: `test/controllers/admin/jobs_controller_test.rb`, `test/lib/admin_menu_test.rb`
Trap: a running job cannot be deleted — `SolidQueue::ClaimedExecution#discard` raises `UndiscardableError`, which is `destroy`'s only guard (the row offers no Delete). Retry is `FailedExecution#retry`: it resets the attempt counters in `arguments`, re-dispatches and removes the failure row, and the job keeps its id. Retry All (`BackgroundJobs.retry_failed`) does the same one job at a time, on purpose: the gem's `FailedExecution.retry_all` keeps the old counters, so a job retried that way can be discarded by `retry_on` at once.
Trap: `SolidQueue::Job#status` reads five `has_one` executions in the order ready, claimed, failed, scheduled, blocked, and `BackgroundJobs.page` preloads them all. A status filter joins its execution, and a join on a preloaded association makes Rails eager-load every preload as a join, so `page` hands Pagy the count of the scope without them; a page past the last is asked for again as the last. In a test, `SolidQueue::Job.create!` makes a `ReadyExecution` for a due job (`after_create :prepare_for_execution`), so a failed fixture destroys that row before `failed_with`, or `status` reads `:ready`.
Trap: `arguments` is the whole Active Job payload and can carry addresses (mail jobs); `Admin::JobsHelper#job_arguments_json` runs it through `filter_parameters` before printing. In development and production the queue models read through the `queue` connection (`connects_to`), so they cannot join `person` or any primary table.

### Bug Reports
Reach it: `GET /admin/bug-reports` → Administration › System Logs › Bug Reports; purge `DELETE /admin/bug-reports`
Gate: `TECH_NINJA` only (no Admin pass)
Controller: `app/controllers/admin/bug_reports_controller.rb` (`index`, `purge`)
Owner: `BugReport` (`app/models/bug_report.rb`) (not `BugReportsController`, which files reports from the navbar dialog)
Touches: `bug_report` (w), `person`, `action_logs` (w)
Verify: `test/controllers/admin/bug_reports_controller_test.rb`, `test/lib/bug_report_menu_test.rb`, `test/lib/admin_menu_test.rb`
Trap: Refusing a non-Tech-Ninja Admin is deliberate (controller test pins it), unlike Clubhouse 1 Log, Error Logs and Request Log, which admit `ADMIN` — do not align it with them.
Trap: Never paged: `BugReport.for_log` shows the newest `BugReport::LIST_LIMIT` (200), and `index` counts the table only when that page is full.

### Clubhouse 1 Log
Reach it: `GET /admin/clubhouse1-log` → Administration › System Logs › Clubhouse 1 Log
Gate: `ADMIN`, `TECH_NINJA`; refused on the Groundhog Day Server (`prevent_if_ghd_server`)
Controller: `app/controllers/admin/clubhouse1_log_controller.rb` (`index`)
Owner: `Clubhouse1Log` (`app/models/clubhouse1_log.rb`), `Clubhouse1LogFilterForm` (`app/forms/clubhouse1_log_filter_form.rb`), `Admin::Clubhouse1LogHelper` (`app/helpers/admin/clubhouse1_log_helper.rb`)
Touches: `log`, `person`
Verify: `test/controllers/admin/clubhouse1_log_controller_test.rb`, `test/models/clubhouse1_log_test.rb`
Trap: `event` is unindexed across about 2.4 million rows, so `Clubhouse1Log.find_for_query` pages with Pagy's countless mode, which fetches `page_size + 1` rows for previous/next and never counts — do not add a total. It returns `[pagy, rows]`; an unknown person, and an `event_text` with a four-byte character the column cannot hold, run the same query on `none`.
Trap: `TECH_NINJA` is not in `PersonConcern::VIEW_ROLES`, so `callsign_link` bounces a Tech Ninja to /me — use `person_display_link`, as `Admin::Clubhouse1LogHelper` does.

### Error Logs
Reach it: `GET /admin/error-log` → Administration › System Logs › Error Logs; purge `DELETE /admin/error-log`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/admin/error_logs_controller.rb` (`index`, `purge`)
Owner: `ErrorLog` (`app/models/error_log.rb`), `ErrorLogFilterForm` (`app/forms/error_log_filter_form.rb`), `Admin::ErrorLogsHelper` (`app/helpers/admin/error_logs_helper.rb`)
Touches: `error_logs` (w), `person`, `action_logs` (w)
Verify: `test/controllers/admin/error_logs_controller_test.rb`
Trap: `ErrorLog.record` and `record_exception` store `request.parameters.to_hash` unfiltered despite a "filtered copy" comment — a new `data` reader must mask, as `Admin::ErrorLogsHelper#error_log_filtered_data` does at render.
Trap: `ErrorLog#data` raises `JSON::ParserError` on legacy non-JSON rows — use `data_or_nil`; `find_for_query` takes `start_at`/`ends_at`, not the `start_time`/`end_time` of its sibling logs.

### Admin › Mail Log (System Mail Log)
Reach it: `GET /admin/mail-log` → Administration › System Logs › Mail Log; message body `GET /admin/mail-log/:id/body`
Gate: `ADMIN`
Controller: `app/controllers/admin/mail_log_controller.rb` (`index`, `body`)
Owner: `MailLog` (`app/models/mail_log.rb`), `MailLogFilterForm` (`app/forms/mail_log_filter_form.rb`), `MailLogHelper` (`app/helpers/mail_log_helper.rb`)
Touches: `mail_log`, `broadcast`, `person`
Verify: `test/controllers/admin/mail_log_controller_test.rb`, `test/models/mail_log_test.rb`, `test/helpers/mail_log_helper_test.rb`
Trap: The table partial and body view in `app/views/common/mail_log/` are shared with Person › Mail Log — a change there changes both pages, the notice for a row whose text was never kept included (see Person › Mail Log).
Trap: Group messages keep subject/body on `broadcast` (`MailLog#subject`/`#body`), so subject search LEFT JOINs it — keep `MailLog.find_for_query` columns table-qualified; `MailLog::LIST_COLUMNS` omits `body`, so `#body` raises on a non-group list row.

### Request Log
Reach it: `GET /admin/request-logs` → Administration › System Logs › Request Log; Live mode `GET /admin/request-logs?mode=live`; expire `DELETE /admin/request-logs/expire`
Gate: `ADMIN`, `TECH_NINJA`
Controller: `app/controllers/admin/request_logs_controller.rb` (`index`, `expire`; `index` renders the Live mode when `mode=live`)
Owner: `RequestLog` (`app/models/request_log.rb`), `RequestLogFilterForm` (`app/forms/request_log_filter_form.rb`), `RequestLogger` (`lib/middleware/request_logger.rb`), `RequestLogLiveChannel` (`app/channels/request_log_live_channel.rb`)
Touches: `request_log` (w), `action_logs` (w), `error_logs` (w), `person`, `setting`
Verify: `test/controllers/admin/request_logs_controller_test.rb`, `test/models/request_log_test.rb`, `test/integration/request_logger_test.rb`, `test/helpers/admin/request_logs_helper_test.rb`, `test/channels/request_log_live_channel_test.rb`
Trap: Live mode is pull, not push — `RequestLogLiveChannel` polls `request_log` itself (`periodically`, 2 s per subscriber) and never `stream_from`s, so the `turbo_stream_from "request-log"` in `_live` only builds the tag, and a `broadcast_*_to "request-log"` reaches nobody.
Trap: the feed's cursor is not a bare id watermark. A lower id can commit after a higher one was sent, so each tick re-reads `LOOKBACK` ids below the newest one sent and skips the ids it has sent; a new subscription is handed the ids the page shows (`data-shown`), and more than `BATCH_LIMIT` waiting replaces the list (`update`) rather than prepending a slice with a hole beneath it.
Trap: the subscription exists only while the tab is showing — `live_log_controller.js` builds the stream element from a `<template>` and removes it when the tab is hidden, and the page opts out of Turbo's cache (`turbo_exempts_page_from_cache`), so Back fetches it again instead of restoring a second subscriber.
Trap: Only `RequestLogger` writes rows, and only while `RequestLogEnabled` is on — false in `test/fixtures/setting.yml`, so a test must turn it on, as `test/integration/request_logger_test.rb` does.
Trap: `Admin::RequestLogsController#resolve_person_id` reads a bare number as a person id before a callsign (the opposite of `Admin::Clubhouse1LogController`), so a digits-only callsign cannot be searched here.

### SMS Management
Reach it: `GET /admin/sms-management` → Administration › System Logs › SMS Management; export `GET /admin/sms-management.csv` (the newest 1,000 texts the filters match); the Twilio Account panel `GET /admin/sms-management/twilio` and the log `GET /admin/sms-management/messages`, each loaded into a lazy frame (`?refresh=1` asks for the panel past its cache); where Twilio sends incoming texts `PATCH /admin/sms-management/incoming` (the panel's Update Incoming Address, answering into its frame); Look Up a Number `POST /admin/sms-management/lookup` (into its own frame, 422)
Gate: `TECH_NINJA` only (no Admin pass); the Edit Twilio Settings button shows only to an `ADMIN` as well, since Settings is Admin-only. Update Incoming Address is never offered or allowed on the training server, whose Twilio Account panel asks Twilio nothing at all ("Live Twilio account reads are not available on the Groundhog Day Server", the owner's ruling of 2026-10-26, as LMS lookups are skipped there); its log and export ask Twilio nothing either, and it offers no export (ruled the same day)
Controller: `app/controllers/admin/sms_management_controller.rb` (`index`, `twilio`, `messages`, `update_incoming`, `lookup`)
Owner: `TwilioMessageLog` (`app/lib/twilio_message_log.rb`), `TwilioStatus` (`app/lib/twilio_status.rb`), `TwilioAccount` (`app/lib/twilio_account.rb`: the settings, `build_client` with its 5-second timeout, `ERRORS` and how each reads (`describe`, `unanswered?`, `slow_answer?`), `usable_id?`, `messaging_service_problem`; `SmsService` sends with it too), `SmsManagement` (`app/lib/sms_management.rb`: `incoming_changes_allowed?`, `incoming_url_problem`, `point_incoming_texts`), `SmsFilterForm` (`app/forms/sms_filter_form.rb`), `Admin::SmsManagementHelper` (`app/helpers/admin/sms_management_helper.rb`); the direction cell and word are `Communication::RbsHelper`'s, dates read through `UiComponents::FilterBarHelper.filter_time`, times print through `DateTimeHelper#log_time_format`, `TwilioLookup` (`app/lib/twilio_lookup.rb`: Look Up a Number)
Touches: `setting`, `person` (whose number a text has), `action_logs` (w); Twilio's REST API: reads the account, balance, Notify services, the Messaging Service, message list and Monitor alerts, and writes one thing, how that Messaging Service handles incoming texts (its address, method, fallback address and number deferral); and Lookup v2 for one number at a time
Verify: `test/controllers/admin/sms_management_controller_test.rb`, `test/lib/twilio_status_test.rb`, `test/lib/twilio_lookup_test.rb`, `test/lib/sms_service_test.rb` (`TwilioAccount.build_client`'s timeout), `test/controllers/admin/settings_controller_test.rb` (TwilioMessagingServiceId is a credential), `test/lib/admin_menu_test.rb`, `test/helpers/ui_components/filter_bar_helper_test.rb` (`filter_time`)
Trap: the log is Twilio's own message list, never `broadcast_message`: the Clubhouse's record of what it asked Twilio to send is RBS › Message log. A text's row keeps the SID Twilio gave it, and Twilio's receipts move it on (see Text delivery receipts), so RBS › Message log says whether a text arrived; this log is what Twilio itself lists.
Trap: the settings card's Delivery Reports row reads "Off" where `SmsService.receipt_address` is nil (dev's localhost), "Received" with when the newest text Twilio has reported on was sent (`BroadcastMessage.last_text_receipt_at`: one query over the latest `RECEIPT_LOOKBACK` (2,000) texts, never the whole table), or "None yet". It is the text's send time, not the receipt's: no row keeps when a receipt came.
Trap: Twilio filters its message list only by `To`, `From` and the UTC date sent (`DateSent>` and `DateSent<` take `YYYY-MM-DD`, no time of day), so those are the log's only filters: no direction or status filter, and no total to page against. `SmsFilterForm` sends the UTC date of whatever moment a value names (20:00 in Arizona is the next day's date). Twilio pages by a token it hands back: `TwilioMessageLog.neighbour` reads `Page` and `PageToken` out of Twilio's next and previous links into `filter[page]` and `filter[page_token]`, and `SmsFilterForm` drops a token Twilio could not have written, starting again at page 0. The pager says "Page N" only, and a later page that comes back empty keeps it, saying "Twilio lists no more texts."
Trap: To and From take a callsign or a number. `TwilioMessageLog.number_for` keeps whatever `SmsService.normalize_phone` makes a number of, and reads anything else through `Person.resolve_callsign` (the exact callsign, else the only one that matches once spacing and punctuation go), using its `sms_number`; a callsign that could be two people, or one with no number, matches nothing, and Twilio is not asked. The Person column matches each text's number at the Ranger's end exactly to `person.sms_number`, the lowest id where two people share one, as the inbound webhook's `Person.find_by_sms_number` does, so a number stored in another form finds no one.
Trap: the export writes the Number column as the page shows it (`PhoneFormatter.format`), and one PhoneFormatter leaves bare (a `+` and digits) with a leading apostrophe, so a spreadsheet keeps it as text instead of dropping the `+`.
Trap: the panel's "Texts, Last 24 Hours" asks Twilio for the UTC date the window opens and trims by each text's own `date_sent`. Twilio lists newest first, so past `TwilioStatus::MESSAGE_LIMIT` (1,000) texts the counts are a sample, and the panel says so, unless that page already reaches back past the window's start. Open question (2026-10-25): Twilio's `date_sent` is nullable and its list is sorted and filtered by it, so a text Twilio never sent (`failed`) may have none and be missing from these counts and from a date-filtered log; one read-only look at a failed text on the live account would settle it.
Trap: the account panel's frame is an ordinary lazy frame: each visit, page turn or filter asks for it again, and the 5-minute cache answers. It was `data-turbo-permanent` until 2026-10-25, and Turbo then carried the loaded frame over from its cached snapshot, so a return visit through the menu showed the old panel and never asked again. The log's frame targets `_top`: its pager links visit the page, so the address and the filter bar stay in step, and the frame reloads from its new `src`. Both frame actions skip `build_menu_items`.
Trap: `TwilioStatus.fetch` caches the answers for 5 minutes under `["twilio-status", CACHE_VERSION, digest]`, the digest of the SID, token, Messaging Service id and Notify service ids, so a corrected setting is asked about at once; bump `CACHE_VERSION` whenever what `read` returns changes shape, or a deploy hands the new panel an answer the old code cached. A read missing an answer Twilio never gave (no connection, a timeout, an answer that is not JSON) is not cached. Once a call cannot connect, the rest are not made; a read timeout (`TwilioAccount.slow_answer?`: twilio-ruby raises it with Faraday's `TimeoutError` as its cause) fails only its own answer. Tests run on `null_store`: they swap `TwilioAccount.build_client` for `FakeTwilioClient` (`test/support/fake_twilio_client.rb`, `FakeTwilioTestHelper`) and reach the cache through `CacheTestHelper#with_cache_store`. Two cold reads at once ask Twilio once (issue 14, reworked after the review the same day): the first takes the lock `[*key, "reading"]`, an add-only write of a token only it knows, read back from the store, since Solid Cache's add-only write can answer true to two requests at once (it swallows the deadlock between them). A request that loses waits as long as the lock lasts (`LOCK_FOR`, 30 s: a read is several calls, one after another), looking at the lock and then the answer every `WAIT_STEP` (0.2 s); the holder caches its answer before letting go, so once the lock is gone the answer is there, if it ever will be, and with none the waiter reads Twilio itself. Every read of the lock or the answer goes past the request's local cache (`TwilioStatus.shared_read`, `Rails.cache.with_local_cache`): Solid Cache keeps what a request first read for the rest of it, a miss included, so a waiter reading its own copy never saw the answer. A request that takes the lock looks for the answer once more, and the holder lets go only while the lock still holds its token. Refresh skips the lock and the wait. The test environment's null store keeps no lock, so only a test with `with_cache_store` sees the wait; `test/lib/twilio_status_test.rb` runs production's local cache on a Solid Cache store kept in a Hash.
Trap: every Twilio call the page makes rescues `TwilioAccount::ERRORS`: a `TwilioError`, but also the `JSON::ParserError` an answer that is not JSON raises and the `URI::InvalidURIError` a spaced id raises before anything is sent. TwilioServiceId is split on commas and nothing more (`TwilioAccount.settings`, which `SmsService.broadcast` reads too), and an id that is empty or holds a space or punctuation (`TwilioAccount::TWILIO_ID`) is reported (`UNUSABLE_ID`) without asking Twilio, since broadcasts through it fail too.
Trap: Update Incoming Address moves where production's incoming texts go, live, starting with the next text, from whichever server it is used on: every copy of the database holds these credentials (dev's does), and every server but the training server may make the change. The owner ruled on 2026-10-26 against a per-server switch (`RANGER_CLUBHOUSE_TWILIO_INCOMING_LIVE`, removed that day): every server is assumed live. Its guards are the Tech Ninja gate, the confirm dialog, the action log, and the training-server check: `SmsManagement.incoming_changes_allowed?`, checked inside `point_incoming_texts` so a console call there is held back too, and `prevent_if_ghd_server` on the action. The training server's panel says it cannot make the change.
Trap: `SmsManagement.incoming_url_problem` refuses what Twilio cannot post to: not https, a user name or password, a query or fragment (the action log keeps the address as typed), a bare IP address in any spelling (`127.1`, `2130706433`, `0x7f000001`, `010.0.0.1`, IPv6), a name with no dot, or a local suffix (`.localhost`, `.test`, `.local`, `.internal`), case and a trailing dot ignored; so in development the address filled in is refused. That address, and the one the panel calls "This server", is `sms_incoming_address`: `TwilioSignatureConcern.address`, the one the inbound webhook checks signatures against (https on the mail host), never the address the page was reached at, so the settings card, the badge and the form agree with the check.
Trap: the Messaging Service is a setting of its own, `TwilioMessagingServiceId` (an `MG…` id, added 2026-10-26), a credential like the other Twilio settings, shown masked or Missing on the settings card. It used to be read off each Notify service, which stops working when Notify ends on 2027-01-31. The panel's Incoming Texts row reads that one service and the update changes it alone; neither asks a Notify service, so a Notify service Twilio cannot read no longer holds the change back. With the setting empty, or holding a space or punctuation (`TwilioAccount.messaging_service_problem`), the row says so without asking Twilio and the update is refused naming the setting; the form is offered only once Twilio read the service (`twilio_incoming_lock`). No server has the setting until an Admin with Tech Ninja enters it (the `MG…` id of the service the Notify service sends through, in Twilio's Console under Messaging › Services), so after a deploy the panel says it is not set and the update waits for it. The update keeps how the service handled incoming texts (`SmsManagement.incoming_setup`: address, method, fallback address, number deferral), then sets `inbound_request_url`, method POST, `fallback_url` empty (so a text the new address fails on goes nowhere else) and `use_inbound_webhook_on_number` false, so the address applies to every number in it. A number's own `sms_url` is left alone; on the live account it is Twilio's demo reply, unused while the service does not defer to it. On 2026-10-25 the live account sent incoming texts to Clubhouse 2 (`https://ranger-clubhouse.burningman.org/api/sms/inbound`), so `/infrastructure/sms/inbound` gets none until someone updates it.
Trap: the action log row (`twilio-incoming-update`) holds the new address and, per service, the old setup, ids masked and addresses as the page shows them (an old address's query is left off). An update that went out with no answer back (a timeout, a dropped connection) may have been made: it is logged with `unanswered: true`, and the message says so. One Twilio refused is neither made nor logged. Its outcome is a callout inside the panel's frame (the frame draws no toasts), and the panel reloads past its cache. A Tech Ninja without Admin cannot open Action Logs, so the message after the change names the old address.
Trap: Twilio's error text names resources by full id; `sms_mask_sids` masks every id in it, as the settings card masks the stored ones. A subaccount's balance is never asked for (`owner_account_sid` differs from its `sid`): Twilio keeps it on the main account, and `Balance.json` answers 20404 for a subaccount. The dev credentials are a subaccount's (checked 2026-10-25).
Trap: Look Up a Number (added 2026-10-26, SMS Management issue 13, reworked after the review the same day) asks Lookup v2 for one number. A callsign comes first, as on Clubhouse 1 Log, since some are only digits ("4748"): its number on file (`Person.resolve_callsign`; a loose spelling two people share is refused, as is a callsign with no number, and one with nothing left once written loosely is no one's). Anything else with digits and no letters is a number, a paste's odd spaces, dashes and invisible marks included (`PhoneFormatter.digits_typed`, made public for this); input with no letter or digit asks for a number or a callsign, and Twilio is not asked. twilio-ruby puts the number in the address unescaped, so `TwilioLookup.request_form` sends E.164, or only its digits and plus. The basic lookup is free; the line type and carrier (`fields: "line_type_intelligence"`) are billed per lookup, so they are asked for only with their box ticked, and the box comes back unticked after every lookup (the owner's ruling: opt in per lookup). The answer is a 200 into its frame, never the house 422: RequestLogger keeps a 422's parameters and page, and Request Logs shows them to Admins without Tech Ninja. After a lookup the field has autofocus, and what was found goes to the layout's `#live-region` through a `turbo-stream` inside the frame, which Turbo runs as it lands (callsign first and the live-region stream chosen by Claude, reversible). A landline explains Twilio error 30006; a Canadian number's line type needs NPAC approval (60601). Never on the training server. `SmsService.sms_capable?` (Lookup v1, in maintenance mode, uncalled) is gone.

## Background jobs & mail

Jobs inherit `ApplicationJob`, whose `retry_on`/`discard_on` are commented out, so a raise lands in failed executions. Schedules live in `config/recurring.yml` (America/Phoenix); the Groundhog Day (GHD) training server runs only the finished-job cleanup and training reload. Mail is Liquid in `mail_template` tagged `<mailer_name>/<action>` (seeded from `db/mail_templates/`), fed only `liquid_assigns`, and held on GHD (`ApplicationMailer#hold_mail_on_training_server`).

### Daily Report (DailyReportJob)
Runs: `daily_report` 3am daily — production only, not GHD; sends nothing when setting `DAILY_REPORT_EMAIL` is blank
Job: `app/jobs/daily_report_job.rb`
Owner: `DailyReportJob` (`app/jobs/daily_report_job.rb`), `DailyReportMailer` (`app/mailers/daily_report_mailer.rb`), `ActionLog.find_for_query` (`app/models/action_log.rb`)
Touches: `setting`, `error_logs`, `action_logs`, `role`, `person_status`, `person`, `broadcast`, `alert`, `broadcast_message`, `solid_queue_failed_executions`, `solid_queue_jobs`, `mail_template`
Verify: `test/jobs/daily_report_job_test.rb`, `test/mailers/daily_report_mailer_test.rb`
Trap: `ActionLog.find_for_query` takes `lastday:`, `ErrorLog.find_for_query` takes `last_day:`, and an unknown key is silently ignored — a swap drops the 24-hour filter and lists rows from all time.
Trap: a setting added to `DailyReportJob::REPORTED_SETTINGS` never appears unless also mapped in `DailyReportMailer::WATCHED_SETTINGS` and read as `settings.<key>` (not the stored name) in `db/mail_templates/daily_report_mailer/notify.yml`.

### Failed background task cleanup (ClearFailedTasksJob)
Runs: `clear_failed_tasks` 4am daily — production only, not GHD
Job: `app/jobs/clear_failed_tasks_job.rb`
Owner: `ClearFailedTasksJob` (`app/jobs/clear_failed_tasks_job.rb`), `SolidQueue::FailedExecution.discard_all_in_batches` (solid_queue gem)
Touches: `solid_queue_failed_executions` (w), `solid_queue_jobs` (w)
Verify: `test/jobs/clear_failed_tasks_job_test.rb`

### Finished background task cleanup (clear_solid_queue_finished_jobs)
Runs: `clear_solid_queue_finished_jobs` hourly at minute 12 — development and production, GHD included (the only recurring task in development)
Job: none — `command:` in `config/recurring.yml` calling `SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)`
Owner: `SolidQueue::Job.clear_finished_in_batches` (solid_queue gem; `config` leaves `clear_finished_jobs_after` at one day)
Touches: `solid_queue_jobs` (w)
Verify: none — no test exercises this feature
Trap: `config/puma.rb` loads `plugin :solid_queue` unconditionally (`SOLID_QUEUE_IN_PUMA` guard commented out), so every `bin/rails server` starts a worker plus this scheduler on the dev queue in `rangers-ch3` and can run jobs another server enqueued.

### Training database reload (reload_training_database)
Runs: `reload_training_database` 4am daily — GHD server only (production with `RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME` set), where it replaces every production task but `clear_solid_queue_finished_jobs`; by hand `bin/rails clubhouse:reload_training_db CONFIRM=<database>` (`lib/tasks/clubhouse.rake`)
Job: none — `command:` in `config/recurring.yml` calling `GroundHogDay.reload_training_database!`
Owner: `GroundHogDay.reload_training_database!` (`app/lib/ground_hog_day.rb`), `DatabaseDump.load_gzip` (`app/lib/database_dump.rb`)
Touches: every table not named `solid_*` (w) (dropped, then reloaded from `training-<YYYY-MM-DD>.sql.gz` in the app root), `solid_cache_entries` (w)
Verify: `test/lib/ground_hog_day_test.rb`
Trap: the scheduled reload skips the `CONFIRM=<database>` check (`DatabaseDump.confirm_overwrite!`), so the env var plus a `training-<YYYY-MM-DD>.sql.gz` drops every non-`solid_` table — never set `RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME` over a real database.

### Log and sign-in code expiry (CleanupMailLogJob, ExpireRequestLogsJob, ExpireOauthCodesJob)
Runs: `cleanup_mail_log` 3:30am daily (older than `MailLog::RETENTION`, 6 months); `expire_request_logs` 5am daily (`RequestLog::EXPIRE_DAYS_DEFAULT`, 7 days); `expire_oauth_codes` every 5 minutes (`OauthCode::EXPIRE_IN_SECONDS`, 120s) — all production only, not GHD
Job: `app/jobs/cleanup_mail_log_job.rb`, `app/jobs/expire_request_logs_job.rb`, `app/jobs/expire_oauth_codes_job.rb`
Owner: `MailLog.purge_old` (`app/models/mail_log.rb`), `RequestLog.expire` (`app/models/request_log.rb`), `OauthCode.delete_expired` (`app/models/oauth_code.rb`)
Touches: `mail_log` (w), `request_log` (w), `oauth_code` (w)
Verify: `test/jobs/cleanup_mail_log_job_test.rb`, `test/jobs/expire_oauth_codes_job_test.rb`, `test/models/request_log_test.rb`, `test/models/mail_log_test.rb`, `test/models/oauth_code_test.rb`
Trap: `ExpireOauthCodesJob` only keeps `oauth_code` small — the 120s limit is enforced at redeem (`OauthCode.redeem` returns nil for `created_at <= EXPIRE_IN_SECONDS.seconds.ago`), so never drop that check.

### Announcement expiry (ExpireAnnouncementsJob)
Runs: `expire_announcements` 5am daily — production only, not GHD
Job: `app/jobs/expire_announcements_job.rb`
Owner: `Motd.expire!` (`app/models/motd.rb`)
Touches: `motd` (w), `person_motd` (w)
Verify: `test/jobs/expire_announcements_job_test.rb`, `test/models/motd_test.rb`
Trap: `Motd.retrieve_announcements_for_person` ignores `expires_at`, so an expired announcement stays on /me until this job deletes it, which never happens in development or on GHD.

### Expired Handle Reservations (ExpireHandleReservationsJob)
Runs: `expire_handle_reservations` 5am daily — production only, not GHD; mails the Volunteer Coordinators (`EmailAddresses::VOLUNTEER_COORDINATORS_TEAM`) only when something expired
Job: `app/jobs/expire_handle_reservations_job.rb`
Owner: `HandleReservation.expire_handles!` (`app/models/handle_reservation.rb`), `ExpiredHandleReservationsMailer` (`app/mailers/expired_handle_reservations_mailer.rb`)
Touches: `handle_reservation` (w), `action_logs` (w), `mail_template`
Verify: `test/jobs/expire_handle_reservations_job_test.rb`, `test/models/handle_reservation_test.rb`, `test/mailers/expired_handle_reservations_mailer_test.rb`

### Photos queued for review (PhotoPendingJob)
Runs: `photo_pending` 9am and 9pm (`0 9,21 * * *`) — production only, not GHD; sends nothing when no photo is submitted
Job: `app/jobs/photo_pending_job.rb`
Owner: `PersonPhoto.find_all_submitted` (`app/models/person_photo.rb`), `PhotoPendingMailer` (`app/mailers/photo_pending_mailer.rb`)
Touches: `setting`, `person_photo`, `person`, `mail_template`
Verify: `test/jobs/photo_pending_job_test.rb`

### Vehicles pending review (VehiclePendingJob)
Runs: `vehicle_pending` 7pm daily — production only, not GHD; sends nothing when setting `VEHICLE_PENDING_EMAIL` is blank or nothing is pending
Job: `app/jobs/vehicle_pending_job.rb`
Owner: `Vehicle.find_all_pending` (`app/models/vehicle.rb`), `VehiclePendingMailer` (`app/mailers/vehicle_pending_mailer.rb`)
Touches: `setting`, `vehicle`, `person`, `mail_template`
Verify: `test/jobs/vehicle_pending_job_test.rb`, `test/models/vehicle_test.rb`
Trap: `Vehicle.find_all_pending` counts only present-year (`event_year: Current.year`) personal requests and drops any whose owner account is gone (log warning only), so the mailed count can be lower than the pending rows in `vehicle`.
Trap: the email's link opens the Vehicle Registry (`registry_url`), whose `:view_registry` gate is Admin or Event Management, so a reader on `VEHICLE_PENDING_EMAIL` holding only `VEHICLE_INFO_UPDATE` lands on `/me` (the Vehicle Registry's own trap).

### Approved applications reminder (PendingApplicationsJob)
Runs: `pending_applications` 5pm daily — production only, not GHD; mails the Volunteer Coordinators only when present-year approved applications are waiting
Job: `app/jobs/pending_applications_job.rb`
Owner: `ProspectiveApplication.retrieve_approved` (`app/models/prospective_application.rb`), `ProspectiveApplication::ApprovedReminderMailer` (`app/mailers/prospective_application/approved_reminder_mailer.rb`)
Touches: `prospective_application`, `mail_template`
Verify: `test/jobs/pending_applications_job_test.rb`, `test/mailers/prospective_application_mailer_test.rb`

### Recheck unfinished texts (RecheckUnfinishedTextsJob)
Runs: `recheck_unfinished_texts` 6am daily — production only, not GHD (and `SmsService.recheck_unfinished_texts` returns at once on the training server too); asks Twilio nothing while the Account SID or token is unset
Job: `app/jobs/recheck_unfinished_texts_job.rb`
Owner: `SmsService.recheck_unfinished_texts` and `receipt_status` (`app/lib/sms_service.rb`), `BroadcastMessage.awaiting_receipt` and `record_receipt` (`app/models/broadcast_message.rb`)
Touches: `broadcast_message` (w), `broadcast` (w, after a failed text), `setting`, `error_logs` (w); Twilio's Messages API (one fetch a text)
Verify: `test/jobs/recheck_unfinished_texts_job_test.rb`, `test/lib/sms_service_test.rb`
Trap: added 2026-10-26 (SMS Management issue 11), as Twilio advises: a text still `sent` (or a code still `verify`) with a SID, between `SmsService::RECHECK_AFTER` (12 hours) and `RECHECK_WITHIN` (3 days) after its row was written, is fetched by SID, `RECHECK_BATCH` (100) rows' ids at a time, and what Twilio says goes through `record_receipt`, the receipt endpoint's own rule, so a late receipt and the recheck never disagree. A text Twilio no longer has (404) is skipped; any other refusal, or no answer, stops the run with one `sms-recheck-exception` log, and the next day's run asks again. `created_at` has no index, so the window is one pass over `broadcast_message` a day.

### Online course completion scan (MoodleCompletionJob)
Runs: `moodle_completion_season` every ten minutes April–August (`0,10,20,30,40,50 * * 4-8 *`) and `moodle_completion_september` every ten minutes September 1–10 — production only, not GHD; skipped while setting `ONLINE_COURSE_ENABLED` is off
Job: `app/jobs/moodle_completion_job.rb`
Owner: `Moodle#process_course_completion` (`app/lib/moodle.rb`), `OnlineCourse` (`app/models/online_course.rb`), `PersonOnlineCourse` (`app/models/person_online_course.rb`)
Touches: `setting`, `online_course`, `person_online_course` (w), `person`, `error_logs` (w)
Verify: `test/jobs/moodle_completion_job_test.rb`, `test/lib/moodle_test.rb`
Trap: the scan only writes `person_online_course.completed_at` — `OnlineCourseCompletedMailer` has a template but no caller, so no completion email goes out.
Trap: `Moodle#process_course_completion` skips a completion whose America/Phoenix year differs from `course.year`, and the job scans only present-year active courses, so the schedule never records a course finished after September 10.

### Ranger SAP Candidates email (RangersWhoNeedSapsJob)
Runs: `rangers_who_need_saps` Mondays 2:30am in July and August (`30 2 * 7-8 1`) — production only, not GHD; sends nothing when setting `TAS_SAP_REPORT_EMAIL` is blank
Job: `app/jobs/rangers_who_need_saps_job.rb`
Owner: `SapCandidatesReport` (`app/lib/reports/sap_candidates_report.rb`), `RangersWhoNeedSapsMailer` (`app/mailers/rangers_who_need_saps_mailer.rb`)
Touches: `setting`, `person`, `timesheet`, `person_slot`, `slot`, `position`, `access_document`, `mail_template`
Verify: `test/jobs/rangers_who_need_saps_job_test.rb`, `test/mailers/rangers_who_need_saps_mailer_test.rb`, `test/controllers/ticketing/sap_candidates_controller_test.rb`
Trap: the header comment in `app/mailers/rangers_who_need_saps_mailer.rb` ("Nothing schedules this yet", nightly) is stale — `config/recurring.yml` runs it weekly through July and August.

### Badge export archive cleanup (DeleteBmidExportsJob)
Runs: `delete_bmid_exports` yearly, September 15 at 5:30am (`30 5 15 9 *`) — production only, not GHD; by hand `bin/rails clubhouse:delete_bmid_exports_post_event`, or `clubhouse:delete_bmid_exports[year]` for one year (`lib/tasks/clubhouse.rake`)
Job: `app/jobs/delete_bmid_exports_job.rb`
Owner: `BmidExport.delete_all_for_post_event` (`app/models/bmid_export.rb`)
Touches: `bmid_export` (w), `active_storage_attachments` (w), `active_storage_blobs` (w)
Verify: `test/jobs/delete_bmid_exports_job_test.rb`
Trap: `BmidExport.delete_all_for_post_event` destroys every year's archives (`destroy_each(all)`), not just the present year's — use `delete_all_for_year` for one year.

### Empty shift alert (AlertWhenSignUpsEmptyJob)
Runs: enqueued with `set(wait: 5.minutes)` by `Scheduling::EmailNotification.handle_empty_signups_alerts` (`app/lib/scheduling/email_notification.rb`) when signup intake removes a slot's last person (private `Scheduling::Signup.delete_signup`, also reached by `Scheduling::Signup::Bulk` removals from a status change in `PersonStatusManagement` or a revoked position in `PersonPosition`) — if the position has `alert_when_no_trainers` and trainees remain on the linked trainee slot, or `alert_when_becomes_empty` with setting `EVENT_MANAGEMENT_ON_PLAYA_ENABLED` on; re-reads the counts and sends nothing if someone signed back up
Job: `app/jobs/alert_when_sign_ups_empty_job.rb`
Owner: `Scheduling::EmailNotification` (`app/lib/scheduling/email_notification.rb`), `AlertWhenSignUpsEmptyMailer` (`app/mailers/alert_when_sign_ups_empty_mailer.rb`)
Touches: `slot`, `position`, `person`, `setting`, `mail_template`
Verify: `test/jobs/alert_when_sign_ups_empty_job_test.rb`
Trap: the job takes the `Position` and `Slot` records (GlobalID) and `ApplicationJob`'s `discard_on ActiveJob::DeserializationError` is commented out, so a slot deleted during the five-minute wait fails the job instead of skipping it.

### RBS › Broadcast emails (RbsTransmitEmailJob)
Runs: enqueued by `Rbs.transmit` (`app/lib/rbs.rb`) for a broadcast sent with email — `POST /communication/rbs/broadcasts/:type` (`Communication::RbsBroadcastsController#create`, Communication Management › Ranger Broadcast)
Job: `app/jobs/rbs_transmit_email_job.rb` (`< RbsEmailJob`, `app/jobs/rbs_email_job.rb`: the shared lock and continuation settings)
Owner: `Rbs.broadcast_email` (`app/lib/rbs.rb`: Amazon SES `SendBulkEmail`, `min(SES_MAX_SEND_RATE, 50)` people a call, a call a second), `RbsMailer` (`app/mailers/rbs_mailer.rb`, rendered once per broadcast)
Touches: `alert`, `person`, `broadcast` (w), `broadcast_message` (w), `mail_log` (w), `error_logs` (w), `email_suppression`, `setting`, `mail_template`
Verify: `test/lib/rbs_test.rb`, `test/controllers/communication/rbs_broadcasts_controller_test.rb`
Trap: `Rbs.broadcast_email` deliberately does not re-check alert preferences — the job's `targets` (`[person_id, use_email]`) carry send-time decisions incl. emergency overrides, and a re-check would drop emergency broadcasts to opted-out people. It reads only the recorded reason, from the `Person` it loads (`people_by_id`): one `EmailSuppression.suppressed` call per run, for the people it won't email, records `suppressed` where the record holds their address and `no-contact` otherwise. It never asks about the people it will email, so an address suppressed after Send still gets that one email. Keep the pairs: `targets.to_h` raises on a three-element tuple, and jobs queued before a deploy still carry pairs.
Trap: with `BROADCAST_MAIL_TEST_ADDRESS` set, `Rbs.email_mode` is `:test` and `Rbs.broadcast_email` sends through SES in any environment, to the pattern with each person's id in place of the `?` (see the Rbs entry).
Trap: while `Rbs.email_mode` is `:held` (setting `BROADCAST_MAIL_SANDBOX`, the training server, or `config.x.rbs_email_rangers` not true with no test address set), `broadcast_message` rows read as sent with no SES call and no `mail_log` row — check `mail_log` or `broadcast_message.message_id` to know an email really left. An email with no address at all is recorded `invalid-parameter` instead (`Rbs.deliver_email_batch`), which the sandbox never did, and is not retryable.
Trap: the SES template holds only placeholders, one per part of the rendered message, and the parts travel as `template_data` — `Rbs.ses_content` builds both from the same parts, because a placeholder with no data makes SES take the email and drop it. Put no literal text in the template, or a `{{` someone typed becomes Handlebars. The SES client is built without SDK retries (`retry_limit: 0`) — a retried call has no idempotency token and would send a whole batch twice.
Trap: an address SES could not take (`Rbs.sendable_address?`, which calls the rule in `EmailAddresses.sendable?`, to AWS's documented form `UserName@[SubDomain.]Domain.TopLevelDomain`: fails `URI::MailTo::EMAIL_REGEXP`, has a leading, trailing or doubled dot before the @, has no dot in the domain, or a last label that is not 2+ letters or `xn--` punycode, such as `a@b`, `a@1.2.3.4`, `a@b.123` or `a@b.c`; or the mail library cannot read it; in test mode the Ranger's own address is what is checked) is recorded `invalid-parameter` ("Invalid address on file") and never put in a call, and control characters are stripped from the To name (`Rbs.to_line`). Entries SES refuses go to `error_logs` as `rbs-email-not-accepted` with SES's reason, and each row records that reason as its status (`Rbs.ses_refusal_status`); a call that raised gives everyone in it `Rbs.call_failure_status`. An email that will not draw (an admin-edited template can parse and still raise) or no SES client (`MissingRegionError` comes from `Client.new`) stops the run at once (`EmailRun#broken`): one `rbs-email-exception` log, and everyone left is recorded `service-fail` at the address the mode would have used, so a test broadcast keeps its plus addresses for any later Retry. After `Rbs::SES_FAILURES_BEFORE_GIVING_UP` (3) call failures in a row that every later call would meet too (missing keys, a paused or suspended account, or answers all in `Rbs::SES_ACCOUNT_REFUSALS`), the rest of the broadcast is recorded `service-fail` without calling SES again, with one `rbs-email-given-up` log naming how many were not sent. A dropped connection, throttling or an SES 5xx never counts (`Rbs.passing_failure?`), and a call that sends anyone resets the count. Once SES has answered, its answer is never turned into a failure: a log write that fails after the call is skipped (`Rbs.note`).
Trap: one broadcast email job runs at a time, a send or a retry: both jobs share the `rbs-email` Solid Queue lock (see the RbsRetryEmailJob entry).
Trap: the job is continuable (`ActiveJob::Continuable`, one `:deliver` step): `Rbs.broadcast_email` yields after each recorded batch and the job checkpoints there, so a deploy (Solid Queue's worker stop answers `stopping?`) stops it at the checkpoint after the call in flight, and it resumes 5 s later. That holds because a call is bounded inside the shutdown window: `Rbs.ses_client` gives up after 5 s to connect and 20 s to answer, production's `config.solid_queue.shutdown_timeout` is 30 s, and `web`'s `stop_grace_period` in docker-compose.yml is 45 s, longer than both. Shorten any of those and a call can be cut off, the job released to start over, and the batch in flight sent twice. A job whose worker was killed is marked failed, not run again, and `Rbs.record_stopped` never ran, so the people it had not reached have no row and the broadcast can read "Delivered"; a failed job can be retried from a console with `SolidQueue::FailedExecution#retry` (Mission Control is not installed). Any run started again -- resumed, released, or retried -- skips everyone who already has an email row for the broadcast. `resume_errors_after_advancing` is off, so an error never resumes it.
Trap: the last argument is the email mode when Send was pressed; each batch sends by `Rbs.effective_email_mode`, never less safely (see the Rbs entry). Keep the argument order: queued jobs survive a deploy.
Trap: tests never reach AWS: `config/environments/test.rb` stubs every `Aws::SESV2::Client`, and `SesTestHelper#with_ses` records the calls, answering each entry `ses-<its address>`.

### RBS › Broadcast texts (RbsTransmitSmsJob)
Runs: enqueued by `Rbs.queue_sms` (from `Rbs.transmit`) for a broadcast sent with texts — `POST /communication/rbs/broadcasts/:type` — and by `Rbs.queue_retried_sms` (from `Rbs.retry_broadcast`) for its failed texts — `POST /communication/rbs/history/:id/retry`
Job: `app/jobs/rbs_transmit_sms_job.rb`
Owner: `Rbs.deliver_queued_sms` (`app/lib/rbs.rb`), `SmsService.text_settings`/`text_through` (`app/lib/sms_service.rb`: the Messages API through `TwilioMessagingServiceId`, `validity_period` 2 hours)
Touches: `broadcast` (w), `broadcast_message` (w), `error_logs` (w), `setting`; Twilio's Messages API
Verify: `test/lib/rbs_test.rb`, `test/lib/sms_service_test.rb`
Trap: the rows come first. Send writes a `queued` row (`Broadcast::STATUS_QUEUED`, "Queued", not a failure) for each person it may text, and Retry turns the failed text rows back to `queued`; the job sends whatever of the broadcast is queued, so a send and a retry are one job. Each round of `Rbs::SMS_THREADS` (4) rows is marked `send-unconfirmed` before its texts go, then settled: `sent` with Twilio's SID in `message_id`, `service-fail` for a refusal (one `sms-exception` log each), `send-unconfirmed` when Twilio may have taken it without answering. While texts are queued they count in neither `sms_failed` nor the Retry button; a job that never runs leaves them `queued`, which RBS › Message log shows.
Trap: continuable, one `:deliver` step checkpointed after each round. A deploy's stop (`ActiveJob::Continuation::Interrupt`, an `Exception`, which `rescue StandardError` lets through) leaves the rest `queued` for the resumed run; an error turns them `service-fail`, for a Retry (`Rbs.fail_queued_sms`); a killed worker leaves only its round in flight, `send-unconfirmed`, so no text goes twice. A round is one text a thread, inside the 30 s shutdown window even at the 5 s timeouts (a 429 pause stretches it).
Trap: each text of a round goes on its own thread with its own client, built once a run (`Rbs.sms_senders`): a `Twilio::HTTP::Client` keeps its connection and last response on itself. The threads only call Twilio; the rows and logs are written on the job's thread. A 429 is asked again up to `SmsService::RATE_LIMIT_RETRIES` (5) times, the pause doubling from 0.1 s with ±10% jitter; any other refusal is not.
Trap: the last argument is whether the text sandbox was on at the click (`Rbs.sms_held?`, read past the cache), and every round asks again, so turning it on holds the rest: held texts are recorded `sent` with no SID and no Twilio call. Keep the argument order: queued jobs survive a deploy.
Trap: a missing Account SID or token, or an unusable `TwilioMessagingServiceId`, fails every queued text at once with one `sms-exception` log, before Twilio is asked (`Rbs.sms_senders`).
Trap: `limits_concurrency to: 1` keyed by the broadcast id: one run per broadcast, so a Retry clicked twice waits on the first, while another broadcast's texts (an emergency's) never wait behind it. The `:test` adapter ignores the lock.

### RBS › Broadcast Clubhouse messages (RbsTransmitClubhouseMessageJob)
Runs: enqueued by `Rbs.transmit` (`app/lib/rbs.rb`) for a broadcast sent to Clubhouse inboxes — `POST /communication/rbs/broadcasts/:type` (`Communication::RbsBroadcastsController#create`)
Job: `app/jobs/rbs_transmit_clubhouse_message_job.rb`
Owner: `Rbs.broadcast_message` (`app/lib/rbs.rb`), `PersonMessage` (`app/models/person_message.rb`)
Touches: `setting`, `person`, `person_message` (w), `broadcast_message` (w)
Verify: `test/lib/rbs_test.rb`
Trap: setting `BROADCAST_CLUBHOUSE_SANDBOX` is read when the job runs, not at send, and a sandboxed run records a sent `broadcast_message` per person but no `person_message` — check `person_message.broadcast_id`.

### RBS › Retry failed broadcast emails (RbsRetryEmailJob)
Runs: enqueued by `Rbs.retry_broadcast` (`app/lib/rbs.rb`) when retryable failed emails remain — `POST /communication/rbs/history/:id/retry` (`Communication::RbsHistoryController#retry`)
Job: `app/jobs/rbs_retry_email_job.rb` (`< RbsEmailJob`, as the send job)
Owner: `Rbs.deliver_retried_emails` (`app/lib/rbs.rb`: the same `deliver_email_batch` SES batches a send uses, recorded in place by `Rbs.record_retried_batch`), `RbsMailer` (`app/mailers/rbs_mailer.rb`, rendered once per run)
Touches: `broadcast` (w), `broadcast_message` (w), `alert`, `person`, `mail_log` (w), `error_logs` (w), `setting`, `mail_template`
Verify: `test/lib/rbs_test.rb`, `test/controllers/communication/rbs_history_controller_test.rb`
Trap: `Rbs.retry_broadcast` sets `broadcast.email_failed` to the recount, not 0, so the Retry button stays until the job runs. A second click queues a second job; it waits on the shared lock and its per-batch reload finds the rows already sent.
Trap: this job and `RbsTransmitEmailJob` share one Solid Queue lock, declared once in their parent `RbsEmailJob` (`limits_concurrency to: 1, group: "rbs-email", key: "rbs-email", duration: 3.hours`), so only one broadcast email job runs at a time. Without `group:` each class gets its own semaphore, and a send and a retry run side by side at twice the account rate. The `:test` adapter ignores the lock; `rbs_test.rb` checks its settings.
Trap: a live retry goes to the address on the failed `broadcast_message` row, not the person's current `person.email` — so a row sent to the test address goes there again. While a test address is set, every retry goes to it (`Rbs.test_address` from the person's id), whatever the row says.
Trap: each batch's rows are read again through `broadcast.failed_messages.where(id:)` just before its SES call, so a row sent since the Retry click is skipped, and so is the row of anyone who can no longer be messaged since (dismissed, deleted: `BroadcastMessage.sendable`), which keeps its failure status. Only an email SES took moves its row to the address it went to: a retry that fails again, or one held back by a test address that can't be used (`rbs-email-not-sent`), keeps the row's address.
Trap: continuable like the send job: it checkpoints after each recorded batch, and a resumed run's per-batch reload through `failed_messages` skips every row sent before it stopped.
Trap: the last argument is the email mode when Retry was pressed; each batch sends by `Rbs.effective_email_mode`, never less safely (see the Rbs entry).
Trap: nothing in RBS sends broadcast email over SMTP any more — a held retry (`Rbs.email_mode` `:held`) marks rows `sent` with no SES call and no `mail_log` row, as the sandbox always did, except that a row with no address becomes `invalid-parameter`.

### Mail template loading (mail_templates:load)
Runs: by hand, `bin/rails mail_templates:load`, and at every test boot (`test/test_helper.rb` calls `MailTemplateSeeds.load!`) — no deploy step (`bin/docker-entrypoint`, `Dockerfile`, `docker-compose.yml`) runs it
Job: none — rake task `lib/tasks/mail_templates.rake` reading `db/mail_templates/**/*.yml`
Owner: `MailTemplateSeeds` (`app/lib/mail_template_seeds.rb`), `MailTemplate` (`app/models/mail_template.rb`)
Touches: `mail_template` (w)
Verify: `test/lib/mail_template_seeds_test.rb`, `test/mailers/mail_template_coverage_test.rb`, `test/models/mail_template_test.rb`
Trap: a `db/mail_templates` yml edit changes no email until the loader runs, which leaves alone ("Left alone, edited in the Clubhouse") any row not matching its `seeded_digest` — change those at Communication Management › Email Templates.
Trap: every public mailer method is a sendable action, and `MailTemplateCoverageTest` demands a `db/mail_templates/<mailer_name>/<action>.yml` with a subject for each — keep helpers private, add the yml with any new action.

### Transactional mail
Mail: `AccountCreationMailer` ← `/register` (`RegisterForm#announce_new_account`, deliver_later, to setting `ACCOUNT_CREATION_EMAIL`) — `db/mail_templates/account_creation_mailer/notify.yml`
Mail: `AlertWhenSignUpsEmptyMailer` ← `AlertWhenSignUpsEmptyJob` (to `position.contact_email`) — `db/mail_templates/alert_when_sign_ups_empty_mailer/notify.yml`
Mail: `AutomaticActiveConversionMailer` ← `ShiftManage.convert_inactive_to_active` (Inactive person off duty on a non-training, non-Cheetah Cub shift) via `ShiftManage.sign_off` (HQ and Me shift manage end shift, Person › Timesheets sign-off, Mass Sign-Out, Roll Call check-out, Alpha Sign-Out) and `BulkSignInOut` (Bulk Sign In/Out), deliver_later, to the Volunteer Coordinators — `db/mail_templates/automatic_active_conversion_mailer/notify.yml`
Mail: `AutomaticSignOutMailer` ← no caller (ported, not wired up) — `db/mail_templates/automatic_sign_out_mailer/notify.yml`
Mail: `ClubhouseNewMessageMailer` ← `Rbs.message_notify` from `MessagesConcern#create`/`#create_reply` (Me › Messages, Person › Messages, HQ › Messages), deliver_later; only while setting `BROADCAST_CLUBHOUSE_NOTIFY` is on and the recipient's Clubhouse-message alert allows email; skipped under setting `BROADCAST_MAIL_SANDBOX`, which still records `broadcast` and `broadcast_message` rows; `message_notify` asks `email_suppression` first, queues nothing for a suppressed address and records its row `suppressed`; while setting `BROADCAST_MAIL_TEST_ADDRESS` is set it goes to that pattern with the person's id in place of the `?` (see Ranger Broadcast System (Rbs)); `SuppressedRecipientsInterceptor` still drops one suppressed after the alert was queued, under a `sent` row — `db/mail_templates/clubhouse_new_message_mailer/notify.yml`
Mail: `ContactMailer` ← no caller (only `test/mailers/contact_mailer_test.rb`) — `db/mail_templates/contact_mailer/send_message.yml`
Mail: `DailyReportMailer` ← `DailyReportJob` — `db/mail_templates/daily_report_mailer/notify.yml`
Mail: `ExpiredHandleReservationsMailer` ← `ExpireHandleReservationsJob` — `db/mail_templates/expired_handle_reservations_mailer/notify.yml`
Mail: `NotifyVcEmailChangeMailer` ← no caller (ported, not wired up) — `db/mail_templates/notify_vc_email_change_mailer/notify.yml`
Mail: `OnlineCourseCompletedMailer` ← no caller (`MoodleCompletionJob` does not send it) — `db/mail_templates/online_course_completed_mailer/notify.yml`
Mail: `OnlineCourseEnrollmentMailer` ← no caller (ported, not wired up) — `db/mail_templates/online_course_enrollment_mailer/notify.yml`
Mail: `OnlineCourseResetPasswordMailer` ← no caller (ported, not wired up) — `db/mail_templates/online_course_reset_password_mailer/notify.yml`
Mail: `PasskeyMailer` (`added`, `removed`) ← `Me::PasskeysController` and `Person::PasskeysController` `create`/`destroy` (deliver_later) — `db/mail_templates/passkey_mailer/added.yml`, `removed.yml` (HTML and plain text parts)
Mail: `PasswordResetMailer` ← `SessionsController#reset_password` (`POST /reset-password`, deliver_now) — `db/mail_templates/password_reset_mailer/notify.yml` (HTML and plain text parts)
Mail: `PhotoApprovedMailer`, `PhotoRejectedMailer` ← `Vc::PhotosReviewController#review` on approve/reject (deliver_now; skipped for `Person::LOCKED_STATUSES`); rejection also rendered by `reject_preview` — `db/mail_templates/photo_approved_mailer/notify.yml`, `db/mail_templates/photo_rejected_mailer/notify.yml`
Mail: `PhotoPendingMailer` ← `PhotoPendingJob`; links to `GET /vc/photos-review` (`review_url`) — `db/mail_templates/photo_pending_mailer/notify.yml`
Mail: `PhotosExpiredMailer` ← no caller (ported, not wired up) — `db/mail_templates/photos_expired_mailer/notify.yml`
Mail: `RangersWhoNeedSapsMailer` ← `RangersWhoNeedSapsJob` — `db/mail_templates/rangers_who_need_saps_mailer/notify.yml`
Mail: `RbsMailer#broadcast` ← `Rbs.render_broadcast` in `RbsTransmitEmailJob` (drawn once per broadcast with no recipient, sent through SES `SendBulkEmail` by `Rbs.broadcast_email`, a `mail_log` row per email SES took; nothing while `Rbs.email_mode` is `:held`), and in `RbsRetryEmailJob` the same way through `Rbs.deliver_retried_emails` — `db/mail_templates/rbs_mailer/broadcast.yml`
Mail: `TrainerReminderMailer` ← no caller (ported, not wired up); to the position's contacts and the trainers, From `DoNotReplyEmail` as "Ranger Clubhouse", Reply-To the contacts — `db/mail_templates/trainer_reminder_mailer/notify.yml`
Mail: `TrainingSessionFullMailer` ← `Scheduling::Signup` when signup intake fills a training slot whose position has a contact email (deliver_later); to every contact address, From `DoNotReplyEmail` as "Ranger Clubhouse", Reply-To the contacts — `db/mail_templates/training_session_full_mailer/notify.yml`
Mail: `TrainingSignupMailer` ← no caller (the `TrainingSignupEmailJob` line in `Scheduling::Signup` is commented out) — `db/mail_templates/training_signup_mailer/notify.yml`
Mail: `UpdateMailingListSubscriptionsMailer` ← no caller (ported, not wired up) — `db/mail_templates/update_mailing_list_subscriptions_mailer/notify.yml`
Mail: `VehiclePendingMailer` ← `VehiclePendingJob`; links to `GET /vehicles/registry?status=pending&type=personal` (`registry_url`), the requests it lists — `db/mail_templates/vehicle_pending_mailer/notify.yml`
Mail: `WelcomeMailer` ← `PersonController#resend_welcome` (`POST /person/:person_id/resend_welcome`, Admin or VC) and `ProspectiveClubhouseAccountFromApplication#send_welcome_email` (Volunteer Coordinator › Applications › Create Prospectives, setting `SEND_WELCOME_EMAIL`), deliver_later; both give the token 14 days (`Person::PNV_INVITATION_EXPIRE`), and the link is `reset_token_url(token:, welcome: 1)`, Reset Your Password worded as a welcome — `db/mail_templates/welcome_mailer/notify.yml`
Mail: `ProspectiveApplication::AgeConfirmationMailer`, `ApprovedCallsignMailer`, `ExperienceConfirmationMailer`, `MoreHandlesMailer`, `PiiIssueMailer`, `RejectRegionalMailer`, `RejectTooYoungMailer`, `RejectUnqualifiedMailer`, `ReturningRangerMailer`, `WhyRangerQuestionMailer`, `RrnCheckMailer#check` ← `ProspectiveApplicationStatusMail.execute` (`app/lib/prospective_application_status_mail.rb`) from `Vc::ApplicationsController#status` (`POST /vc/applications/:id/status`), previewed by `#preview_email`; built by `ProspectiveApplicationMailer#build_mail`, to the applicant or setting `PROSPECTIVE_APPLICATION_MAIL_SANDBOX` (`RrnCheckMailer` to setting `RRN_EMAIL`), deliver_now plus a `prospective_application_log` row; its `mail_log` rows carry the application — `db/mail_templates/prospective_application/<mailer>/notify.yml` (`rrn_check_mailer/check.yml`)
Mail: `ProspectiveApplication::SendEmailMailer#send_message` ← `Vc::ApplicationsController#send_email` (`POST /vc/applications/:id/send_email`) and `#preview_email`; deliver_now plus a `prospective_application_log` row via `ProspectiveApplicationStatusMail.deliver_and_log`, and `mail_log` rows carrying the application; always to `application.email` — setting `PROSPECTIVE_APPLICATION_MAIL_SANDBOX` (read only by `ProspectiveApplicationMailer#build_mail`) does not redirect it — `db/mail_templates/prospective_application/send_email_mailer/send_message.yml`
Mail: `ProspectiveApplication::ApprovedReminderMailer` ← `PendingApplicationsJob` — `db/mail_templates/prospective_application/approved_reminder_mailer/notify.yml`
Mail: shared pieces `shared/mailer/*` (`application_footer`, `bot_sign_off`, `do_not_reply`, `on_hold`, `ranger_header_image`, `vc_email`) ← `{% render %}` in other templates via `MailTemplateFileSystem` (`app/lib/mail_template_file_system.rb`) — `db/mail_templates/shared/mailer/*.yml`
Owner: `ApplicationMailer` (`app/mailers/application_mailer.rb`), `MailTemplateResolver` (`app/lib/mail_template_resolver.rb`), `MailTemplateRenderer` (`app/lib/mail_template_renderer.rb`), `SesMailDelivery` (`app/lib/ses_mail_delivery.rb`), `SuppressedRecipientsInterceptor` (`app/lib/suppressed_recipients_interceptor.rb`), `MailTestAddressInterceptor` (`app/lib/mail_test_address_interceptor.rb`), all three set up in `config/initializers/mail_delivery.rb`
Touches: `mail_template`, `setting`, `mail_log` (w), `prospective_application_log` (w), `broadcast` (w), `broadcast_message` (w), `person_alert`, `person` (w), `email_suppression`, `action_logs` (w), `error_logs` (w)
Verify: `test/mailers/mail_template_coverage_test.rb`, `test/mailers/application_mailer_test.rb`, `test/mailers/prospective_application_mailer_test.rb`, `test/lib/mail_template_renderer_test.rb`, `test/lib/mail_template_seeds_test.rb`, `test/mailers/contact_mailer_test.rb`, `test/lib/prospective_application_status_mail_test.rb`, `test/lib/ses_mail_delivery_test.rb`, `test/lib/suppressed_recipients_interceptor_test.rb`, `test/lib/mail_test_address_interceptor_test.rb`, `test/mailers/training_session_full_mailer_test.rb`, `test/mailers/trainer_reminder_mailer_test.rb`, `test/mailers/welcome_mailer_test.rb`, `test/mailers/update_mailing_list_subscriptions_mailer_test.rb`
Trap: production sends all of this mail by SMTP (`config/environments/production.rb`, to mailpit) until `RANGER_CLUBHOUSE_SES_MAIL_LIVE=true` sets `config.x.ses_mail_live`, read only as `== true` (declared false in `config/application.rb`; development and test never set it, and tests stay on `:test`). Then `SesMailDelivery.install!`, from the `after_initialize` block in `config/initializers/mail_delivery.rb`, builds one `Aws::SESV2::Client` and makes `:ses_mail` the delivery method; the SMTP lines stay as the default. It refuses to boot (`SesMailDelivery::ConfigurationError`) without `AWS_REGION` or the keys in `ses.env`, and asks AWS nothing. The client has the SDK's retries off, 5 s to connect and 20 s to answer, and the short log formatter: the default one would write every recipient and the start of the raw message, a password reset's link included, to the production log.
Trap: there is one client for all mail, in `ses_mail_settings[:sesv2_client]`. ActionMailer builds the delivery method inside every `mail()` call, so without it each would build a client and look up the keys again — also for mail never sent: `RbsMailer`'s render, `ProspectiveApplicationStatusMail.preview`, `Vc::ApplicationsController#preview_email` and the training server's held mail.
Trap: `SesMailDelivery#deliver!` tries again, in process, only a call SES never took: `TooManyRequestsException` or `LimitExceededException`, or a connection never made (`Rbs::NEVER_CONNECTED`, bare or inside `Seahorse::Client::NetworkingError`). A read timeout, a 5xx, `MessageRejected`, a paused account and missing keys fail at once, since SES may already have sent the email or the next try would fail the same way. At most 3 tries, pausing 0.5 s then 1 s, and a try starts only while the time since the first began, plus its pause, is at most 4 s — so a delivery ends within 29 s, inside Solid Queue's 30 s `shutdown_timeout`. Giving up writes one `ses-mail-exception` error log naming the mailer and the tries (never an address or the body) and raises: `deliver_later` mail lands in Solid Queue's failed executions, and `deliver_now` in a request (password reset, photo review, VC status and send-email) shows an error page with the change already saved.
Trap: once `RANGER_CLUBHOUSE_SES_MAIL_LIVE` is on, new-message alerts go through SES too; a broadcast fills the account's whole send rate (`Rbs.ses_batch_size`), so other mail sent during one can be throttled (the retries absorb a short throttle); an address SES refuses fails that email's whole call, for every recipient on it; and the SES webhook's `person.is_bouncing` write fires for this mail as it did for Clubhouse 2's (nothing here reads or writes the column).
Trap: `RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS` sends every delivered ActionMailer email to that one inbox, in any environment that sets it. It is an environment variable read at each delivery, not a setting: a Clubhouse 2 restore replaces the setting table and would clear it. `MailTestAddressInterceptor` makes To the address, removes Cc, Bcc and any `smtp_envelope_to`, and names the real recipients in `X-Clubhouse-Original-Recipients`; subject and body are unchanged, and held mail (`perform_deliveries` false, the training server's) keeps its real recipients. It covers all ActionMailer mail, new-message alerts and the scheduled team mail included, but never RBS broadcast email, which no interceptor sees (it has `BroadcastMailTestAddress`). A value `EmailAddresses.sendable?` refuses stops the boot. Interceptors run in the order registered, so `SuppressedRecipientsInterceptor` is registered ahead of it in `config/initializers/mail_delivery.rb`: it must see the real recipients. The inbox then gets an email only when a live recipient is left, and the header names only the live ones, as live mail would go.
Trap: every ActionMailer email asks `email_suppression` once, for its To, Cc and Bcc addresses together (`SuppressedRecipientsInterceptor`, a Mail interceptor registered in every environment, ahead of the test address). Each suppressed address — a bounce or a complaint row, matched however `person.email` is cased — is dropped from its field, the others stay as written, a field left empty is removed, and each dropped address gets one `email-suppressed` action log (actor nobody, target `Person.find_by(email:)`, data `to_email`, `mailer`, `subject`, never the body), which the Action Logs filter's "Email Bounces/Complaints" (`email-%`) finds and `DailyReportJob::EMAIL_EVENTS` leaves out. An email left with nobody is held (`perform_deliveries` false), so neither SMTP nor SES is asked and it has no `mail_log` row — but status mail still writes its "emailed" `prospective_application_log` entry, as it does for the training server's held mail (accepted). Held mail is not looked at. A lookup that raises lets the email go unfiltered and writes one `email-suppression-lookup-failed` error log; an action log that cannot be written writes one `email-suppressed-log-failed` error log; neither stops the email. New-message alerts ask the record before they are queued (`Rbs.message_notify`), so it drops one, and writes its `email-suppressed` log, only when the address was suppressed in between. RBS broadcast email (`Rbs.broadcast_email`, SES `SendBulkEmail`) never passes through it; RBS asks the record itself (see Ranger Broadcast System (Rbs)).
Trap: every email here gets `mail_log` rows, one per To address, from `ApplicationMailer#record_mail_log` (an `after_deliver` callback) as it is delivered, whether `deliver_now` or a `deliver_later` job sends it; no sender writes them, and only `RbsMailer`, never delivered, gets none. `PasswordResetMailer`, `WelcomeMailer`, `OnlineCourseResetPasswordMailer`, `ClubhouseNewMessageMailer` and `ContactMailer` keep no body (`self.withhold_body_from_mail_log = true`); a new mailer whose email carries a sign-in secret or a private message sets it too. See MailLog.
Trap: a new `deliver_later` must pass `.with(sender_id:)`, or its rows log no sender: the job builds the email again with nobody signed in, and `ApplicationMailer#set_sender_id` reads `params[:sender_id]` before `Current.person`. The nine queued calls do — `WelcomeMailer` (`PersonController#resend_welcome`, `ProspectiveClubhouseAccountFromApplication#send_welcome_email`), `ClubhouseNewMessageMailer` (`Rbs.message_notify`, its `sender_id` argument), `AutomaticActiveConversionMailer` (`ShiftManage.convert_inactive_to_active`, the user ending the shift), `TrainingSessionFullMailer` (`Scheduling::Signup`) and `PasskeyMailer`'s four (`Me::PasskeysController`, `Person::PasskeysController`, `current_user`; not its `by:`, so it is no exception) — but not `AccountCreationMailer` (nobody is signed in at `/register`). The ten mailers with no caller yet (`ContactMailer`, `TrainingSignupMailer`, `OnlineCourseEnrollmentMailer`, `OnlineCourseCompletedMailer`, `OnlineCourseResetPasswordMailer`, `NotifyVcEmailChangeMailer`, `AutomaticSignOutMailer`, `TrainerReminderMailer`, `PhotosExpiredMailer`, `UpdateMailingListSubscriptionsMailer`) need it once one queues them. `assert_enqueued_email_with` then needs `params: { sender_id: … }`: its matcher compares `params` too, so an assertion without `params:` matches only an email queued without them.
Trap: `Scheduling::Signup` queues `TrainingSessionFullMailer.with(sender_id: Current.person_id).notify(slot:, signed_up:, notify_email:)`: `.with` carries only `sender_id:`, and the slot stays a keyword argument, since `notify` takes keywords, not `params`.
Trap: a link in a message comes from a route `_url` helper (`reset_token_url`, `person_url`; `ApplicationMailer#logo_url` is `asset_url("ranger-logo.png", host: root_url)`, since no asset host is set), on the host `config.action_mailer.default_url_options` names (`config/environments/production.rb`, `clubhouse3.dev`; `force_ssl` makes it `https`) — the one host to change at cutover — never a hard-coded host. `Rails.application.routes.default_url_options` is unset, and `"#{root_url}#{asset_path(…)}"` doubles the slash. The one template that still hard-codes Clubhouse 2's host is the more-handles email's HandleAdvice link, #25's in `.scratch/rbs-ses-bulk-email/issues/`.
Trap: a template writes the Clubhouse's address as `{{ clubhouse_url }}` (`root_url`, from `ApplicationMailer#liquid_assigns`, so every message has it), never a host, and `MailTemplateSeedsTest` refuses Clubhouse 2's (`ranger-clubhouse.burningman.org`) in every `db/mail_templates` file, with one allowance until #25; a deep link is a value its mailer builds with a route helper (`PhotoPendingMailer`'s `review_url`, `VehiclePendingMailer`'s `registry_url`). A name the mailer doesn't supply prints as nothing, so `href=""` with no error (`MailTemplateRenderer.render` has no strict variables). A shared piece drawn with `{% render %}` sees only what it is passed: `{% render "shared/mailer/…", clubhouse_url: clubhouse_url %}`, as `welcome_mailer/notify.yml` passes `logo_url`.
