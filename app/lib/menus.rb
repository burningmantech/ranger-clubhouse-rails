# frozen_string_literal: true

module Menus
  # Sections are defined once and shared between the sidebar menus (ME, ADMIN)
  # and the mega-menu categories (MEGA_CATEGORIES). Item :description is shown
  # only by the mega menu; sidebar and navbar renderers ignore it.

  MY_CLUBHOUSE_SECTION = {
    title: "Essentials",
    items: [
      { title: "Clubhouse Dashboard", path: :me_root_path, root: true,
        description: "Your tasks, deadlines, and event updates at a glance" },
      # The navbar's unread envelope asks the same Person#mailbox_user?.
      { title: "Messages", path: :me_messages_path,
        description: "Read and send Clubhouse messages",
        visible_if: { status: [:mailbox_user?] } },
      # Past prospectives reach only the dashboard and their profile
      # (ApplicationController#confine_past_prospective), so this item and the
      # Pre-Event and Communication sections hide from them.
      { title: "Schedule / Sign-Ups", path: :me_schedule_path,
        description: "Browse shifts and trainings, and manage your sign-ups",
        visible_if: { not_status: [:past_prospective?] } },
      {
        title: "Self Check In/Out",
        path: :me_shift_manage_path,
        description: "Check in and out of your shifts",
        visible_if: {
          roles: [Role::ADMIN, Role::SHIFT_MANAGEMENT_SELF],
          setting: Setting::SHIFT_MANAGEMENT_SELF_ENABLED
        }
      },
      {
        title: "Timesheet",
        path: :me_timesheet_dashboard_path,
        description: "Review and confirm your service hours",
        visible_if: { status: [:is_ranger?, :is_echelon?] }
      }
    ]
  }.freeze

  RANGER_PROFILE_SECTION = {
    title: "Profile & Recognition",
    submenu: true,
    visible_if: { status: [:is_ranger?, :is_echelon?] },
    items: [
      { title: "Profile", path: :me_profile_path,
        description: "Update your contact info, emergency contacts, and photo" },
      {
        title: "Service Recognition",
        path: :me_awards_path,
        description: "See your years of service and recognition awards",
        visible_if: { status: [:is_ranger?, :is_echelon?] }
      }
    ]
  }.freeze

  APPLICANT_AUDITOR_PROFILE_SECTION = {
    title: "Profile",
    submenu: true,
    visible_if: { not_status: [:is_ranger?, :is_echelon?] },
    items: [
      { title: "Profile", path: :me_profile_path,
        description: "Update your contact info, emergency contacts, and photo" }
    ]

  }.freeze

  PRE_EVENT_SECTION = {
    title: "Pre-Event",
    submenu: true,
    visible_if: { not_status: [:is_auditor?, :past_prospective?] },
    items: [
      { title: "Agreements", path: :me_agreements_path,
        description: "Review and sign required agreements" },
      { title: "Operational Summary", path: :me_operational_summary_path,
        description: "Review your event readiness in one place" },
      { title: "Tickets & Stuff", path: :me_tickets_path,
        description: "Claim tickets, vehicle passes, and other event access items" },
      {
        title: "Vehicle Dashboard",
        path: :me_vehicles_dashboard_path,
        description: "Register personal vehicles and request driving stickers",
        visible_if: { computed: :show_vehicles }
      }
    ]
  }.freeze

  COMMUNICATION_SECTION = {
    title: "Communication",
    submenu: true,
    visible_if: { not_status: [:past_prospective?] },
    items: [
      { title: "Announcements", path: :me_announcements_path,
        description: "Official announcements from the Rangers" },
      { title: "Cadre Directory", path: :me_directory_path,
        description: "Contact information for Ranger cadres and teams",
        visible_if: { status: [:is_ranger?, :is_echelon?] } },
      { title: "Mentoring", path: :me_mentoring_path,
        description: "Your mentors, mentees, and mentoring status",
        visible_if: { status: [:is_ranger?] } }
    ]
  }.freeze

  # The writing side of Communication. Kept apart from COMMUNICATION_SECTION
  # because that one is everybody's reading list and this one is not: the item
  # carries its own role gate, so the section needs none.
  COMMUNICATION_MANAGEMENT = {
    title: "Communication Management",
    icon: "bullhorn",
    sections: [
      items: [
        {
          title: "Announcements",
          path: :communication_announcements_path,
          active_prefix: true,
          description: "Post the messages shown on everyone's Clubhouse home page",
          visible_if: { roles: [Role::ADMIN, Role::ANNOUNCEMENT_MANAGEMENT] }
        },
        {
          title: "Account Banners",
          path: :communication_person_banners_path,
          active_prefix: true,
          description: "Review the banner messages shown on Ranger accounts",
          visible_if: { roles: [Role::ADMIN, Role::VC] }
        },
        {
          title: "Email Templates",
          path: :communication_mail_templates_path,
          active_prefix: true,
          description: "Edit what the emails the Clubhouse sends actually say",
          visible_if: { roles: [Role::ADMIN, Role::VC] }
        },
        {
          title: "Ranger Broadcast",
          path: :communication_rbs_root_path,
          active_prefix: true,
          description: "Send texts, emails, and Clubhouse messages to groups of Rangers",
          visible_if: { roles: Rbs::MEGAPHONE_ROLES }
        },
        {
          title: "Survey Management",
          path: :communication_surveys_path,
          active_prefix: true,
          year_scoped: true,
          description: "Create and edit the feedback surveys shown on the Clubhouse dashboard",
          # A survey role can be one composed for a single training, which no
          # list of role ids can name. The page opens to the same people.
          visible_if: { proc: ->(context) { Survey.can_manage_any?(context[:person]) } }
        }
      ]
    ]
  }.freeze

  # Mega-menu categories. Top-level :title/:description/:icon/:visible_if are
  # read only by the mega menu; sidebar/navbar renderers only read :sections.

  MY_CLUBHOUSE = {
    title: "My Clubhouse",
    description: "Your dashboard, schedule, and profile",
    icon: "house",
    sections: [MY_CLUBHOUSE_SECTION, PRE_EVENT_SECTION, COMMUNICATION_SECTION, APPLICANT_AUDITOR_PROFILE_SECTION, RANGER_PROFILE_SECTION]
  }.freeze

  # The category gate is GONE rather than widened to a union, following
  # SHIFT_OPERATIONS: Event Dates is readable by Tech Ninja while Settings
  # stays Admin-only, and a hand-kept union of the two goes stale silently the
  # next time an item is added. Each item carries the gate its own controller
  # enforces -- AdminMenuTest holds every one to it, because an item left
  # ungated here is offered to every Ranger -- and MegaMenu.categories already
  # drops a category whose sections all build empty.
  ADMIN = {
    title: "Administration",
    description: "Admin tools and settings",
    icon: "screwdriver-wrench",
    sections: [
      # Main menu section
      {
        title: "Admin Menu",
        items: [
          { title: "Documents", path: :admin_documents_path, root: true,
            description: "Edit the documents the Clubhouse displays",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Event Dates", path: :admin_event_dates_path, root: true,
            description: "Set the start and end times for each event year",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "OAuth Clients", path: :admin_oauth_clients_path, root: true,
            description: "Manage the websites that sign people in through the Clubhouse",
            visible_if: { roles: [Role::TECH_NINJA] } },
          { title: "Online Courses", path: :admin_online_courses_path, root: true, year_scoped: true,
            description: "Set the Moodle course each training position uses for a year",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Passkeys", path: :admin_passkeys_path, root: true,
            description: "See every passkey registered across accounts",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Permissions", path: :admin_permissions_path, root: true,
            description: "Review the permissions the Clubhouse grants, and what confers them",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "RBS Alerts", path: :admin_rbs_alerts_path, root: true,
            description: "Edit the wording Rangers read when choosing which alerts to receive",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "Salesforce Query", path: :admin_salesforce_query_path, root: true,
            description: "Run a SOQL query or SOSL search against Salesforce and review the records",
            visible_if: { roles: [Role::TECH_NINJA] } },
          { title: "Settings", path: :admin_settings_path, root: true,
            description: "Configure Clubhouse-wide settings",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Shift Coverage Setup", path: :admin_shift_coverage_groups_path, root: true,
            description: "Set the shift types and posts the Shift Coverage report shows",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } }
        ]
      },
      # Main menu section
      {
        title: "System Logs",
        items: [
          { title: "Action Logs", path: :admin_action_logs_path, root: true,
            description: "Browse the audit log of Clubhouse actions",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Background Jobs", path: :admin_jobs_path, root: true,
            description: "Watch the job queues, retry or delete failed jobs, and see which workers are running",
            visible_if: { roles: [Role::TECH_NINJA] } },
          { title: "Bug Reports", path: :admin_bug_reports_path, root: true,
            description: "Read the problems people reported from the Bug Report button",
            visible_if: { roles: [Role::TECH_NINJA] } },
          { title: "Clubhouse 1 Log", path: :admin_clubhouse1_log_path, root: true,
            description: "Search the audit log kept by the first Clubhouse",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "Error Logs", path: :admin_error_logs_path, root: true,
            description: "Review exceptions and failures recorded by the system",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "Mail Log", path: :admin_mail_log_path, root: true,
            description: "Search the emails the Clubhouse has recorded",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Request Log", path: :admin_request_logs_path, root: true,
            description: "Review the requests the Clubhouse answered",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } }
        ]
      }
    ]
  }.freeze

  # Signed agreements recorded in bulk. Its own category rather than a line in
  # Administration: the per-person agreements page already lives under PERSON,
  # and the pages that record them for a list of people are a different job from
  # configuring the Clubhouse.
  AGREEMENTS = {
    title: "Agreements",
    description: "Signed agreements recorded for many people at once",
    icon: "file-signature",
    visible_if: { roles: [Role::ADMIN] },
    sections: [
      {
        title: "Agreements Menu",
        items: [
          { title: "Bulk Record a Signature", path: :agreements_bulk_signature_path,
            root: true, active_prefix: true,
            description: "Record one signed agreement for a pasted list of callsigns" }
        ]
      }
    ]
  }.freeze

  # Records and reports covering many people at once. The per-person pages live
  # under PERSON, which needs a person to be looking at; these need only a list.
  #
  # No category gate, following SHIFT_OPERATIONS: the items admit different
  # people, and a hand-kept union of their roles goes stale silently the next
  # time an item is added. A category whose every item is hidden drops out on
  # its own, so each item carries its own gate and nothing has to be kept in
  # step by hand. An Event Management gate lived here briefly and hid every
  # Admin-only page in the category from an Admin who did not also hold Event
  # Management -- PeopleMenuTest now holds each item to its controller.
  PEOPLE = {
    title: "People",
    description: "Records and reports covering many people at once",
    icon: "users-gear",
    sections: [
      {
        title: "People Menu",
        items: [
          { title: "Bulk Lookup", path: :people_bulk_lookup_path,
            active_prefix: true,
            description: "Look up person records for a pasted list of callsigns or email addresses",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Create Account", path: :people_create_account_path,
            root: true,
            description: "Create a Clubhouse account and set its first password",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Languages Known", path: :people_languages_known_path,
            active_prefix: true,
            description: "Who speaks what, and who is on a shift right now",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          { title: "People by Location", path: :people_by_location_path,
            active_prefix: true, year_scoped: true,
            description: "Where everyone lives, grouped by country and state",
            visible_if: { roles: [Role::ADMIN, Role::MENTOR, Role::TRAINER, Role::VC] } },
          { title: "People by Status", path: :people_by_status_path,
            active_prefix: true,
            description: "Every account, grouped by the status it holds right now",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "People Search", path: :people_search_path,
            active_prefix: true,
            description: "Find accounts by status, history, training, photo, and ticketing progress",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Retention Report", path: :people_retention_report_path,
            active_prefix: true,
            description: "Rangers who rangered any of the last five events, for the post-event survey",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Unified Flagging", path: :people_unified_flagging_path,
            active_prefix: true, year_scoped: true,
            description: "Everyone the intake teams noted, ranked, flagged, or bonked in a year",
            visible_if: { roles: [Role::ADMIN] } }
        ]
      },
      {
        title: "Account Maintenance",
        items: [
          # Exact match only: the form posts back to its own path, and nothing
          # lives underneath it.
          { title: "Bulk Change Status", path: :people_bulk_status_path,
            root: true, active_prefix: true,
            description: "Set the status, or the vintage flag, for a pasted list of callsigns",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Status Change Recommendations", path: :people_status_change_recommendations_path,
            active_prefix: true,
            description: "Status changes to consider now that an event is over (fka People By Status Change)",
            visible_if: { roles: [Role::ADMIN] } }
        ]
      }
    ]
  }.freeze

  # Certification records and reports covering many people at once, e.g. a class
  # roster after a training session, or everyone holding a given certification.
  #
  # No category gate, following PEOPLE: the two items admit different people, and
  # a hand-kept union of their roles goes stale silently the next time an item is
  # added. A category whose every item is hidden drops out on its own.
  CERTIFICATES = {
    title: "Certificates",
    description: "Certification records and reports covering many people at once",
    icon: "certificate",
    sections: [
      {
        title: "Certificates Menu",
        items: [
          { title: "Certificates Report", path: :certificates_report_path,
            active_prefix: true,
            description: "Who holds each certification, with the dates and card numbers",
            visible_if: { roles: [Role::ADMIN, Role::CERTIFICATION_MGMT] } },
          { title: "Bulk Record Certifications", path: :certificates_bulk_record_path,
            root: true, active_prefix: true,
            description: "Record or update one certification for a pasted list of callsigns",
            visible_if: { roles: [Role::ADMIN] } }
        ]
      }
    ]
  }.freeze

  # No category gate, following PEOPLE. Most of this category is VC's own work,
  # but four pages belong to a role that reaches nothing else here: Intake files
  # notes on the pipeline, Edit Handle Reservations keeps the reserved list, and
  # Salesforce Import runs the two import pages. An Admin-or-VC category gate
  # hid all four from exactly the people they were built for, and the VC sidebar
  # -- which never reads a category gate -- had the mirror problem, offering
  # every ungated page to an Intake reader whose controller then bounced them.
  # Each item carries the gate its own controller enforces; VcMenuTest holds it
  # to that, and an item added without a gate fails rather than going to all.
  VC = {
    title: "Volunteer Coordinator",
    description: "Volunteer application processing",
    icon: "clipboard-user",
    sections: [
      {
        title: "VC Menu",
        items: [
          { title: "BPGUID Lookup", path: :vc_bpguid_path, active_prefix: true,
            description: "Find a person's Burner Profile in Salesforce and link it to their account",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Handle Checker", path: :vc_handle_checker_path, active_prefix: true,
            description: "Check a proposed handle for conflicts",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Photo Review", path: :vc_photos_review_path, active_prefix: true,
            description: "Approve or reject submitted BMID photos",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Photos", path: :vc_photos_path, active_prefix: true,
            description: "Browse all Clubhouse photos",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          # Edit Handle Reservations is the role that may change the list; VC
          # alone reads it (see the controller's manage_reserved_handles gate).
          { title: "Reserved Handles", path: :vc_reserved_handles_path, active_prefix: true,
            description: "Manage handles that must not be issued as callsigns",
            visible_if: { roles: [Role::ADMIN, Role::VC, Role::EDIT_HANDLE_RESERVATIONS] } },
          { title: "Spigot Flow Report", path: :vc_spigot_flow_report_path, active_prefix: true, year_scoped: true,
            description: "Daily counts of applicants moving through intake milestones",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Unified Flagging", path: :vc_unified_flagging_path, active_prefix: true, year_scoped: true,
            description: "Applicant pipeline with every team's ranks, flags, and notes",
            visible_if: { roles: [Role::ADMIN, Role::VC, Role::INTAKE] } }
        ]
      },
      {
        title: "Applications",
        items: [
          { title: "Applications", path: :vc_applications_path, root: true, active_prefix: true, year_scoped: true,
            description: "Review and process volunteer applications",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Application Import", path: :vc_application_import_path, active_prefix: true,
            description: "Import Ranger applications from Salesforce",
            visible_if: { roles: [Role::ADMIN, Role::SALESFORCE_IMPORT] }
          },
          { title: "Create Prospectives", path: :vc_create_prospectives_path, active_prefix: true,
            description: "Create prospective accounts from approved applications",
            visible_if: { roles: [Role::ADMIN, Role::SALESFORCE_IMPORT] }
          }
        ]
      },
      {
        title: "Post-Event",
        items: [
          { title: "Maintenance", path: :vc_maintenance_path, active_prefix: true,
            description: "Bulk reset applicant statuses and callsigns after the event",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Shiny Penny Report", path: :vc_shiny_penny_report_path, active_prefix: true, year_scoped: true,
            description: "Rangers who passed training and mentoring in a given year",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Thank You Cards", path: :vc_thank_you_cards_path, active_prefix: true, year_scoped: true,
            description: "Mailing addresses for everyone who rangered during a given year",
            visible_if: { roles: [Role::ADMIN, Role::VC] } }
        ]
      }
    ]
  }.freeze

  # The roster pages are not year_scoped: they report current standing and
  # ignore ?year= entirely (see Mentoring::PotentialAlphasController#setup_year).
  # Shift Report and Alpha Schedule are the exceptions -- both read a chosen
  # year's Alpha shifts.
  MENTORING = {
    title: "Mentoring",
    description: "Potential Alphas and the mentor cadre",
    icon: "handshake-angle",
    visible_if: { roles: [Role::ADMIN, Role::MENTOR] },
    sections: [
      {
        title: "Pre-Event",
        items: [
          { title: "Potential Alphas", path: :mentoring_potential_alphas_path, root: true, active_prefix: true,
            description: "Prospectives and Alphas with every team's ranks, flags, and notes" },
          { title: "Convert Prospectives", path: :mentoring_convert_prospectives_path, active_prefix: true,
            description: "Bulk-convert Prospectives who passed training to Alpha status" },
          { title: "Alpha Status", path: :mentoring_alpha_status_path, active_prefix: true,
            description: "Where this year's Prospectives and Alphas stand, and who to chase next" }
        ]
      },
      {
        title: "Scheduling",
        items: [
          { title: "Alpha Schedule", path: :mentoring_alpha_schedule_path, active_prefix: true, year_scoped: true,
            description: "Alpha shift rosters, sign-ins, and the printable Alpha-day sheets" },
          { title: "Shift Report", path: :mentoring_shift_report_path, active_prefix: true, year_scoped: true,
            description: "Who is signed up for an Alpha shift, or on duty right now, across the mentor cadre" }
        ]
      },
      {
        title: "Alpha Management",
        items: [
          { title: "Acceptance Sheets", path: :mentoring_alpha_acceptance_sheets_path, active_prefix: true,
            description: "Print the acceptance forms the mentor cadre signs to accept an Alpha" },
          # The walk has happened by the time anyone opens this page...
          { title: "Mentor Assignments", path: :mentoring_alpha_mentor_assignments_path, active_prefix: true,
            description: "Record who mentored each Alpha and whether they passed, bonked, or self-bonked" },
          # ...and this is what those recorded verdicts are then carried out on.
          { title: "Alpha Pods", path: :mentoring_alpha_pods_path, active_prefix: true, year_scoped: true,
            description: "Form the mentor, MITten, and Alpha pods that walk each Alpha shift" },
          # The pods walk the shift, this ends it, and the sheets below are
          # signed afterwards. Not year_scoped: the page pins Current.year
          # because it writes against entries that are open right now.
          { title: "Convert Alphas", path: :mentoring_alphas_convert_path, active_prefix: true,
            description: "Mint passed Alphas into active Rangers, and move bonked Alphas to bonked status" },
          { title: "Alpha Sign-Out", path: :mentoring_alpha_signout_path, active_prefix: true,
            description: "End the shift for Alphas still on duty after an Alpha walk" }
        ]
      },
      {
        title: "Post Event",
        items: [
          { title: "Post Season Summary", path: :mentoring_post_season_summary_path, active_prefix: true,
            year_scoped: true,
            description: "Review a season's whole class: who walked, who bonked, and what the Mentors concluded" },
          # Shown to the whole section, though reading a survey needs the Alpha
          # survey-management role on top of Mentor -- the page says so rather
          # than the menu hiding a link most of the cadre could not explain the
          # absence of. Not year_scoped: the index lists every year at once.
          { title: "Alpha Surveys", path: :mentoring_surveys_path, active_prefix: true,
            description: "What each year's Alphas said about their mentors, by report and by mentor" }
        ]
      }
    ]
  }.freeze

  # No category-level visible_if since the Flake Report opened the category to
  # Event Management: every item gates itself, and MegaMenu.categories drops a
  # category whose sections all build empty. A hand-kept union of the item
  # gates can only ever go stale (see the Quartermaster comment).
  SCHEDULING = {
    title: "Scheduling",
    description: "Manage shift slots for each position",
    icon: "calendar-days",
    sections: [
      {
        title: "Forecast Reports",
        items: [
          # Listed here because what a shift lead opens it for is the forecast:
          # who is covering the next few hours.
          { title: "Shift Lead Report", path: :scheduling_shift_lead_path,
            active_prefix: true, year_scoped: true,
            description: "Who is covering a shift period, and which positions are short",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          # Lives beside the Shift Lead Report because upstream's Reports menu
          # lists the two next to each other under "Schedule".
          { title: "Schedule by Callsign", path: :scheduling_schedule_by_callsign_path,
            active_prefix: true, year_scoped: true,
            description: "Who signed up for shifts this year, callsign by callsign",
            # Edit Slots too, matching the controller: upstream's SlotPolicy
            # before hook lets them through to every slot report.
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # The same sign-ups read the other way round, and listed next after
          # its callsign twin the way upstream's Reports menu lists the pair.
          { title: "Schedule by Position", path: :scheduling_schedule_by_position_path,
            active_prefix: true, year_scoped: true,
            description: "Who signed up for shifts this year, position by position",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # The same sign-ups read a third way: hour by hour, across the posts
          # that have to be covered together. Same gate as the two above it,
          # off the same policy.
          { title: "Shift Coverage", path: :scheduling_shift_coverage_path,
            active_prefix: true, year_scoped: true,
            description: "Who is scheduled at each post, period by period, for one kind of shift",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # The same shifts counted rather than named: which ones still need
          # people. Listed after the schedule pair it drills across into.
          { title: "Shift Sign-Ups", path: :scheduling_shift_signups_path,
            active_prefix: true, year_scoped: true,
            description: "Every shift for the year and how full it is, position by position",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # The same shifts read as traffic: how many people each period sends
          # to the HQ window, and who is there to meet them. Same gate as the
          # reports above it, off the same policy.
          { title: "HQ Check In/Out Forecast", path: :scheduling_hq_forecast_path,
            active_prefix: true, year_scoped: true,
            description: "How busy the HQ window will be each period, and who is staffing it",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # A narrower gate than its neighbours: training and affidavits are
          # Event Management's to chase, and Edit Slots has no part in it.
          { title: "Sandman Qualifications", path: :scheduling_sandman_qualified_path,
            active_prefix: true, year_scoped: true,
            description: "Who may stand a Sandman shift, and what everyone else still needs",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          # A different gate again from anything else in this group: arrival
          # passes are the access document team's to issue, so the report
          # answers to the roles those passes do.
          { title: "Early Arrivals", path: :scheduling_early_arrivals_path,
            active_prefix: true, year_scoped: true,
            description: "Who arrives before gate opening, for SITE Setup arrival packets",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_ACCESS_DOCS] } }
        ]
      },
      {
        title: "Shift Change Reports",
        items: [
          { title: "Flake Report", path: :scheduling_flake_report_path, active_prefix: true,
            year_scoped: true,
            description: "Who signed up but never rangered the shift, and who rangered one without signing up",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS, Role::EVENT_MANAGEMENT] } },
          # Same gate as the shift drop report above, and for the same reason:
          # upstream hangs this one off the timesheet policy too.
          { title: "No Shows Report", path: :scheduling_no_shows_report_path,
            active_prefix: true, year_scoped: true,
            description: "Who signed up for a shift and was never on duty for it",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT] } },
          # A narrower gate than its neighbour on purpose: upstream hangs this
          # report off the timesheet policy, which never admits Edit Slots.
          { title: "Shift Drop Report", path: :scheduling_shift_drop_report_path,
            active_prefix: true, year_scoped: true,
            description: "Who dropped a shift close to its start, position by position",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT, Role::EVENT_MANAGEMENT] } }
        ]
      },
      {
        # Its own section rather than a home among the shift reports: this page
        # summarizes the event as a whole, so it is neither a forecast nor a
        # record of shifts changing hands.
        title: "Event Reports",
        items: [
          { title: "Event Statistics", path: :scheduling_event_stats_path,
            active_prefix: true, year_scoped: true,
            description: "How the event turned out: turnout, Alphas, and training completion",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } }
        ]
      },
      {
        title: "Scheduling Admin",
        items: [
          { title: "Slots", path: :scheduling_slots_path, root: true, active_prefix: true, year_scoped: true,
            description: "Create, copy, and bulk edit shift slots",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SLOTS] } },
          { title: "Position Credits", path: :scheduling_position_credits_path, active_prefix: true, year_scoped: true,
            description: "Set the credits earned per hour for each position",
            visible_if: { roles: [Role::ADMIN] } }
        ]
      }
    ]
  }.freeze

  # Whole-board shift actions: what you reach for at the end of an event, as
  # opposed to the one-Ranger-at-a-time work of the HQ window.
  #
  # This category carried a `visible_if` back when Mass Sign-Out was its only
  # item and the gates matched exactly. Bulk Sign In/Out admits Timesheet
  # Management as well, so the category gate is GONE rather than widened to a
  # union: a hand-kept union goes stale silently, and an Admin-only category
  # gate would have hidden this page from every Timesheet Management reader it
  # is meant for. SCHEDULING and QUARTERMASTER carry none for the same reason,
  # and MegaMenu.categories already hides a category whose sections all build
  # empty. Do not put one back.
  SHIFT_OPERATIONS = {
    title: "Shift Operations",
    description: "Actions taken across everyone on duty at once",
    icon: "clock-rotate-left",
    sections: [
      {
        title: "Shift Operations Menu",
        items: [
          { title: "Bulk Sign In/Out", path: :shift_operations_bulk_sign_in_out_path,
            active_prefix: true,
            description: "Sign a pasted list of Rangers in and/or out at once",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # year_scoped: a pod belongs to a shift, and shifts belong to a year.
          # active_prefix because the pod and membership routes hang off this
          # path.
          { title: "Cruise Direction", path: :shift_operations_cruise_direction_path,
            active_prefix: true, year_scoped: true,
            description: "Manage the pods out on a dirt shift",
            visible_if: { roles: [Role::ADMIN, Role::POD_MANAGEMENT] } },
          # root: with no active_prefix -- the page has no descendants to stay
          # lit on, and the POST lands back on this exact path.
          { title: "Mass Sign-Out", path: :shift_operations_mass_signout_path, root: true,
            description: "Sign out everyone still on duty in one sweep",
            visible_if: { roles: [Role::ADMIN] } },
          # The wall display. root: for the same reason as Mass Sign-Out -- one
          # path, nothing hanging off it.
          { title: "ROC Photo Board",
            path: :shift_operations_roc_photo_board_path, root: true,
            description: "Wall display of who is on duty in the ROC",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          # active_prefix: the two rosters hang off this path, so an exact
          # match would drop the highlight the moment a mode is picked.
          { title: "Roll Call", path: :shift_operations_rollcall_path,
            active_prefix: true,
            description: "Sign a whole crew in or out by tapping names",
            visible_if: { roles: [Role::ADMIN, Role::SHIFT_MANAGEMENT] } }
        ]
      },
      # Its own section rather than another line in the menu above: this is the
      # one place in the category where the reader is paying people rather than
      # moving them on and off shift, and the Payroll role that reaches it
      # usually reaches nothing else here.
      {
        title: "Payroll",
        items: [
          # year_scoped: a sign-up belongs to a year. root: one path, nothing
          # hanging off it.
          { title: "Missing Paycom Employee IDs", path: :shift_operations_payroll_missing_id_path,
            root: true, year_scoped: true,
            description: "People signed up for paid shifts with no Paycom Employee ID",
            visible_if: { roles: [Role::ADMIN, Role::PAYROLL] } },
          # Not year_scoped: a pay period is a pair of dates the reader types,
          # and one can straddle the turn of a year.
          { title: "Payroll Export", path: :shift_operations_payroll_export_path, root: true,
            description: "Timesheet entries for a pay period, and the files payroll loads",
            visible_if: { roles: [Role::ADMIN, Role::PAYROLL] } }
        ]
      }
    ]
  }.freeze

  # The summary page sits at the namespace root and the records page hangs off
  # it, so the summary item stays on an exact match (root: true, no
  # active_prefix) — with a prefix match it would light up on the records page
  # too and neither item would tell you where you are.
  TICKETING = {
    title: "Ticketing",
    description: "Tickets, passes, and credentials",
    icon: "ticket",
    visible_if: { roles: [Role::ADMIN, Role::EDIT_ACCESS_DOCS] },
    sections: [
      {
        title: "Ticketing Menu",
        items: [
          { title: "Summary", path: :ticketing_access_documents_path, root: true,
            description: "Everyone holding a ticket, pass, or credential, one row per person" },
          { title: "Current Documents", path: :ticketing_access_documents_records_path, active_prefix: true,
            description: "Every current ticket, pass, and credential, with filters and CSV export" },
          { title: "Provisions", path: :ticketing_provisions_path, active_prefix: true,
            description: "Every current meal pass, shower pass, and event radio, with filters and CSV export" },
          { title: "TRS Export", path: :ticketing_trs_export_path, active_prefix: true,
            description: "Send claimed tickets, passes, and credentials to the ticket vendor, then mark them submitted" },
          { title: "Statistics", path: :ticketing_statistics_path, active_prefix: true,
            description: "How many tickets, passes, and credentials sit in each status right now" }
        ]
      },
      {
        title: "Reports",
        items: [
          { title: "Claimed, Didn't Ranger", path: :ticketing_claimed_with_no_signups_path, active_prefix: true,
            description: "Ticket holders who have not both finished the online course and worked a shift" },
          { title: "Expiring Tickets", path: :ticketing_expiring_path, active_prefix: true,
            description: "Unclaimed and banked tickets that lapse at the end of the coming event" },
          { title: "SAP Candidates", path: :ticketing_sap_candidates_path, active_prefix: true,
            description: "Rangers with no setup access pass who hold a ticket or have signed up this year" },
          { title: "Unclaimed w/Sign-Ups", path: :ticketing_unclaimed_with_signups_path, active_prefix: true,
            description: "Unclaimed tickets, flagged when the holder has signed up for a late-season shift" }
        ]
      },
      {
        title: "Maintenance",
        items: [
          # The two ticketing halves of upstream's admin/bulk-upload. Bulk BMID
          # shares their URL prefix but not their gate, so it is listed in the
          # BMID menu instead.
          { title: "Bulk Access Documents", path: :ticketing_bulk_access_documents_path, active_prefix: true,
            description: "Create tickets, passes, and credentials — or set SAP access dates — for a pasted list" },
          { title: "Bulk Provisions", path: :ticketing_bulk_provisions_path, active_prefix: true,
            description: "Grant earned or allocated meal passes, showers, and event radios to a pasted list" },
          # active_prefix also lights this up on every task's preview page.
          { title: "Maintenance Tasks", path: :ticketing_maintenance_path, active_prefix: true,
            description: "Seasonal bulk operations on tickets and provisions, each with a preview step" },
          { title: "Un-Submit Provisions", path: :ticketing_unsubmit_provisions_path, active_prefix: true,
            description: "Return provisions claimed by people who did not ranger back to available" }
        ]
      }
    ]
  }.freeze

  # New area, opened by the On Duty port. The other timesheet reports land here
  # as they are ported. No category-level visible_if -- every item gates itself,
  # and MegaMenu.categories drops a category whose sections all build empty.
  TIMESHEETS = {
    title: "Timesheets",
    description: "Who is on duty, and the hours everyone has turned in",
    icon: "clock",
    sections: [
      {
        title: "Reports",
        items: [
          # Narrower than its neighbours on purpose: upstream's policy admits
          # Admin and Timesheet Management alone, and an Event Management reader
          # shown this link would only be bounced off the page.
          { title: "Early / Late Check-Ins", path: :timesheets_early_late_checkins_path,
            active_prefix: true, year_scoped: true,
            description: "Check-ins that landed outside the window around their shift",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Forced Shift Starts", path: :timesheets_forced_shift_start_path,
            active_prefix: true, year_scoped: true,
            description: "Shift starts forced past a sign-in blocker, and why",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Hours & Credits", path: :timesheets_hours_credits_path,
            active_prefix: true, year_scoped: true,
            description: "A year's hours and credits per ranger, by part of the season",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # Not year_scoped: the year comes from the duty date, see the
          # controller.
          { title: "On Duty", path: :timesheets_on_duty_path, root: true, active_prefix: true,
            description: "Who is on duty right now, and who has been out too long",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Timesheets by Callsign", path: :timesheets_timesheets_by_callsign_path,
            active_prefix: true, year_scoped: true,
            description: "Everyone's hours and credits for a year, one callsign at a time",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Timesheet by Position", path: :timesheets_timesheet_by_position_path,
            active_prefix: true, year_scoped: true,
            description: "The same year's hours and credits, one position at a time",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Timesheet Totals", path: :timesheets_timesheet_totals_report_path,
            active_prefix: true, year_scoped: true,
            description: "Hours and credits for the year, totaled by position held",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # Not year_scoped: this page carries a span of its own rather than the
          # shared year, and a year handed to it would be ignored.
          { title: "Top Hour Earners", path: :timesheets_top_hour_earners_path,
            active_prefix: true,
            description: "Who put in the most hours in one year of a span",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } }
        ]
      },
      {
        title: "Timesheet Wrangling",
        items: [
          # Same gate and the same reason as Early / Late Check-Ins above.
          # Upstream's label reads "Corrections Requests"; the typo stays there.
          { title: "Correction Requests", path: :timesheets_correction_requests_path,
            active_prefix: true, year_scoped: true,
            description: "Corrections and missing entries still waiting on a decision",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # The decided half of the page above, and the same gate again.
          { title: "Correction Statistics", path: :timesheets_correction_stats_path,
            active_prefix: true, year_scoped: true,
            description: "How the year's correction requests were decided, and by whom",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # Same gate again: upstream's policy admits Timesheet Management alone.
          { title: "Unconfirmed Timesheets", path: :timesheets_timesheet_unconfirmed_path,
            active_prefix: true, year_scoped: true,
            description: "Rangers who logged hours but never confirmed their timesheet",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # Same gate and the same reason as Early / Late Check-Ins above:
          # upstream's policy admits Admin and Timesheet Management alone.
          { title: "Sanity Checker", path: :timesheets_sanity_checker_path,
            active_prefix: true, year_scoped: true,
            description: "Timesheet entries that look wrong, and who to ask about them",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } },
          # Same gate again, and this one also writes: the page and the repair
          # behind it are the same permission.
          { title: "Slot Repair", path: :timesheets_timesheet_slot_repair_path,
            active_prefix: true, year_scoped: true,
            description: "Entries linked to the wrong shift, or to no shift at all",
            visible_if: { roles: [Role::ADMIN, Role::TIMESHEET_MANAGEMENT] } }
        ]
      }
    ]
  }.freeze

  # Meal and shower pogs. Both pages admit Admin and Pog Management only: Event
  # Management keeps Person › Pogs and the HQ window, and is deliberately not
  # let in here. No category gate, for the reason QUARTERMASTER gives below.
  # Administration's filters add query params, hence active_prefix.
  POGS = {
    title: "Pogs",
    description: "Meal and shower pog statistics and record administration",
    icon: "utensils",
    sections: [
      {
        title: "Pogs Menu",
        items: [
          { title: "Pog Dashboard", path: :pogs_dashboard_path, year_scoped: true,
            description: "How many meal and shower pogs were issued in a year, by day and type, and who issued them",
            visible_if: { roles: [Role::ADMIN, Role::POG_MANAGEMENT] } },
          { title: "Pog Administration", path: :pogs_administration_path, active_prefix: true, year_scoped: true,
            description: "Find, correct or delete a pog record",
            visible_if: { roles: [Role::ADMIN, Role::POG_MANAGEMENT] } }
        ]
      }
    ]
  }.freeze

  # The menu is visible to the union of its items' roles, so each item carries
  # its own gate: a Mentor may read Alpha shirt sizes but not edit the catalog,
  # and must not be shown a Swag link that would bounce them.
  QUARTERMASTER = {
    title: "Quartermaster",
    description: "Swag catalog, shirt counts, and years of service",
    icon: "shirt",
    # No category-level visible_if: every item below carries its own gate, and
    # MegaMenu.categories already drops a category whose sections all build
    # empty (the sidebar never consults the category gate at all). A hand-kept
    # union of the item gates can only ever go stale -- forget to widen it when
    # adding an item and the whole category vanishes from /me/menu for exactly
    # the role the item was added for.
    sections: [
      {
        title: "Shifts/Swag Reports",
        items: [
          # Not year_scoped: the report filters on status alone, so it ignores ?year=.
          { title: "Alpha Shirts", path: :quartermaster_alpha_shirts_path, active_prefix: true,
            description: "Shirt sizes and order counts for the current Prospectives and Alphas",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER, Role::MENTOR] } },
          # Year-scoped: the report counts hours for the selected event year.
          # Timesheet Management is carried over from upstream's policy-wide
          # grant, as Events Rangered does.
          { title: "Potential Shirts", path: :quartermaster_potential_shirts_path, active_prefix: true,
            year_scoped: true,
            description: "Who may earn a t-shirt or long sleeve this year, and the shirts to order",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER, Role::TIMESHEET_MANAGEMENT] } },
          # Not year_scoped: the milestone is all-time. Only the sign-up column
          # has a year, and it always asks about the current one.
          { title: "Potential Swag", path: :quartermaster_potential_swag_path, active_prefix: true,
            description: "Who might earn a service pin or patch at the coming event",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER, Role::EDIT_SWAG] } },
          # year_scoped: the report is per-event-year (with its own All option).
          { title: "Swag Distribution", path: :quartermaster_swag_distribution_path,
            active_prefix: true, year_scoped: true,
            description: "What shirts, pins, and patches were handed out during an event",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER] } }
        ]
      },
      {
        title: "Service Reports",
        items: [
          # Not year_scoped: the census is all-time. Only the Signed Up column
          # has a year, and it always asks about the current one.
          { title: "Events Rangered", path: :quartermaster_events_rangered_path, active_prefix: true,
            description: "Years of service for everyone who has rangered, and who has signed up",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER, Role::TIMESHEET_MANAGEMENT] } },
          # Not year_scoped: service years are all-time. active_prefix: the
          # per-group rosters hang off this path. No Timesheet Management here,
          # unlike Events Rangered -- upstream gates this one on AwardPolicy.
          { title: "Freaking Years", path: :quartermaster_freaking_years_path, active_prefix: true,
            description: "Active Rangers grouped by total service years",
            visible_if: { roles: [Role::ADMIN, Role::QUARTERMASTER] } }
        ]
      },
      {
        title: "Maintenance",
        items: [
          { title: "Swag", path: :quartermaster_swag_path, root: true, active_prefix: true,
            description: "Edit the shirts, pins, and patches Rangers can be issued",
            visible_if: { roles: [Role::ADMIN, Role::EDIT_SWAG] } }
        ]
      }
    ]
  }.freeze

  # Team, cadre, and delegation administration. Sized to hold the positions
  # admin port as a sibling item later -- hence the namespace title rather than
  # "Teams".
  TEAMS_POSITIONS = {
    title: "Teams & Positions",
    description: "Team, cadre, position, and lineup records",
    icon: "people-group",
    sections: [
      {
        title: "Teams & Positions Menu",
        items: [
          # Its own computed key rather than manages_team_roster: that one asks
          # Team.manageable_by?, which also demands Event Management, and this
          # page admits any Clubhouse Team Manager. Menu conditions are ANDed,
          # so "an Admin or a team manager" has to arrive as one predicate.
          { title: "Bulk Membership History", path: :teams_positions_bulk_membership_history_path,
            active_prefix: true,
            description: "Record when people joined or left a team, without changing who is on it now",
            visible_if: { computed: :records_team_history } },
          # Same gate as Roster Management, and deliberately the same computed
          # one rather than a copy: both pages ask Team.manageable_by?, so a
          # second predicate could only drift away from it.
          { title: "Bulk Position Grant / Revoke", path: :teams_positions_bulk_positions_path, active_prefix: true,
            description: "Grant or revoke one position for a pasted list of callsigns",
            visible_if: { computed: :manages_team_roster } },
          # The membership twin of the item above, and gated the same way. A
          # team grant carries the team's Recommended positions with it, so the
          # two pages are one operation apart rather than two unrelated tools.
          { title: "Bulk Team Grant / Revoke", path: :teams_positions_bulk_teams_path, active_prefix: true,
            description: "Grant or revoke team membership — and its member positions — for a pasted list of callsigns",
            visible_if: { computed: :manages_team_roster } },
          # None of these are year_scoped: the records are not per-event-year.
          { title: "Team Records", path: :teams_positions_team_records_path, root: true, active_prefix: true,
            description: "Create and edit teams, cadres, and delegations — flags, role grants, and contacts",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          # Read-only, and like the two reports after it, reached by Event
          # Management on the role alone -- upstream gates the report on that
          # role by itself.
          { title: "Membership Report", path: :teams_positions_membership_report_path, active_prefix: true,
            description: "Every active team's roster — who belongs to it, and which teams have no manager",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          # The position twin of the report above, gated the same way and for
          # the same reason -- upstream's PositionPolicy asks for Event
          # Management by itself. Read-only.
          { title: "Position Grants", path: :teams_positions_position_grants_path, active_prefix: true,
            description: "Who holds each position — and who is missing one every Ranger should hold. This is the old People By Position report.",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          # The gate is computed rather than a role list because it asks two
          # questions: Team.manageable_by? wants Admin, Event Management, or
          # Tech Ninja, AND -- for everyone but an Admin or Tech Ninja, who
          # reach every roster -- a team_manager row. The report above needs
          # only the role, which is the difference between the two items.
          { title: "Roster Management", path: :teams_positions_roster_management_path, active_prefix: true,
            description: "Review a team's members and position grants, and remove people from the team",
            visible_if: { computed: :manages_team_roster } },
          # Read-only, and on the same gate as the two reports above: upstream
          # kept the page in the Ember reports area, which only Admin and Event
          # Management could open.
          { title: "Special Teams Hours", path: :teams_positions_special_teams_hours_path, active_prefix: true,
            description: "Hours per year for the positions you choose, with sign-up counts if you ask. This is the old People By Special Teams report.",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } }
        ]
      },
      {
        title: "Administration",
        items: [
          { title: "Position Records", path: :teams_positions_position_records_path, active_prefix: true,
            description: "Create and edit positions — attributes, permission grants, training, and team",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          { title: "Position Lineups", path: :teams_positions_position_lineups_path, active_prefix: true,
            description: "Group positions whose sign-ups are shown together on the Schedule page",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } },
          # Narrower than everything above it: upstream's API gates the checker
          # on Admin and Tech Ninja alone, and its repairs revoke real access.
          # The Ember menu offered it to Event Management, who were then refused
          # by every request the page made.
          { title: "Position Sanity Checker", path: :teams_positions_position_sanity_checker_path,
            active_prefix: true,
            description: "Position, team, and permission grants that contradict each other — and one-click repairs",
            visible_if: { roles: [Role::ADMIN, Role::TECH_NINJA] } }
        ]
      }
    ]
  }.freeze

  # Badge (BMID) management for a whole event year. The person-scoped badge
  # page stays in PERSON; this is the roster view of every badge at once.
  BMID = {
    title: "BMID",
    description: "Burning Man ID badge management",
    icon: "id-card",
    visible_if: { roles: [Role::ADMIN, Role::EDIT_BMIDS] },
    sections: [
      {
        title: "BMID Menu",
        items: [
          { title: "Manage BMIDs", path: :bmid_manage_path, root: true, active_prefix: true, year_scoped: true,
            description: "Every badge for the year — titles, meals, showers, arrival dates, and print status" },
          { title: "Export BMIDs", path: :bmid_export_path, active_prefix: true, year_scoped: true,
            description: "Review the qualified badges and send a print batch to Eventree" },
          # Not year_scoped: the check only ever runs on the current year.
          { title: "BMID Sanity Check", path: :bmid_sanity_check_path, active_prefix: true,
            description: "People whose shift sign-ups conflict with their SAP or Staff Credential access dates" },
          # Not year_scoped: the list belongs to no year, and setting titles
          # only ever touches the current one.
          { title: "BMID Titles", path: :bmid_titles_path, active_prefix: true,
            description: "The titles a position earns on a badge, and the run that sets them" },
          # Lives at /ticketing/bulk-bmid by URL, but belongs to this menu: its
          # gate is Edit BMIDs, which the Ticketing category does not admit.
          { title: "Bulk BMID Actions", path: :ticketing_bulk_bmid_path, active_prefix: true,
            description: "Mark the badges of a pasted list of callsigns as submitted" }
        ]
      }
    ]
  }.freeze

  # Vehicle administration for a whole event year. The self-serve request flow
  # lives under /me; this is the reviewer's side of it.
  #
  # No category gate. It held the union of its three items' roles, which was
  # right the day it was written and is exactly the shape the house rule now
  # forbids: every item added has to be remembered in two places, and nothing
  # fails when it is not. Each item carries the gate its own controller
  # enforces, and MegaMenu.categories drops the category once all three hide.
  VEHICLES = {
    title: "Vehicles",
    description: "Fleet and personal vehicle administration",
    icon: "car",
    sections: [
      {
        title: "Vehicles Menu",
        items: [
          # Event Management On Playa belongs in this gate: the registry's view
          # ability is has_event_management?, which names the raw role. Vehicle
          # Info Update is not in it -- that role may edit a record but not read
          # the list.
          { title: "Vehicle Registry", path: :vehicles_registry_index_path, root: true,
            active_prefix: true, year_scoped: true,
            description: "Every fleet and personal vehicle for the year — permits, stickers, and request review",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA] } },
          # ... and not in this one, though it was listed here until it was
          # measured. Paperwork's ability names EVENT_MANAGEMENT itself, on
          # purpose (see the controller), and a raw on-playa holder gains that
          # only while the setting is on, when RoleManager upgrades them. The
          # raw role written out here showed them the link year-round and
          # bounced them off it every day of the off-season.
          { title: "Vehicle Paperwork", path: :vehicles_paperwork_path, year_scoped: true,
            description: "Who signed the Vehicle Use Protocol, and who may request a Motor Vehicle Record or a personal vehicle",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::VEHICLE_INFO_UPDATE] } },
          # The write side of the audit above, and the only item here gated on
          # Vehicle Management.
          { title: "Bulk Vehicle Paperwork", path: :vehicles_bulk_paperwork_path, active_prefix: true,
            description: "Record motorpool agreements, insurance, and request eligibility for a pasted list",
            visible_if: { roles: [Role::ADMIN, Role::VEHICLE_MANAGEMENT] } }
        ]
      }
    ]
  }.freeze

  ASSET_MANAGEMENT = {
    title: "Asset Management",
    description: "Radios, vehicles, and gear the Rangers hand out",
    icon: "walkie-talkie",
    # Matches the controllers' gate exactly. EVENT_MANAGEMENT_ON_PLAYA is NOT
    # listed: RoleManager upgrades those holders to EVENT_MANAGEMENT while the
    # on-playa setting is on, and drops the role off-season, so listing it
    # would add no one.
    visible_if: { roles: [Role::ADMIN, Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT] },
    sections: [
      {
        title: "Asset Management Menu",
        items: [
          # The entry point the rest of the menu drills down from: start with a
          # barcode in hand rather than with a list.
          { title: "Asset Search", path: :asset_management_search_path,
            active_prefix: true, year_scoped: true,
            description: "Look up one asset by barcode — who has it now, and everywhere it has been" },
          { title: "Assets Outstanding", path: :asset_management_assets_outstanding_path,
            active_prefix: true, year_scoped: true,
            description: "Assets still checked out — who has each one and when it went out" },
          { title: "Asset History", path: :asset_management_asset_history_path,
            active_prefix: true, year_scoped: true,
            description: "Every checkout for the year — who took what, and whether it came back" },
          { title: "Radio Assets", path: :asset_management_radio_assets_path,
            active_prefix: true, year_scoped: true,
            description: "The year's handheld radio inventory — event and shift radios, with a barcode-range summary" },
          { title: "Radio Checkout Report", path: :asset_management_radio_checkout_path,
            active_prefix: true, year_scoped: true,
            description: "Radios held past 14 hours — who is overdue, and who may keep one all event" }
        ]
      },
      {
        title: "Asset Administration",
        items: [
          # Year-scoped: the inventory is per-event-year. active_prefix without
          # root: so the item stays lit on the record pages beneath it -- root:
          # would short-circuit prefix matching and light nothing at all there.
          { title: "Asset Inventory", path: :asset_management_records_path,
            active_prefix: true, year_scoped: true,
            description: "Every barcoded asset for the year — add, edit, and export the inventory" }
        ]
      }
    ]
  }.freeze

  # HQ Window Interface — person-scoped sidebar for layouts/hq.html.erb
  # (Ember port/templates/hq.hbs UiSidebar). Every item is now an in-shell HQ
  # page, so none carries a role gate of its own; see the per-item notes for
  # when each link-out to /person was absorbed. Like PERSON, this menu is
  # excluded from MEGA_CATEGORIES: its route helpers need @person.
  HQ = {
    use_person: true,
    sections: [
      {
        title: "HQ Window",
        visible_if: {
          roles: [Role::ADMIN, Role::SHIFT_MANAGEMENT],
          setting: Setting::HQ_WINDOW_INTERFACE_ENABLED
        },
        items: [
          { title: "Shift Check In/Out", path: :hq_shift_manage_path, active_prefix: true,
            description: "Start and end shifts, issue radios and pogs" },
          { title: "On-Site Registration", path: :hq_site_registration_path, active_prefix: true,
            description: "Register the person as arrived on playa" },
          { title: "Schedule / Sign Ups", path: :hq_scheduling_path, active_prefix: true,
            description: "Browse and manage the person's shift sign-ups" },
          # Inside the shell, and open to the whole HQ persona: delivering
          # messages is a window task, so Hq::MessagesController gates on
          # HqConcern's roles rather than the person page's Event Management.
          { title: "Messages", path: :hq_messages_path, active_prefix: true,
            description: "Read and send Clubhouse messages for the person" },
          # In-shell since 2026-07-22 (was a link-out to /person/N/timesheets
          # gated on Admin/EM/TM): the HQ page runs the person's own self-serve
          # corrections flow, so the whole HQ persona can drive it.
          { title: "Timesheet / Corrections", path: :hq_timesheets_path, active_prefix: true,
            description: "Verify and correct the person's timesheet entries" },
          # In-shell since 2026-07-22 (was an "Asset History" link-out to
          # /person/N/assets gated on the person-page roles): checking gear in
          # and out is a window task, so the whole HQ persona can drive it.
          { title: "Asset Check In/Out", path: :hq_assets_path, active_prefix: true,
            description: "Issue radios and gear, review this year's checkouts" },
          # In-shell since 2026-07-22 (was a link-out to /person/N/training gated
          # on the person-page roles): the HQ page is read-only, so it needs no
          # gate beyond HqConcern's and the whole HQ persona can open it.
          # Managing the online course record still lives on the person page.
          { title: "Training / ARTs", path: :hq_training_path, active_prefix: true,
            description: "Review the person's training and ART status" }
        ]
      }
    ]
  }.freeze

  # Me Menu - Personal navigation menu for the /me routes
  #
  # This menu is displayed in the sidebar for all authenticated users
  # when viewing their personal dashboard and related pages.
  #
  # The same definition can be rendered by both sidebar and navbar.
  ME = {
    sections: [
      MY_CLUBHOUSE_SECTION,
      PRE_EVENT_SECTION,
      COMMUNICATION_SECTION,
      RANGER_PROFILE_SECTION,
      APPLICANT_AUDITOR_PROFILE_SECTION
    ]
  }.freeze

  # Grouped by task domain and ordered by frequency of use within each group,
  # rather than kept as one flat list, so the year-round essentials stay
  # scannable and the seasonal VC items (Tickets & Provisions, BMID) have a
  # stable, predictable spot instead of being buried among rarely-used items.
  PERSON = {
    use_person: true,
    sections: [
      {
        title: "Person Manage",
        submenu: true,
        items: [
          { title: "Overview", path: :person_path },
          { title: "Dashboard", path: :person_dashboard_path, active_prefix: true },
          { title: "Profile", path: :person_profile_path, active_prefix: true },
          { title: "Messages", path: :person_messages_path, active_prefix: true,
            visible_if: { roles: [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA] } },
          { title: "Schedule / Sign-Ups", path: :person_scheduling_path, active_prefix: true },
          { title: "Timesheets", path: :person_timesheets_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } },
          { title: "Work History", path: :person_work_history_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT] } }
        ]
      },
      {
        title: "Event",
        submenu: true,
        items: [
          { title: "Tickets & Provisions", path: :person_tickets_provisions_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::EDIT_ACCESS_DOCS] } },
          { title: "Assets", path: :person_assets_path, active_prefix: true },
          { title: "BMID", path: :person_bmid_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::EDIT_BMIDS] } },
          { title: "Pogs", path: :person_pogs_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          { title: "Swag", path: :person_swag_index_path, active_prefix: true },
          { title: "Vehicles", path: :person_vehicles_path, active_prefix: true }
        ]
      },
      {
        title: "Intake & Training",
        submenu: true,
        items: [
          { title: "Applications", path: :person_applications_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Mentoring", path: :person_mentoring_path, active_prefix: true },
          { title: "Training / ARTs", path: :person_training_path, active_prefix: true },
          { title: "Unified Flagging", path: :person_unified_flagging_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN, Role::INTAKE, Role::REGIONAL_MANAGEMENT] } }
        ]
      },
      {
        title: "Account & Admin",
        submenu: true,
        items: [
          { title: "Agreements", path: :person_agreements_path, active_prefix: true,
            description: "Agreements signed by this person, with admin corrections",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT] } },
          { title: "Awards", path: :person_awards_path, active_prefix: true },
          { title: "Certifications", path: :person_certifications_path, active_prefix: true },
          { title: "External IDs", path: :person_external_ids_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Login Sessions", path: :person_sessions_path, active_prefix: true,
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Mail Log", path: :person_mail_log_path, active_prefix: true,
            description: "Emails sent to or from this account, and email address changes",
            visible_if: { roles: [Role::ADMIN, Role::VC] } },
          { title: "Passkeys", path: :person_passkeys_path, active_prefix: true,
            description: "The passkeys that can sign in as this person",
            visible_if: { roles: [Role::ADMIN] } },
          { title: "Site Log", path: :person_site_log_path, active_prefix: true,
            description: "When this person was marked on site or off site, and by whom",
            visible_if: { roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA] } }
        ]
      }
    ]
  }.freeze

  USER = {
    title: "Account",
    description: "Sign-in and account settings",
    icon: "circle-user",
    sections: [
      {
        items: [
          { title: "My Profile", path: :me_profile_path,
            description: "Update your contact info and personal details" },
          { title: "Change Password", path: :me_profile_edit_password_path,
            description: "Set a new login password" },
          # Computed rather than always on: the pages answer 404 where passkeys
          # are off (no address set, or a single sign-on client).
          { title: "Passkeys", path: :me_profile_passkeys_path,
            description: "Sign in without your password",
            visible_if: { computed: :passkeys_enabled } },
          # A String path on purpose: a route helper cannot carry the query, and
          # ?tour=1 is what replays the first-sign-in tour without recording it
          # (Me::DashboardController). Hidden for the two statuses whose
          # dashboard has no tour: Dashboard#type's bonked and past-prospective
          # branches, which me/dashboard/index renders without it.
          { title: "Replay Onboarding", path: "/me?tour=1",
            description: "Take the tour of the Clubhouse again",
            visible_if: { not_status: [:past_prospective?, :is_any_bonked?] } }
        ]
      },
      {
        visible_if: { computed: :is_development },
        items: [
          { title: "Clear Cache", path: :clear_cache_path, data: { turbo_method: :post },
            description: "Clear the development cache" }
        ]
      },
      {
        items: [
          { title: "Logout", path: :logout_path, confirm: true,
            description: "Sign out of the Clubhouse" }
        ]
      }
    ]
  }.freeze

  # Ordered category list for the mega menu. PERSON is deliberately excluded.
  # New menu groups added here appear in the mega menu automatically.
  MEGA_CATEGORIES = [
    MY_CLUBHOUSE,
    USER,
    ADMIN,
    AGREEMENTS,
    ASSET_MANAGEMENT,
    BMID,
    CERTIFICATES,
    COMMUNICATION_MANAGEMENT,
    MENTORING,
    PEOPLE,
    POGS,
    QUARTERMASTER,
    SCHEDULING,
    SHIFT_OPERATIONS,
    TEAMS_POSITIONS,
    TICKETING,
    TIMESHEETS,
    VC,
    VEHICLES
  ].freeze
end
