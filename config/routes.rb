Rails.application.routes.draw do
  mount Rails::Hyperdrive::Engine => "/_hyperdrive" if Rails.env.development?
  # Signing in is the Clubhouse's front door, so it sits at the root instead of
  # behind a /sessions prefix.
  root to: "sessions#new"
  # A client has no password form: its accounts are signed in elsewhere.
  post "/", to: "sessions#create", constraints: ->(_request) { !Sso.client? }
  # Signing in with a passkey, offered wherever the password form is and 404
  # everywhere else (Passkeys.enabled?): the options for the device's prompt,
  # then what the device answered.
  scope constraints: ->(request) { Passkeys.enabled?(request) } do
    post "passkey/options", to: "sessions#passkey_options", as: :passkey_options
    post "passkey", to: "sessions#passkey", as: :passkey_sign_in
  end
  delete "logout", to: "sessions#logout", as: :logout
  get "forgot", to: "sessions#forgot", as: :forgot
  post "reset-password", to: "sessions#reset_password", as: :reset_password
  get "reset-token", to: "sessions#reset_token", as: :reset_token
  post "update-password", to: "sessions#update_password", as: :update_password
  if Rails.env.development?
    # A GET so the dev shortcuts are plain links.
    get "sign-in-as", to: "sessions#sign_in_as", as: :sign_in_as
    post "clear-cache", to: "sessions#clear_cache", as: :clear_cache
  end

  # Single sign-on. A Clubhouse is a server, a client, or neither (SSO), so
  # each set of pages answers 404 unless the environment names its mode. The
  # server paths are Clubhouse 2's, so the learning site and the HQ ticket
  # desk need no new settings when this Clubhouse takes over.
  get "sso/authorize", to: "sso#authorize", as: :sso_authorize
  post "sso/token", to: "sso/api#token", as: :sso_token
  get "sso/userinfo", to: "sso/api#userinfo", as: :sso_userinfo
  get ".well-known/openid-configuration", to: "sso/api#discovery", as: :sso_discovery

  get "sso/login", to: "sso#login", as: :sso_login
  get "sso/callback", to: "sso#callback", as: :sso_callback

  # Opening an auditor account. No one is signed in here, and the page walks
  # through its steps as ordinary visits so the browser's back button works.
  get "register", to: "register#show", as: :register
  post "register", to: "register#create"

  # The kiosk bookmark pages. No sign-in, no menus, one segment below the root --
  # the link lists inside these documents point back at the Clubhouse with a
  # relative "../", which only lands on the front page from here. The second
  # route is what the page's own timer asks for: a frame cannot reload itself
  # from the address it was served from.
  #
  # format: false so a dot stays part of the tag and fails the constraint,
  # rather than being read as "this document, as JSON" and asking for a page
  # that was never written.
  get "bookmark/:tag", to: "bookmarks#show", as: :bookmark,
      constraints: { tag: /[A-Za-z0-9_-]+/ }, format: false
  get "bookmark/:tag/document", to: "bookmarks#document", as: :bookmark_document,
      constraints: { tag: /[A-Za-z0-9_-]+/ }, format: false

  get "autocomplete/search", to: "autocomplete#search"

  # The Bug Report dialog in the top menu. Anyone signed in can file a report;
  # the Tech Team reads them under admin/bug-reports.
  resources :bug_reports, path: "bug-reports", only: [:new, :create]

  namespace :me do
    root to: "dashboard#index"
    # The first-sign-in tour reports that it ran (me/dashboard/_onboarding).
    patch "onboarded", to: "dashboard#onboarded", as: :onboarded

    get "menu", to: "menu#show"
    post "favorites/toggle", to: "favorites#toggle", as: :toggle_favorite

    get "awards", to: "awards#index"

    resource :alerts, only: [:edit, :update]

    get "announcements", to: "announcements#index", as: :announcements
    post "announcements/:id/toggle-read", to: "announcements#toggle_read", as: :toggle_read_announcement

    resources :agreements, path: "agreements", only: [:index, :show] do
      member do
        patch :sign
      end
    end

    get "directory", to: "directory#index"

    resources :messages, only: %w[index new create show] do
      get :find_recipient, on: :collection
      get :suggest_callsigns, on: :collection
      post :search_callsigns, on: :collection
      post :select_callsign, on: :collection
      member do
        post :toggle_archive, path: "archive"
        post :toggle_read, path: "read"
        post :create_reply, path: "reply"
        # A live reply read on the owner's open thread; /me only (ruling D6).
        post :mark_read, path: "mark-read"
      end
    end

    get "mentoring", to: "mentoring#index"

    get "online-course", to: "online_course#index"
    post "online-course", to: "online_course#create"

    get "operational-summary", to: "operational_summary#index"

    # The one document a team publishes for its members, linked from the
    # Operational Summary's Teams & Positions section. Membership is the gate.
    get "teams/:id/document", to: "team_documents#show", as: :team_document

    scope path: "surveys", as: "surveys", controller: :surveys do
      get "/", to: "surveys#show"
      post "/", to: "surveys#create"
    end

    # Personal info section routes
    get "profile", to: "profile#index", as: :profile
    patch "profile/reviewed", to: "profile#mark_reviewed", as: :mark_reviewed_profile
    get "profile/:section_id/edit", to: "profile#edit", as: :edit_profile_section
    patch "profile/:section_id", to: "profile#update", as: :profile_section

    # All nested resources under profile path
    scope path: "profile", as: "profile" do
      # Languages resource
      resources :languages, path: "languages"

      get "password", to: "password#edit", as: :edit_password
      post "password", to: "password#update", as: :password

      get "password-reset", to: "password_reset#edit"
      post "password-reset", to: "password_reset#update"

      # Signing in without a password. Offered wherever the password form is,
      # and 404 everywhere else (Passkeys.enabled?). Adding a passkey takes two
      # requests with the device's own prompt between them: options, then create.
      constraints ->(request) { Passkeys.enabled?(request) } do
        resources :passkeys, only: [:index, :new, :create, :destroy] do
          post :options, on: :collection
        end
      end

      # Photos resource with custom actions
      resources :photos, path: "photos", only: [:new, :create, :destroy] do
        member do
          get :crop
          patch :crop_save
        end
      end
    end

    scope path: "schedule/sign-ups", as: "available_sign_up" do
      get "/", to: "available_sign_ups#index"
      get "position/:position_id", to: "available_sign_ups#show", as: :position
      post "position/:position_id/slot/:slot_id", to: "available_sign_ups#create", as: :slot
      delete "position/:position_id/slot/:slot_id", to: "available_sign_ups#destroy"
    end

    scope path: "schedule", as: "schedule" do
      get "/", to: "schedule#index"
      get "export", to: "schedule#export", as: :export, constraints: { format: :ics }
      get "signup-summary", to: "schedule#signup_summary", as: :signup_summary
      get "qualifications", to: "schedule#qualifications", as: :qualifications
      get ":slot_id/signups", to: "schedule#signups", as: :signups
      delete ":slot_id", to: "schedule#destroy", as: :destroy
    end

    scope path: "tickets", as: "tickets", controller: :tickets do
      get "/", action: :index
      get "ticket", action: :ticket, as: :ticket
      get "gift", action: :gift, as: :gift
      get "vehicle-pass", action: :vehicle_pass, as: :vehicle_pass
      get "provisions", action: :provisions, as: :provisions
      get "sap", action: :sap, as: :sap
      get "sap-so", action: :sap_so, as: :sap_so
      get "review", action: :review, as: :review

      patch "documents/:id/status", action: :update_status, as: :document_status
      patch "delivery", action: :update_delivery, as: :delivery
      patch "sap-so", action: :update_sap_so
      patch "provisions", action: :update_provisions
      post "finish", action: :finish, as: :finish
    end

    scope path: "timesheet" do
      get "/", to: "timesheet#index", as: :timesheet_dashboard
      get :qualifications, to: "timesheet#qualifications", as: :timesheet_dashboard_qualifications

      get :index, path: "event-summary", to: "event_summary#index", as: :event_summary

      resources :timesheet, path: "manage", except: [:new, :create] do
        collection do
          get :final_confirmation, path: "final-confirmation"
          post :final_confirmation_acknowledgement, path: "final-confirmation"
        end

        member do
          patch :mark_verified, path: "verified"
        end
      end

      resources :missing_requests, path: "missing-request", except: [:show]

      scope path: "work-history", controller: :work_history, as: :work_history do
        get "/", to: "work_history#index"
        get :position_summary, path: "position-summary"
        get :position_all, path: "position-all"
        get :entire_year, path: "entire-year"
      end
    end

    scope path: "shift-manage", as: "shift_manage", controller: :shift_manage do
      get "/", action: :index
      post "start", action: :start_shift, as: :start
      post "end", action: :end_shift, as: :end
      post "resignin", action: :resignin, as: :resignin
      get "position", action: :correct_position, as: :position
      patch "position", action: :update_position
      delete "entry", action: :delete_mistake, as: :entry
    end

    scope path: "vehicles", as: "vehicles" do
      get "/", to: "vehicles_dashboard#index", as: :dashboard
      get "mvr-submit", to: "vehicles_dashboard#mvr_submit", as: :mvr_submit
      resources :personal_vehicles, path: "personal", only: [:new, :create, :edit, :update, :destroy]
    end
  end

  # Badge (BMID) management for a whole event year: one filtered, sortable
  # table of every badge the year needs, plus the bulk save behind Edit Mode.
  namespace :bmid do
    get "manage", to: "manage#index", as: :manage
    patch "manage", to: "manage#update", as: :manage_update

    # The Eventree export (Ember vc/bmid-print port): review the qualified
    # badges, download a CSV batch for the badge printer, and mark everything
    # in the batch as submitted.
    get "export", to: "export#index", as: :export
    post "export", to: "export#create", as: :export_create
    delete "export/:id", to: "export#unsubmit", as: :export_unsubmit

    # Read-only report of shift sign-ups that disagree with SAP/Staff
    # Credential access dates (Ember vc/bmid-sanity-check port).
    get "sanity-check", to: "sanity_check#index", as: :sanity_check

    # The titles a position earns on a badge. Set BMID Titles (the set/apply
    # pair, one URL and two verbs) previews what every qualified holder's badge
    # would say and then writes it.
    resources :titles, except: :show do
      # Reordering is a nudge, not an edit form: the list itself is the only
      # place a preference means anything, so it is changed from there.
      member { patch :move }

      collection do
        get :set
        post :apply, path: "set"
      end
    end

    # The provision modals the manage grid opens from its meals and showers
    # cells. They sit under the page they belong to, and every one of them
    # carries the row owner as person_id: a provision is only ever reachable
    # here through the person who holds it.
    #
    # index is the dialog's first step -- the person's usable provisions of the
    # cell's type, since a person may hold more than one of a type and the cell
    # describes all of them at once.
    scope path: "manage" do
      resources :provisions, only: %i[index new create edit update destroy]

      # The single-badge editor the roster's Edit column opens. Keyed by person
      # rather than by badge id: a badge may not exist until its first save, so
      # person + year is the only identity every row on the roster has.
      #
      # It lives here rather than linking out to /person/:id/bmid because that
      # page belongs to a person, not to an event year -- it loads and saves
      # Current.year whatever row was clicked -- and because a save has to
      # return to the roster the admin was reading, not to the person.
      resources :badges, only: %i[edit update], param: :person_id
    end
  end

  namespace :infrastructure do
    post "sms/inbound", to: "sms#inbound"
    # Where Twilio reports what became of each text the Clubhouse sent, the
    # text's row id in the query (SmsService.text_through).
    post "sms/status", to: "sms#receipt"

    # Where SES reports what became of the mail the Clubhouse sent, by way of
    # an SNS topic. Open to the internet; SnsMessage checks the signature.
    post "aws-sns", to: "aws_sns#notification"
  end

  # The announcements shown on everyone's Clubhouse home page. The reading side
  # lives at /me/announcements; this is where they are written.
  namespace :communication do
    resources :announcements, except: [:show] do
      # Clearing out what has already expired is a housekeeping sweep over the
      # whole list, not an edit of any one announcement.
      collection do
        post :delete_expired, path: "delete-expired"
      end
    end

    # Every account banner in one list. Banners are written and removed on each
    # person's own Banners page, so this one only reads.
    resources :person_banners, only: [:index], path: "person-banners"

    # The wording of the messages the Clubhouse sends. Only editing: each
    # template belongs to a message the Clubhouse already knows how to send.
    resources :mail_templates, only: [:index, :edit, :update], path: "mail-templates"

    # The feedback surveys shown on the Clubhouse dashboard: who answers each
    # one, what it asks, and in what order. Reading the answers lives under the
    # training interface and the Mentors' Alpha Surveys.
    resources :surveys, path: "survey-management" do
      member do
        post :duplicate
      end

      # Groups and questions belong to one survey, and every write is gated by
      # that survey, so they hang off it rather than standing on their own.
      resources :groups, controller: "survey_groups", except: [:index, :show] do
        member do
          patch :move
        end
      end

      resources :questions, controller: "survey_questions", except: [:index, :show] do
        member do
          patch :move
        end
      end
    end

    # The Ranger Broadcast System: one message sent to a group of Rangers by
    # text, email, and Clubhouse message, and the record of what went out.
    scope path: "rbs", as: :rbs do
      get "/", to: "rbs#index", as: :root

      # One page per kind of broadcast. Review and send post the same values:
      # the review writes nothing, and both render their results from the POST,
      # which a GET could not re-derive. "Edit message" posts back to the form
      # for the same reason -- a GET would have to carry the message in the URL.
      get "broadcasts/:type", to: "rbs_broadcasts#new", as: :new_broadcast
      post "broadcasts/:type/edit", to: "rbs_broadcasts#new", as: :edit_broadcast
      post "broadcasts/:type/review", to: "rbs_broadcasts#review", as: :review_broadcast
      post "broadcasts/:type", to: "rbs_broadcasts#create", as: :broadcasts

      get "history", to: "rbs_history#index", as: :history
      get "history/:id", to: "rbs_history#show", as: :history_broadcast
      post "history/:id/retry", to: "rbs_history#retry", as: :retry_history_broadcast

      get "messages", to: "rbs_messages#index", as: :messages
      get "phone-numbers", to: "rbs_phone_numbers#index", as: :phone_numbers
    end
  end

  # Signed agreements, recorded for many people at once (the Affidavits group of
  # upstream's admin/bulk-upload). The per-person view of the same records lives
  # on the person's own Agreements page.
  #
  # Every bulk page in the application declares the same four routes, in the
  # shape bulk-positions and bulk-teams already use: the form, a preview that
  # writes nothing, the apply, and a POST back to the form. The "edit" POST
  # writes nothing either -- it re-renders the form with the pasted list intact,
  # which a GET could only manage by putting every callsign in the URL.
  namespace :agreements do
    scope path: "bulk-signature", controller: :bulk_signature do
      get "/", action: :index, as: :bulk_signature
      post "edit", action: :index, as: :edit_bulk_signature
      post "preview", action: :preview, as: :preview_bulk_signature
      post "/", action: :apply, as: :apply_bulk_signature
    end
  end

  # Person status and flags, changed for a list of callsigns at once (the Change
  # Status group of upstream's admin/bulk-upload). The singular `person` routes
  # are the per-person pages; this namespace is the many-at-once side.
  namespace :people do
    # A new Clubhouse account, entered by hand. Both verbs share the one path:
    # the form posts back to where it was shown, so a rejected save can render
    # the same page again with the values still filled in.
    scope path: "create-account", controller: :create_account do
      get "/", action: :new, as: :create_account
      post "/", action: :create
    end

    scope path: "bulk-status", controller: :bulk_status do
      get "/", action: :index, as: :bulk_status
      post "edit", action: :index, as: :edit_bulk_status
      post "preview", action: :preview, as: :preview_bulk_status
      post "/", action: :apply, as: :apply_bulk_status
    end

    # Every account, grouped by the status it holds right now. The index counts each
    # status; a status opens onto its own page of callsigns.
    #
    # The status arrives as a slug rather than the stored value, which for two of them
    # carries a space. Not year-scoped: a status is what someone holds today, and the
    # table keeps no history of it.
    scope path: "people-by-status", controller: :people_by_status do
      get "/", action: :index, as: :by_status
      get ":status", action: :show, as: :by_status_detail
    end

    # The status changes to consider once an event is over. The index carries
    # only counts; a group's people live on its own page, so no request ever
    # loads all five lists.
    #
    # The group segment keeps the default pattern, which stops at a dot, so the
    # .csv on the end of an export is read as the format. An unknown group is
    # refused by the controller rather than by a constraint, which keeps the
    # list of groups in the one place that already owns it.
    scope path: "status-change-recommendations", controller: :status_change_recommendations do
      get "/", action: :index, as: :status_change_recommendations
      get ":group", action: :show, as: :status_change_recommendations_group
      # format: false on the write, unlike the read above. The convert renders
      # its own results page and has no other format; without this, a .csv on
      # the end would make the whole change and then fail to render the one
      # record of what it did.
      post ":group", action: :convert, as: :status_change_recommendations_convert, format: false
    end

    # Person records looked up for a list of callsigns or email addresses at
    # once. Read only. The results render from the POST because the pasted
    # list rides in the request body, not the URL; the CSV exports post the
    # same list back with a format of csv.
    scope path: "bulk-lookup", controller: :bulk_lookup do
      get "/", action: :index, as: :bulk_lookup
      post "/", action: :lookup, as: :run_bulk_lookup
    end

    # Advanced search across every account: status (current or as of a status
    # change year), years rangered, photo, and this year's training/ticketing
    # progress. The criteria ride in the query string, so the CSV export is
    # the same address with a format of csv.
    scope path: "search", controller: :search do
      get "/", action: :index, as: :search
    end

    # Where everyone lives. The countries index drills into one country, which
    # is either a list of its states or its people.
    #
    # The country segment keeps the default pattern, which stops at a dot so
    # that the .csv on the end of an export is read as the format. The state is
    # a query parameter rather than a second segment, since it can be blank.
    scope path: "people-by-location", controller: :people_by_location do
      get "/", action: :index, as: :by_location
      get "country/:country", action: :country, as: :by_location_country
    end

    # Who speaks what, for everyone on site. The index drills into one
    # language's speakers.
    #
    # The language takes the whole rest of the path. People type their own
    # language names, and real ones carry both dots and slashes -- "Indonesian/
    # Malay" is on file today. A plain segment would cut those names short, and
    # the index cannot even build a link to one. The page reads HTML only, so
    # nothing needs the dot for a format.
    scope path: "languages-known", controller: :languages_known do
      get "/", action: :index, as: :languages_known
      get "*language", action: :show, as: :languages_known_detail, format: false
    end

    # Who rangered any of the last five events, for the post-event survey. One
    # page: the filters ride the query string, and the export is the same
    # action asked for a .csv, so a file always matches what is on screen.
    scope path: "retention-report", controller: :retention_report do
      get "/", action: :index, as: :retention_report
    end

    # Everyone the intake teams touched in a year, for an Admin. Year-scoped;
    # the export is the same GET asked for a .csv, filtered like the page. The
    # review pane loads through the index itself, so no #detail route.
    scope path: "unified-flagging", controller: :unified_flagging do
      get "/", action: :index, as: :unified_flagging
    end
  end

  # Certification records, entered for a list of callsigns at once (the
  # Certification Actions group of upstream's admin/bulk-upload). The per-person
  # records live under the person scope.
  namespace :certificates do
    scope path: "bulk-record", controller: :bulk_record do
      get "/", action: :index, as: :bulk_record
      post "edit", action: :index, as: :edit_bulk_record
      post "preview", action: :preview, as: :preview_bulk_record
      post "/", action: :apply, as: :apply_bulk_record
    end

    # Who holds each certification. The index drills into one certification's
    # roster.
    #
    # Digits only. `find` casts "7-anything" to 7, so without this one page
    # answers to endlessly many URLs, each of which it then repeats back in its
    # own links. The dot that separates the .csv format is handled by the
    # default segment pattern either way.
    scope path: "certificates-report", controller: :certificates_report do
      get "/", action: :index, as: :report
      get ":id", action: :show, as: :report_detail, constraints: { id: /\d+/ }
    end
  end

  # Asset inventory administration (radios, vehicles, gear). Kept off /assets,
  # which Propshaft owns -- its middleware 404s an unknown path under that
  # prefix instead of falling through to the router.
  namespace :asset_management, path: "asset-management" do
    # Types index drills down into a per-type records page, mirroring scheduling
    # slots. Declared before the resource so it is not read as records#show.
    get "records/type/:type", to: "records#type", as: :records_type
    resources :records
    # Barcode lookup for one asset. A GET so the barcode and year ride the query
    # string: a result can be linked, and the Back button re-runs the lookup
    # instead of landing on an empty form.
    scope path: "search", controller: :search do
      get "/", action: :index, as: :search
      patch ":asset_id/check-in", action: :check_in, as: :search_check_in
    end
    get "assets-outstanding", to: "assets_outstanding#index", as: :assets_outstanding
    get "asset-history", to: "asset_history#index", as: :asset_history
    get "radio-assets", to: "radio_assets#index", as: :radio_assets
    get "radio-checkout", to: "radio_checkout#index", as: :radio_checkout
  end

  # Vehicle fleet & personal-vehicle administration (Ember ops/vehicle-registry
  # port). Permit entry gets its own compact page rather than a modal.
  namespace :vehicles do
    # Read-only paperwork audit (Ember reports/vehicle-paperwork port).
    get "paperwork", to: "paperwork#index"

    # The Vehicle Paperwork Flags group of upstream's admin/bulk-upload: the
    # write side of the audit above.
    scope path: "bulk-paperwork", controller: :bulk_paperwork do
      get "/", action: :index, as: :bulk_paperwork
      post "edit", action: :index, as: :edit_bulk_paperwork
      post "preview", action: :preview, as: :preview_bulk_paperwork
      post "/", action: :apply, as: :apply_bulk_paperwork
    end

    resources :registry, only: %i[index new create edit update destroy],
              controller: :registry do
      member do
        get :permit
        patch :permit, action: :update_permit, as: nil
      end
    end
  end

  namespace :timesheets do
    # Who is on duty (Ember reports/on-duty port). Not year-scoped: the year is
    # implied by the duty date, and with none given the answer is "right now".
    get "on-duty", to: "on_duty#index", as: :on_duty

    # Which shift starts were forced past a sign-in blocker (Ember
    # reports/forced-signins port).
    get "forced-shift-start", to: "forced_shift_start#index", as: :forced_shift_start

    # Check-ins that landed outside the window around their scheduled shift
    # start (Ember reports/early-late-checkins port).
    get "early-late-checkins", to: "early_late_checkins#index", as: :early_late_checkins

    # Correction and missing-entry requests still waiting on a decision (Ember
    # reports/timesheet-correction-requests port).
    get "correction-requests", to: "correction_requests#index", as: :correction_requests

    # The same two request types once they have been decided, counted rather
    # than listed (Ember reports/timesheet-correction-stats port).
    get "correction-stats", to: "correction_stats#index", as: :correction_stats

    # Rangers who logged hours but never confirmed their timesheet is correct
    # (Ember reports/timesheet-unconfirmed port).
    get "timesheet-unconfirmed", to: "timesheet_unconfirmed#index", as: :timesheet_unconfirmed

    # Every timesheet of a year grouped by the person who turned it in (Ember
    # reports/timesheet-by-callsign port). Roster index drilling down into one
    # person; both levels answer CSV.
    get "timesheets-by-callsign", to: "timesheets_by_callsign#index",
        as: :timesheets_by_callsign
    get "timesheets-by-callsign/person/:person_id", to: "timesheets_by_callsign#person",
        as: :timesheets_by_callsign_person

    # The same year grouped by position instead (Ember reports/timesheet-by-position
    # port). Index of positions drilling down into one position; both levels
    # answer CSV.
    get "timesheet-by-position", to: "timesheet_by_position#index",
        as: :timesheet_by_position
    get "timesheet-by-position/position/:position_id", to: "timesheet_by_position#position",
        as: :timesheet_by_position_position

    # One year of hours and credits per person, counting only the positions
    # that count hours. Roster index drilling down into one person; only the
    # index answers CSV.
    get "timesheet-totals-report", to: "timesheet_totals_report#index",
        as: :timesheet_totals_report
    get "timesheet-totals-report/person/:person_id", to: "timesheet_totals_report#person",
        as: :timesheet_totals_report_person

    # Who put in the most hours in one year of a span. Not year-scoped: the
    # span is the report's subject and both ends ride in the query string.
    get "top-hour-earners", to: "top_hour_earners#index", as: :top_hour_earners

    # One year of hours and credits per ranger, split into the parts of the
    # season. One page, and it answers CSV.
    get "hours-credits", to: "hours_credits#index", as: :hours_credits

    # Timesheet entries that look wrong -- eight named checks over one year
    # (Ember reports/timesheet-sanity-checker port). The index is a triage
    # board; each check drills into its own page and exports itself.
    #
    # :check is left unconstrained rather than pinned to the report's key list:
    # naming an autoloaded constant here ties the routes to a reloadable class,
    # and the controller already turns an unknown key back to the index with a
    # reason -- which is the better answer for a stale bookmark than a 404.
    get "sanity-checker", to: "sanity_checker#index", as: :sanity_checker
    get "sanity-checker/:check", to: "sanity_checker#check", as: :sanity_checker_check

    # Timesheet entries linked to the wrong scheduled shift, or to none (Ember
    # admin/timesheet-slot-repair port). The page previews every change it
    # would make; the POST writes the ones that were picked and reports back.
    get "timesheet-slot-repair", to: "timesheet_slot_repair#index",
        as: :timesheet_slot_repair
    post "timesheet-slot-repair/apply", to: "timesheet_slot_repair#apply",
         as: :apply_timesheet_slot_repair
  end

  # Team, cadre, and delegation administration (Ember admin/teams port). The
  # Ember edit modal became new/edit pages, per house convention.
  namespace :teams_positions, path: "teams-positions" do
    scope path: "team-records", controller: :team_records do
      get "/", action: :index, as: :team_records
      get "new", action: :new, as: :new_team_record
      post "/", action: :create, as: :create_team_record
      get ":id/edit", action: :edit, as: :edit_team_record
      patch ":id", action: :update, as: :team_record
      delete ":id", action: :destroy
    end

    # Position lineups (Ember admin/positions' second tab). A sibling path
    # rather than a child of position-records: nested, every lineup URL would
    # also match the position-records prefix, lighting up both menu items at
    # once and shadowing that scope's ":id/edit".
    scope path: "position-lineups", controller: :position_lineups do
      get "/", action: :index, as: :position_lineups
      get "new", action: :new, as: :new_position_lineup
      post "/", action: :create, as: :create_position_lineup
      get ":id/edit", action: :edit, as: :edit_position_lineup
      patch ":id", action: :update, as: :position_lineup
      delete ":id", action: :destroy
    end

    # Position administration (Ember admin/positions port). Its lineup tab
    # became the sibling page above, per house convention.
    scope path: "position-records", controller: :position_records do
      get "/", action: :index, as: :position_records
      get "new", action: :new, as: :new_position_record
      post "/", action: :create, as: :create_position_record
      get ":id/edit", action: :edit, as: :edit_position_record
      patch ":id", action: :update, as: :position_record
      delete ":id", action: :destroy
    end

    # Read-only membership report (Ember ops/people-by-clubhouse-teams port).
    # The index carries only counts; a team's roster lives on its own page, so
    # the 2,491 memberships are never all loaded at once.
    scope path: "membership-report", controller: :membership_report do
      get "/", action: :index, as: :membership_report
      get ":team_id", action: :show, as: :membership_report_team
    end

    # Read-only position grant report (Ember reports/people-by-position port).
    # Same shape as the membership report above, and for the same reason: the
    # index carries only counts, so its 46,000 grants are never all loaded.
    scope path: "position-grants", controller: :position_grants do
      get "/", action: :index, as: :position_grants
      get ":position_id", action: :show, as: :position_grants_position
    end

    # Hours and sign-ups per year for the positions a reader picks (Ember
    # reports/special-teams port). The whole request rides the query string, so
    # a report can be bookmarked and its CSV is the page's own address with a
    # format on the end.
    get "special-teams-hours", to: "special_teams_hours#index", as: :special_teams_hours

    # Team roster management (Ember ops/teams port). A team manager reaches the
    # rosters of the teams they manage, and nothing else.
    scope path: "roster-management", controller: :roster_management do
      get "/", action: :index, as: :roster_management
      get ":team_id", action: :show, as: :roster_management_team
      # Every bulk action goes through a preview: the POST from the grid shows
      # what would change and nothing is written until it is confirmed.
      post ":team_id/preview", action: :preview, as: :roster_management_preview
      post ":team_id/apply", action: :apply, as: :roster_management_apply
    end

    # The one document a team publishes for its members (Ember
    # ops/team-resources port). Upstream went straight from the team list into
    # the editor; here a team gets a read page between them, as Trainer
    # Resources does, whose concern and editor these routes reuse.
    scope path: "team-resources", controller: :team_resources do
      get "/", action: :index, as: :team_resources
      get ":team_id", action: :show, as: :team_resource
      get ":team_id/edit", action: :edit, as: :edit_team_resource
      post ":team_id", action: :create
      patch ":team_id", action: :update
      delete ":team_id", action: :destroy
    end

    # Bulk grant/revoke of one position across a pasted callsign list (Ember
    # ops/bulk-positions port). Open to the same people as Roster Management:
    # a team manager reaches their teams' positions, and nothing else.
    scope path: "bulk-positions", controller: :bulk_positions do
      get "/", action: :index, as: :bulk_positions
      # A POST that writes nothing -- it re-renders the form with the pasted
      # list intact, which a GET could only manage by putting every callsign in
      # the URL. Reached from the preview's "Go back and edit".
      post "edit", action: :index, as: :edit_bulk_positions
      post "preview", action: :preview, as: :preview_bulk_positions
      post "/", action: :apply, as: :apply_bulk_positions
    end

    # Bulk grant/revoke of one team membership across a pasted callsign list
    # (Ember ops/bulk-teams port). Same four steps and the same gate as
    # bulk-positions above; the membership carries the team's positions with it.
    scope path: "bulk-teams", controller: :bulk_teams do
      get "/", action: :index, as: :bulk_teams
      post "edit", action: :index, as: :edit_bulk_teams
      post "preview", action: :preview, as: :preview_bulk_teams
      post "/", action: :apply, as: :apply_bulk_teams
    end

    # The Team Membership group of upstream's admin/bulk-upload. Records history
    # only -- who was on a team and when -- and never touches current
    # membership, which the two pages above own.
    scope path: "bulk-membership-history", controller: :bulk_membership_history do
      get "/", action: :index, as: :bulk_membership_history
      post "edit", action: :index, as: :edit_bulk_membership_history
      post "preview", action: :preview, as: :preview_bulk_membership_history
      post "/", action: :apply, as: :apply_bulk_membership_history
    end

    # Grants that contradict each other, and the repairs that settle them
    # (Ember admin/position-sanity-checker port). The index is a triage board;
    # each check drills into its own page and repairs from there.
    #
    # :check is left unconstrained rather than pinned to the registry's key
    # list: naming an autoloaded constant here ties the routes to a reloadable
    # module, and the controller already turns an unknown key back to the index
    # with a reason -- the better answer for a stale bookmark than a 404.
    scope path: "position-sanity-checker", controller: :position_sanity_checker do
      get "/", action: :index, as: :position_sanity_checker
      get ":check", action: :check, as: :position_sanity_checker_check
      post ":check/repair", action: :repair, as: :position_sanity_checker_repair
    end
  end

  # Meal and shower pog statistics and record administration, both gated on
  # Admin or Pog Management.
  namespace :pogs do
    get "dashboard", to: "dashboard#index"
    scope path: "administration", controller: :administration do
      get "/", action: :index, as: :administration
      get ":id/edit", action: :edit, as: :edit_record
      patch ":id", action: :update, as: :record
      delete ":id", action: :destroy, as: nil
    end
  end

  # Swag catalog administration (Ember ops/swag port). The Ember tabs became an
  # index of swag types, each drilling down into its own page.
  namespace :quartermaster do
    scope path: "swag", controller: :swag do
      get "/", action: :index, as: :swag
      get "type/:type", action: :type, as: :swag_type
      get "new", action: :new, as: :new_swag
      post "/", action: :create, as: :create_swag
      get ":id/edit", action: :edit, as: :edit_swag
      patch ":id", action: :update, as: :swag_item
      delete ":id", action: :destroy
    end

    # Shirt sizes for the current Prospectives and Alphas (Ember
    # reports/alpha-shirts port). Not year-scoped -- see the controller.
    get "alpha-shirts", to: "alpha_shirts#index", as: :alpha_shirts
    get "alpha-shirts/counts", to: "alpha_shirts#counts", as: :alpha_shirts_counts

    # Who may earn a shirt for a given event year (Ember
    # reports/potential-shirts port). Year-scoped -- see the controller.
    get "potential-shirts", to: "potential_shirts#index", as: :potential_shirts
    get "potential-shirts/counts", to: "potential_shirts#counts", as: :potential_shirts_counts

    # Years of service for everyone who has rangered (Ember
    # reports/events-rangered port). Not year-scoped -- see the controller.
    get "events-rangered", to: "events_rangered#index", as: :events_rangered

    # Total service years for every Active Ranger, grouped by how many (Ember
    # reports/freaking-years port). The index drills down into a per-group
    # roster. Not year-scoped -- see the controller.
    get "freaking-years", to: "freaking_years#index", as: :freaking_years
    get "freaking-years/:years", to: "freaking_years#show", as: :freaking_years_group,
        constraints: { years: /\d+/ }

    # Service pin and patch candidates for the coming event (Ember
    # reports/potential-swag port). Not year-scoped -- see the controller.
    get "potential-swag", to: "potential_swag#index", as: :potential_swag

    # What swag was handed out during an event (Ember reports/swag-distribution
    # port). Year-scoped, with an all-years option -- see the controller.
    get "swag-distribution", to: "swag_distribution#index", as: :swag_distribution
  end

  # Slot (shift) management (Ember ops/slots port). Positions index drills down
  # into a per-position slots page; copy and bulk-edit are their own controllers.
  namespace :scheduling do
    scope path: "slots", controller: :slots do
      get "/", action: :index, as: :slots
      get "new", action: :new, as: :new_slot
      post "/", action: :create, as: :create_slot
      get "link-options", action: :link_options, as: :slots_link_options
      get "position/:position_id", action: :position, as: :slots_position
      post "position/:position_id/active", action: :set_active_all, as: :slots_position_active
      delete "position/:position_id/bulk-delete", action: :bulk_destroy, as: :slots_position_bulk_delete
      get ":id/edit", action: :edit, as: :edit_slot
      patch ":id", action: :update, as: :slot
      delete ":id", action: :destroy
      post ":id/repeat", action: :repeat, as: :repeat_slot
    end

    scope path: "slots/copy", controller: :slot_copies do
      get "/", action: :new, as: :new_slot_copy
      post "/", action: :create, as: :slot_copies
    end

    scope path: "slots/position/:position_id/bulk-edit", controller: :slot_bulk_edits do
      get "/", action: :new, as: :new_slot_bulk_edit
      post "/", action: :create, as: :slot_bulk_edits
    end

    scope path: "position-credits", controller: :position_credits do
      get "/", action: :index, as: :position_credits
      get "new", action: :new, as: :new_position_credit
      post "/", action: :create, as: :create_position_credit
      get "position/:position_id", action: :position, as: :position_credits_position
      get "position/:position_id/timeline", action: :timeline, as: :position_credits_position_timeline
      delete "position/:position_id/bulk-delete", action: :bulk_destroy, as: :position_credits_position_bulk_delete
      get ":id/edit", action: :edit, as: :edit_position_credit
      patch ":id", action: :update, as: :position_credit
      delete ":id", action: :destroy
    end

    scope path: "position-credits/copy", controller: :position_credit_copies do
      get "/", action: :new, as: :new_position_credit_copy
      post "/", action: :create, as: :position_credit_copies
    end

    # Flake report: who signed up but never rangered the shift, and who
    # rangered a shift they never signed up for. The positions index drills
    # down into one position's shifts, as the slots pages do.
    get "flake-report", to: "flake_report#index", as: :flake_report
    get "flake-report/position/:position_id", to: "flake_report#position",
        as: :flake_report_position

    # Shift drop report: who dropped a shift close to its start. Same two-level
    # shape as the flake report above it.
    get "shift-drop", to: "shift_drop_report#index", as: :shift_drop_report
    get "shift-drop/position/:position_id", to: "shift_drop_report#position",
        as: :shift_drop_report_position

    # No shows report: who signed up and was never on duty for the shift. Same
    # two-level shape again; the position page also answers CSV.
    get "no-shows-report", to: "no_shows_report#index", as: :no_shows_report
    get "no-shows-report/position/:position_id", to: "no_shows_report#position",
        as: :no_shows_report_position

    # Khaki's staffing picture for one shift period (Ember reports/shift-lead).
    # One GET: both flavours of the report -- the sign-ups for a picked shift and
    # whoever is on duty right now -- are reads of the same page, told apart by
    # the query string.
    #
    # Year-scoped, because a shift belongs to a year. The live flavour ignores
    # the year, there being only one "now".
    get "shift-lead", to: "shift_lead#index", as: :shift_lead
    # The same report as a paper document. `print_sheet`, not `print` -- a
    # `print` action would shadow Kernel#print. Named explicitly, like every
    # route in here: an unnamed route inside a namespace steals the namespace's
    # own route name.
    get "shift-lead/print", to: "shift_lead#print_sheet", as: :shift_lead_print

    # Every sign-up of a year grouped by person (Ember reports/schedule-by-callsign
    # port). Roster index drilling down into one person; both levels answer CSV.
    # Named explicitly for the reason spelled above.
    get "schedule-by-callsign", to: "schedule_by_callsign#index",
        as: :schedule_by_callsign
    get "schedule-by-callsign/person/:person_id", to: "schedule_by_callsign#person",
        as: :schedule_by_callsign_person

    # The same year's sign-ups read the other way round: every shift grouped by
    # the position it belongs to (Ember reports/schedule-by-position port). The
    # position page answers CSV, as upstream's export button does.
    get "schedule-by-position", to: "schedule_by_position#index",
        as: :schedule_by_position
    get "schedule-by-position/position/:position_id", to: "schedule_by_position#position",
        as: :schedule_by_position_position

    # Who is scheduled at each post, period by period, for one kind of shift.
    # One page rather than two: the shift type is a choice on the page, not a
    # place to drill into. Answers CSV. Named explicitly, like every route in
    # here, for the reason spelled above the shift lead routes.
    get "shift-coverage", to: "shift_coverage#index", as: :shift_coverage

    # How busy the HQ window is expected to be, period by period. Two pages
    # rather than two tabs: the burn forecast is a different question asked of
    # the same year, and each page reads only what it prints. The people route
    # fills the dialog a staffing count opens. Named explicitly, like every
    # route in here, for the reason spelled above the shift lead routes.
    get "hq-forecast", to: "hq_forecast#index", as: :hq_forecast
    get "hq-forecast/burn-perimeters", to: "hq_forecast#burn_perimeters",
        as: :hq_forecast_burn_perimeters
    get "hq-forecast/people", to: "hq_forecast#people", as: :hq_forecast_people
    get "hq-forecast/shifts/:slot_id", to: "hq_forecast#shift", as: :hq_forecast_shift

    # Who may stand a Sandman shift this year. One page: the report is a single
    # roster with nothing underneath to drill into. Answers CSV. Named
    # explicitly, like every route in here, for the reason spelled above the
    # shift lead routes.
    get "sandman-qualified", to: "sandman_qualified#index", as: :sandman_qualified

    # Who turns up before gate opening weekend, so their arrival packets can be
    # put together. One page: a single roster with nothing underneath to drill
    # into. Answers CSV. Named explicitly, like every route in here, for the
    # reason spelled above the shift lead routes.
    get "early-arrivals", to: "early_arrivals#index", as: :early_arrivals

    # How full every active shift of the year is, grouped by position. Same
    # two-level shape as the schedule report above it; both levels answer CSV.
    get "shift-signups", to: "shift_signups#index", as: :shift_signups
    get "shift-signups/position/:position_id", to: "shift_signups#position",
        as: :shift_signups_position

    # How the whole event turned out, rather than any one shift: turnout against
    # sign-ups, the Alpha cohort, and training completion. Named explicitly,
    # like every route in here, for the reason spelled above the shift lead
    # routes.
    get "event-stats", to: "event_stats#index", as: :event_stats
  end

  # Whole-board shift operations -- actions taken across everyone on duty at
  # once, rather than one Ranger at a time in the HQ window.
  #
  # path: is required; without it Rails would serve these at /shift_operations.
  namespace :shift_operations, path: "shift-operations" do
    # Everyone still on duty, signed out in one sweep (Ember admin/bulk-signout
    # port). Not year-scoped: an entry is open or it is not, and the entries
    # most worth finding are the ones whose year is wrong.
    get "mass-signout", to: "mass_signout#index", as: :mass_signout
    post "mass-signout", to: "mass_signout#create", as: nil

    # A pasted list of callsigns signed in and/or out at once (Ember
    # ops/bulk-sign-in-out). The same four routes every bulk page declares --
    # see the comment above the agreements namespace for why the "edit" POST
    # exists. Not year-scoped: a line may name any date, and a line that names
    # none lands in the current year.
    scope path: "bulk-sign-in-out", controller: :bulk_sign_in_out do
      get "/", action: :index, as: :bulk_sign_in_out
      post "edit", action: :index, as: :edit_bulk_sign_in_out
      post "preview", action: :preview, as: :preview_bulk_sign_in_out
      post "/", action: :apply, as: :apply_bulk_sign_in_out
    end

    # Tap-a-name rollcall for burn-night crews (Ember ops/rollcall). Two
    # rosters behind a mode chooser, and three POSTs that each answer with a
    # turbo stream replacing the one row that changed -- never a page reload,
    # because the operator is holding a phone in the dark partway down a list
    # of a hundred and fifty names.
    #
    # Not year-scoped: the shift window and the on-duty set are both "now"
    # questions.
    scope path: "rollcall", controller: :rollcall do
      get "/", action: :index, as: :rollcall
      get "sign-in", action: :sign_in, as: :rollcall_sign_in
      get "sign-out", action: :sign_out, as: :rollcall_sign_out
      post "check-in", action: :check_in, as: :rollcall_check_in
      post "check-out", action: :check_out, as: :rollcall_check_out
      post "resume", action: :resume, as: :rollcall_resume
    end

    # The ROC wall display, left running on a monitor in HQ. Named
    # explicitly like its siblings -- an unnamed route inside a namespace takes
    # the namespace's own route name. Not year-scoped: it answers who is on
    # duty at this moment and nothing else.
    get "roc-photo-board", to: "roc_photo_board#index",
        as: :roc_photo_board
    # The board on its own, which is what the display asks for when its timer
    # comes round. It cannot re-request the whole page: a frame whose source is
    # the page holding it is a loop, and Turbo empties it rather than follow one.
    get "roc-photo-board/board", to: "roc_photo_board#board",
        as: :roc_photo_board_board

    # Timesheet entries for a pay period, and the punch files payroll loads.
    # Named explicitly like its siblings. Not year-scoped: a pay window is a
    # pair of dates, and one can straddle the turn of a year.
    #
    # The same route serves the page and every download; ?variant= picks which
    # file, so an export link is the page's own query with a format on the end.
    get "payroll-export", to: "payroll_export#index", as: :payroll_export

    # Everyone signed up for a paid shift in the year with no Paycom Employee ID
    # to be paid against, or the 0 that clears them to take it unpaid.
    # Year-scoped: a sign-up belongs to a slot, and slots belong to a year.
    get "payroll-missing-id", to: "payroll_missing_id#index", as: :payroll_missing_id

    # The pods deployed on a dirt shift (Ember ops/cruise-direction).
    # Year-scoped, because a pod belongs to a shift and shifts belong to a
    # year -- the page reads back which pods walked a past event, not only
    # which are out right now.
    #
    # The shift is a query parameter rather than a path segment: the picker is
    # an auto-submitting GET form and every write answers by replacing the
    # board, so the shift never has to be spelled twice.
    scope path: "cruise-direction" do
      get "/", to: "cruise_direction#index", as: :cruise_direction

      scope module: :cruise_direction do
        post "pods", to: "pods#create", as: :cruise_direction_pods
        get "pods/new", to: "pods#new", as: :new_cruise_direction_pod
        get "pods/:id/edit", to: "pods#edit", as: :edit_cruise_direction_pod
        patch "pods/:id", to: "pods#update", as: :cruise_direction_pod
        # as: nil, or the unnamed route helps itself to the namespace's own
        # name and `shift_operations_path` becomes this DELETE.
        delete "pods/:id", to: "pods#destroy", as: nil
        # Where a dragged card was let go. Separate from the update above so a
        # drag cannot carry a transport or a location with it.
        patch "pods/:id/position", to: "pods#position", as: :cruise_direction_pod_position

        get "pods/:pod_id/people/new", to: "people#new", as: :new_cruise_direction_person
        post "pods/:pod_id/people", to: "people#create", as: :cruise_direction_people
        get "pods/:pod_id/people/:person_id/edit", to: "people#edit", as: :edit_cruise_direction_person
        patch "pods/:pod_id/people/:person_id", to: "people#update", as: :cruise_direction_person
        delete "pods/:pod_id/people/:person_id", to: "people#destroy", as: nil
      end
    end
  end

  # Ticketing administration (Ember vc/access-documents port). The Ember tabs
  # became two pages: a per-person summary and a flat record list.
  namespace :ticketing do
    get "access-documents", to: "access_documents#index", as: :access_documents
    get "access-documents/records", to: "access_documents#records", as: :access_documents_records
    get "unclaimed-with-signups", to: "unclaimed_with_signups#index", as: :unclaimed_with_signups
    get "expiring", to: "expiring#index", as: :expiring
    get "sap-candidates", to: "sap_candidates#index", as: :sap_candidates
    get "claimed-with-no-signups", to: "claimed_with_no_signups#index", as: :claimed_with_no_signups
    get "statistics", to: "statistics#index", as: :statistics
    # Creating a provision needs a person picked first, so :new and :create stay
    # on the person pages.
    resources :provisions, only: [:index, :edit, :update, :destroy]
    # Seasonal maintenance tasks: one GET preview + POST commit pair dispatched
    # on the task slug (see TicketingMaintenance::GROUPS).
    get "maintenance", to: "maintenance#index", as: :maintenance
    get "maintenance/:task", to: "maintenance#preview", as: :maintenance_preview
    post "maintenance/:task", to: "maintenance#commit", as: :maintenance_commit
    get "unsubmit-provisions", to: "unsubmit_provisions#index", as: :unsubmit_provisions
    post "unsubmit-provisions", to: "unsubmit_provisions#commit", as: :unsubmit_provisions_commit
    # TRS export runs in two POST steps: export stamps audit comments and hands
    # back the vendor CSV, mark-submitted flips the batch once TRS accepts it.
    get "trs-export", to: "trs_export#index", as: :trs_export
    post "trs-export/export", to: "trs_export#export", as: :trs_export_export
    post "trs-export/mark-submitted", to: "trs_export#mark_submitted", as: :trs_export_mark_submitted

    # The three ticketing groups of upstream's admin/bulk-upload. Bulk BMID sits
    # here by URL but is reached from the BMID menu, whose gate already matches
    # its own: Edit BMIDs, which is not a ticketing role.
    scope path: "bulk-provisions", controller: :bulk_provisions do
      get "/", action: :index, as: :bulk_provisions
      post "edit", action: :index, as: :edit_bulk_provisions
      post "preview", action: :preview, as: :preview_bulk_provisions
      post "/", action: :apply, as: :apply_bulk_provisions
    end

    scope path: "bulk-access-documents", controller: :bulk_access_documents do
      get "/", action: :index, as: :bulk_access_documents
      post "edit", action: :index, as: :edit_bulk_access_documents
      post "preview", action: :preview, as: :preview_bulk_access_documents
      post "/", action: :apply, as: :apply_bulk_access_documents
    end

    scope path: "bulk-bmid", controller: :bulk_bmid do
      get "/", action: :index, as: :bulk_bmid
      post "edit", action: :index, as: :edit_bulk_bmid
      post "preview", action: :preview, as: :preview_bulk_bmid
      post "/", action: :apply, as: :apply_bulk_bmid
    end
  end

  # The Mentor interface (upstream Ember /mentor/*). Potential Alphas is the
  # first page ported; the rest of the suite (assignments, pods, surveys)
  # lands here later.
  namespace :mentoring do
    # Not year-scoped -- the roster is current standing, see
    # Intake.retrieve_current_potentials.
    get "potential-alphas", to: "potential_alphas#index", as: :potential_alphas
    get "potential-alphas/:person_id", to: "potential_alphas#detail", as: :potential_alphas_detail

    # Also not year-scoped: the roster is who is a Prospective now. The POST
    # re-renders #index rather than redirecting, so it needs no path of its own.
    get "convert-prospectives", to: "convert_prospectives#index", as: :convert_prospectives
    post "convert-prospectives", to: "convert_prospectives#convert"
    get "convert-prospectives/:person_id", to: "convert_prospectives#detail", as: :convert_prospectives_detail

    # Not year-scoped either, though its roster IS read from the year's status
    # audit trail -- see Intake.retrieve_year_class. The year is pinned to
    # Current.year, matching the two pages above.
    get "alpha-status", to: "alpha_status#index", as: :alpha_status
    get "alpha-status/:person_id", to: "alpha_status#detail", as: :alpha_status_detail

    # Year-scoped, unlike its siblings: the report reads a chosen year's Alpha
    # shifts. On-duty mode still pins to the current year (upstream behavior).
    get "shift-report", to: "shift_report#index", as: :shift_report

    # Year-scoped as well. Upstream's mentor/schedule stacked every shift into
    # accordions on one page; here the index picks a shift and each shift owns
    # a page, so the three printable sheets get real URLs.
    get "alpha-schedule", to: "alpha_schedule#index", as: :alpha_schedule
    get "alpha-schedule/:slot_id", to: "alpha_schedule#show", as: :alpha_schedule_shift
    get "alpha-schedule/:slot_id/signup-sheet", to: "alpha_schedule#signup_sheet",
        as: :alpha_schedule_signup_sheet
    get "alpha-schedule/:slot_id/info-sheet", to: "alpha_schedule#info_sheet",
        as: :alpha_schedule_info_sheet
    get "alpha-schedule/:slot_id/apparel", to: "alpha_schedule#apparel",
        as: :alpha_schedule_apparel
    # Upstream's "No Alphas Found" dialog: the Info and Apparel buttons point
    # here instead of at their sheet while no one is signed in, so the reader
    # is told before navigating rather than after.
    get "alpha-schedule/:slot_id/no-alphas", to: "alpha_schedule#no_alphas",
        as: :alpha_schedule_no_alphas

    # Not year-scoped, like the three roster pages above: the roster is who is
    # an Alpha right now (upstream's mentor/alphas takes no year either).
    # Printing is its own URL rather than a swapped-in view, so a sheet can be
    # re-printed from browser history; `print_sheets` because a `print` action
    # would shadow Kernel#print inside the controller.
    get "alpha-acceptance-sheets", to: "alpha_acceptance_sheets#index",
        as: :alpha_acceptance_sheets
    get "alpha-acceptance-sheets/print", to: "alpha_acceptance_sheets#print_sheets",
        as: :alpha_acceptance_sheets_print

    # Not year-scoped either: the roster is who is an Alpha now (upstream's
    # mentor/alphas takes no year). The two POSTs both re-render #index at 422
    # rather than redirecting -- a GET cannot re-derive a half-filled sheet --
    # so neither needs a path of its own beyond the one it posts to.
    # `print_sheet`, not `print`: a `print` action shadows Kernel#print.
    get "alpha-mentor-assignments", to: "alpha_mentor_assignments#index",
        as: :alpha_mentor_assignments
    post "alpha-mentor-assignments", to: "alpha_mentor_assignments#save"
    post "alpha-mentor-assignments/pod-prefill", to: "alpha_mentor_assignments#pod_prefill",
         as: :alpha_mentor_assignments_pod_prefill
    get "alpha-mentor-assignments/print", to: "alpha_mentor_assignments#print_sheet",
        as: :alpha_mentor_assignments_print

    # Not year-scoped either: the roster is this year's verdicts on people who
    # hold Alpha status right now, and upstream's mentor/verdicts pins
    # current_year and takes no parameter. The POST re-renders #index at 422 --
    # a GET cannot re-derive who was just converted, because they are no longer
    # Alphas -- so it needs no path of its own. Which of the two outcomes was
    # asked for rides in the form as `target` rather than splitting into two
    # routes, so both buttons post to one action that reads one contract.
    get "alphas-convert", to: "alphas_convert#index", as: :alphas_convert
    post "alphas-convert", to: "alphas_convert#convert"

    # Year-scoped as well, with a floor of 2023 -- the pod tables hold nothing
    # before that. The index picks an Alpha shift; everything below it manages
    # that shift's pods, and every write answers with a turbo stream.
    get "alpha-pods", to: "alpha_pods#index", as: :alpha_pods
    get "alpha-pods/:slot_id", to: "alpha_pods#show", as: :alpha_pods_shift
    # `print_sheet`, not `print` -- a `print` action would shadow Kernel#print
    # inside the controller (same reason as the acceptance sheets).
    get "alpha-pods/:slot_id/print", to: "alpha_pods#print_sheet", as: :alpha_pods_print

    # Pods themselves. A pod is created and deleted as a linked trio, and :id
    # is always the mentor pod -- the only one with a number people say.
    post "alpha-pods/:slot_id/pods", to: "alpha_pods/pods#create", as: :alpha_pods_pods
    delete "alpha-pods/:slot_id/pods/:id", to: "alpha_pods/pods#destroy", as: :alpha_pods_pod
    patch "alpha-pods/:slot_id/pods/:id/move", to: "alpha_pods/pods#move", as: :alpha_pods_pod_move

    # Pod membership. :pod_id is the sub-pod being written to (the mentor,
    # mitten, or alpha row of a trio), so one set of actions serves all three.
    get "alpha-pods/:slot_id/pods/:pod_id/people/new", to: "alpha_pods/people#new",
        as: :new_alpha_pods_person
    post "alpha-pods/:slot_id/pods/:pod_id/people", to: "alpha_pods/people#create",
         as: :alpha_pods_people
    get "alpha-pods/:slot_id/pods/:pod_id/people/:person_id/edit", to: "alpha_pods/people#edit",
        as: :edit_alpha_pods_person
    patch "alpha-pods/:slot_id/pods/:pod_id/people/:person_id", to: "alpha_pods/people#update",
          as: :alpha_pods_person
    delete "alpha-pods/:slot_id/pods/:pod_id/people/:person_id", to: "alpha_pods/people#destroy"

    # Roster writes for one shift. The search dialog is a GET so it can
    # re-render itself into the modal frame as the query changes.
    get "alpha-schedule/:slot_id/people/new", to: "alpha_schedule/rosters#new",
        as: :new_alpha_schedule_roster
    post "alpha-schedule/:slot_id/people", to: "alpha_schedule/rosters#create",
         as: :alpha_schedule_roster
    delete "alpha-schedule/:slot_id/people/:person_id", to: "alpha_schedule/rosters#destroy",
           as: :alpha_schedule_roster_person

    # Not year-scoped, unlike Shift Report, Alpha Schedule, and Alpha Pods: this
    # page ends shifts that are open right now, so a past year's Alpha shift
    # could never have anyone to sign out. Current.year is pinned, as on the
    # roster pages. Which shift (or the everywhere mode) rides in the query
    # string. The POST re-renders #index at 422 rather than redirecting -- a GET
    # cannot re-derive which rows were just ended, because they are no longer on
    # duty -- so it needs no path of its own.
    get "alpha-signout", to: "alpha_signout#index", as: :alpha_signout
    post "alpha-signout", to: "alpha_signout#sign_out"

    # Year-scoped, and the only /mentoring roster page that keeps the people who
    # washed out -- the post-season review is largely about them. The detail
    # route is UnifiedFlaggingConcern's lazily-loaded per-person frame, and it
    # carries the year, unlike its siblings' copies: this page has one.
    get "post-season-summary", to: "post_season_summary#index", as: :post_season_summary
    get "post-season-summary/:person_id", to: "post_season_summary#detail",
        as: :post_season_summary_detail

    # The Alphas' feedback on their mentors. Not year-scoped: the index lists
    # every year at once (upstream's mentor/surveys takes no year either), and
    # a report page reads the year off the survey it is showing.
    #
    # The drill-down says "mentors" where the training interface says
    # "trainers"; the action keeps the shared concern's name.
    get "surveys", to: "surveys#index", as: :surveys
    get "surveys/:survey_id/reports/:report_id", to: "surveys#report", as: :survey_report
    get "surveys/:survey_id/mentors/:person_id", to: "surveys#trainer", as: :survey_mentor
  end

  namespace :vc do
    resources :applications, only: [:index, :show, :update, :destroy] do
      collection do
        get :search
      end
      member do
        post :status
        post :problem_review
        get :preview_email
        post :send_email
        post :extract_handles
        get :edit_details, path: "edit-details"
        get :edit_personal_info, path: "edit-personal-info"
        get "dialog/:dialog", action: :dialog, as: :dialog
      end
      resources :notes, only: [:create, :update, :destroy], controller: "application_notes"
    end

    get "application-import", to: "application_import#index", as: :application_import
    post "application-import/preview", to: "application_import#preview", as: :application_import_preview
    post "application-import/commit", to: "application_import#commit", as: :application_import_commit

    get "create-prospectives", to: "create_prospectives#index", as: :create_prospectives
    post "create-prospectives/preview", to: "create_prospectives#preview", as: :create_prospectives_preview
    post "create-prospectives/commit", to: "create_prospectives#commit", as: :create_prospectives_commit

    # Link a Clubhouse account to its Burner Profile: look a person up by
    # callsign, search Salesforce Accounts (SOSL), copy a contact's BPGUID__c onto
    # the person through the row's signed link. The search rides in a POST body
    # -- it is a last name or an email -- and answers with turbo streams.
    get "bpguid", to: "bpguid#index", as: :bpguid
    get "bpguid/:person_id", to: "bpguid#show", as: :bpguid_person
    patch "bpguid/:person_id", to: "bpguid#update"
    # Both forms are on every page, so a search may run with no person shown.
    post "bpguid(/:person_id)/search", to: "bpguid#search", as: :bpguid_search

    resources :photos, only: [:index]

    get "handle-checker", to: "handle_checker#index", as: :handle_checker

    get "spigot-flow-report", to: "spigot_flow_report#index", as: :spigot_flow_report

    get "shiny-penny-report", to: "shiny_penny_report#index", as: :shiny_penny_report

    get "thank-you-cards", to: "thank_you_cards#index", as: :thank_you_cards

    get "unified-flagging", to: "unified_flagging#index", as: :unified_flagging
    get "unified-flagging/:person_id", to: "unified_flagging#detail", as: :unified_flagging_detail

    resources :reserved_handles, path: "reserved-handles", only: %i[index new create edit update destroy] do
      collection do
        post :expire
        get :upload
        post :upload, action: :upload_run, as: :upload_run
      end
    end

    get "maintenance", to: "maintenance#index", as: :maintenance
    get "maintenance/preview-pnvs", to: "maintenance#preview_pnvs", as: :maintenance_preview_pnvs
    get "maintenance/preview-past-prospectives", to: "maintenance#preview_past_prospectives",
        as: :maintenance_preview_past_prospectives
    post "maintenance/reset-pnvs", to: "maintenance#reset_pnvs", as: :maintenance_reset_pnvs
    post "maintenance/reset-past-prospectives", to: "maintenance#reset_past_prospectives", as: :maintenance_reset_past_prospectives

    get "photos-review", to: "photos_review#index", as: :photos_review
    scope "photos-review", controller: :photos_review, as: :photos_review do
      patch ":id/approve", action: :approve, as: :approve
      get ":id/reject", action: :reject_dialog, as: :reject_dialog
      patch ":id/reject", action: :reject, as: :reject
      get ":id/reject-preview", action: :reject_preview, as: :reject_preview
      get ":id/info", action: :info, as: :info
      get ":id/crop", action: :crop, as: :crop
      patch ":id/crop", action: :crop_save, as: :crop_save
      delete ":id", action: :destroy, as: :photo
    end
  end

  # HQ Window Interface (Ember hq route tree). The index redirector sends the
  # person to shift-manage when on site, otherwise to site-registration.
  scope "hq/:person_id", module: :hq, as: :hq do
    get "", to: "index#show", as: ""
    get "tickets-provisions", to: "tickets_provisions#show", as: :tickets_provisions
    scope path: "shift-manage", as: "shift_manage", controller: :shift_manage do
      get "", action: :index
      post "shift/start", action: :start_shift
      post "shift/end", action: :end_shift
      post "shift/resignin", action: :resignin
      get "shift/position", action: :correct_position
      patch "shift/position", action: :update_position
      delete "shift/entry", action: :delete_mistake
      patch "timesheet/:timesheet_id/verify", action: :verify_timesheet, as: :verify_timesheet
      patch "timesheet/:timesheet_id/unverify", action: :unverify_timesheet, as: :unverify_timesheet
      get "timesheet/:timesheet_id/correction", action: :correction_form, as: :correction_form
      patch "timesheet/:timesheet_id/correction", action: :submit_correction, as: :submit_correction
      get "missing-request/new", action: :new_missing_request, as: :new_missing_request
      post "missing-request", action: :create_missing_request, as: :missing_request
      post "assets", action: :asset_checkout, as: :assets
      patch "assets/:person_asset_id/check-in", action: :asset_check_in, as: :asset_check_in
      get "assets/:person_asset_id/change-attachment", action: :asset_change_attachment, as: :asset_change_attachment
      patch "assets/:person_asset_id/attachment", action: :asset_update_attachment, as: :asset_update_attachment
      get "pogs/new", action: :new_pog, as: :new_pog
      post "pogs", action: :create_pog, as: :pogs
      get "pogs/:pog_id/edit", action: :edit_pog, as: :edit_pog
      get "pogs/:pog_id/cancel", action: :cancel_pog_form, as: :cancel_pog_form
      patch "pogs/:pog_id", action: :update_pog, as: :update_pog
      post "off-site", action: :mark_off_site, as: :off_site
    end
    scope path: "site-registration", as: "site_registration", controller: :site_registration do
      get "", action: :show
      patch "camp-info", action: :save_camp_info, as: :camp_info
      patch "emergency-contact", action: :save_emergency_contact, as: :emergency_contact
      get "radio-check", action: :radio_check, as: :radio_check
      post "on-site", action: :mark_on_site, as: :on_site

      # The Radios step issues gear without leaving the wizard, so it owns its
      # own asset endpoints rather than borrowing shift-manage's (whose
      # redirects would drop the operator out of the wizard).
      post "assets", action: :asset_checkout, as: :assets
      patch "assets/:person_asset_id/check-in", action: :asset_check_in, as: :asset_check_in
      get "assets/:person_asset_id/change-attachment", action: :asset_change_attachment, as: :asset_change_attachment
      patch "assets/:person_asset_id/attachment", action: :asset_update_attachment, as: :asset_update_attachment
    end

    # HQ-scoped twins of the person scheduling routes, so the window operator
    # never leaves the HQ shell. Unlike /person these are locked to the current
    # year — the HQ shell has no year selector (see HqConcern).
    get "schedule", to: "scheduling#index", as: :scheduling
    get "schedule/export", to: "scheduling#export", as: :scheduling_export, constraints: { format: :ics }
    get "schedule/signup-summary", to: "scheduling#signup_summary", as: :scheduling_signup_summary
    get "schedule/qualifications", to: "scheduling#qualifications", as: :scheduling_qualifications
    get "schedule/:slot_id/signups", to: "scheduling#signups", as: :scheduling_signups
    delete "schedule/:slot_id", to: "scheduling#destroy", as: :scheduling_destroy

    get "schedule/sign-ups", to: "available_sign_ups#index", as: :scheduling_sign_ups
    get "schedule/sign-ups/position/:position_id", to: "available_sign_ups#show", as: :scheduling_sign_ups_position
    post "schedule/sign-ups/position/:position_id/slot/:slot_id", to: "available_sign_ups#create", as: :scheduling_sign_ups_slot
    delete "schedule/sign-ups/position/:position_id/slot/:slot_id", to: "available_sign_ups#destroy"

    # HQ-scoped twin of the person mailbox, so delivering a message to the
    # Ranger standing at the window does not eject the operator from the shell.
    resources :messages, only: [:index, :new, :create, :show] do
      get :find_recipient, on: :collection
      get :suggest_callsigns, on: :collection
      post :search_callsigns, on: :collection
      post :select_callsign, on: :collection
      member do
        post :toggle_archive, path: "archive"
        post :toggle_read, path: "read"
        post :create_reply, path: "reply"
      end
    end

    # HQ-scoped twin of the /me timesheet pages — the same self-serve
    # corrections flow, driven by the window operator on the person's behalf.
    # Locked to the current year and always correction-enabled; final
    # confirmation stays a /me-only step (see HqTimesheetConcern).
    resources :timesheets, only: [:index, :edit, :update] do
      member do
        patch :mark_verified, path: "verified"
      end
      collection do
        get :event_summary, path: "event-summary"
      end
    end
    resources :missing_requests, path: "timesheets/missing-requests", except: [:show]

    # Read-only, current-year twin of /person/:id/training — the window operator
    # can check a Ranger's training and ART status without leaving the shell.
    # No write routes: online-course management stays on the person page.
    get "training", to: "training#index", as: :training

    # In-shell assets page (Ember hq/assets): checkout plus the current year's
    # check in/out history. The checkout/check-in/attachment actions are
    # AssetManagementConcern's, mounted on this page's own paths.
    scope path: "assets", as: "assets", controller: :assets do
      get "", action: :index
      post "", action: :asset_checkout, as: :checkout
      patch ":person_asset_id/check-in", action: :asset_check_in, as: :check_in
      get ":person_asset_id/change-attachment", action: :asset_change_attachment, as: :change_attachment
      patch ":person_asset_id/attachment", action: :asset_update_attachment, as: :update_attachment
    end
  end

  # Training Interface (Ember training/:position_id tree) — one suite per
  # training position, addressed by title slug ("in-person", "green-dot";
  # see Training.slug), resolved and authorized by Training::BaseController
  # per Laravel's TrainingPolicy. The upstream "dirt" alias and numeric ids
  # are dropped by decree. Phase 1 carries the sessions landing; the report
  # and session-management pages join this scope as they are ported.
  scope "training/:slug", module: :training, as: :training do
    get "", to: "sessions#index", as: ""

    # Reports (Phase 2) -- read-only, one controller per report.
    get "capacity", to: "capacity#index", as: :capacity
    get "multiple-enrollments", to: "multiple_enrollments#index", as: :multiple_enrollments
    get "trainer-attendance", to: "trainer_attendance#index", as: :trainer_attendance
    get "trained-no-work", to: "trained_no_work#index", as: :trained_no_work
    get "untrained-people", to: "untrained_people#index", as: :untrained_people
    get "online-course-progress", to: "online_course_progress#index", as: :online_course_progress
    # Mentee-ART-only (Tow Truck, Green Dot) -- the controller redirects any
    # other slug, same as Training.has_mentees? hides the menu item. Not
    # year-scoped: the report is current standing.
    get "mentees", to: "mentees#index", as: :mentees
    delete "mentees/:person_id", to: "mentees#destroy", as: :revoke_mentee_positions
    # Undo for a mis-clicked revoke. The positions to restore ride in from the
    # revoked row rather than being re-derived, so only what was just taken
    # comes back -- see Training::MenteesController#restorable_position_ids.
    post "mentees/:person_id/restore", to: "mentees#restore", as: :restore_mentee_positions
    # ART-only (upstream TrainingPolicy::trainingNotes requires is_art) -- the
    # controller redirects an In-Person slug.
    get "all-notes", to: "all_notes#index", as: :all_notes

    # ART mentoring (has_art_mentoring trainings only; the controllers redirect
    # any other slug). A mentoring shift's key is its mentee slot's id, or "t"
    # and a timesheet id for sign-ins that matched no shift -- see
    # ArtMentoring::Shifts.
    scope "mentoring", module: :mentoring, as: :mentoring do
      get "", to: "landing#index", as: ""
      get "assignment", to: "assignments#index", as: :assignment
      get "assignment/:key", to: "assignments#show", as: :assignment_shift, constraints: { key: /t?\d+/ }
      post "assignment/:key", to: "assignments#save", constraints: { key: /t?\d+/ }
      # A general note is added with the roster's Save; these change one.
      resources :general_notes, path: "general-notes", only: %i[edit update destroy]
      get "verdicts", to: "verdicts#index", as: :verdicts
      get "multiple-shifts", to: "multiple_shifts#index", as: :multiple_shifts
    end

    # The applicant pipeline, read-only and In-Person Training only (the data
    # is position-agnostic). Shares its templates and filtering with the
    # vc_unified_flagging twin -- see UnifiedFlaggingConcern.
    get "unified-flagging", to: "unified_flagging#index", as: :unified_flagging
    get "unified-flagging/:person_id", to: "unified_flagging#detail", as: :unified_flagging_detail

    # Trainer resources (Ember training/:position_id/resources) -- the one
    # document a training position publishes for its trainers. Upstream
    # toggled the editor inline; here it gets its own page, so a half-written
    # document survives a reload and the future team flavor can reuse the
    # form unchanged.
    get "resources", to: "resources#show", as: :resources
    get "resources/edit", to: "resources#edit", as: :edit_resources
    post "resources", to: "resources#create"
    patch "resources", to: "resources#update"
    delete "resources", to: "resources#destroy"

    # Upstream showed every session's roster in one accordion stack; here the
    # index summarizes and each session gets its own page.
    get "completed-training", to: "completed_training#index", as: :completed_training
    get "completed-training/:slot_id", to: "completed_training#show", as: :completed_training_session

    # Survey reports (Ember training/:position_id/survey, pluralized here).
    # One index covers the training, mentor, and mentee audiences that
    # upstream split across three ?position_id= links. report_id is "main" or
    # a survey_group id -- exactly what Survey.find_for_query emits. Trainer
    # feedback drills into its own page instead of upstream's accordion wall.
    get "surveys", to: "surveys#index", as: :surveys
    get "surveys/:survey_id/reports/:report_id", to: "surveys#report", as: :survey_report
    get "surveys/:survey_id/trainers/:person_id", to: "surveys#trainer", as: :survey_trainer

    # Session management (Ember training/:position_id/session/:slot_id).
    # Reads live on SessionsController; mutations get focused controllers
    # under training/sessions/.
    scope "session/:slot_id", as: :session do
      get "", to: "sessions#show", as: ""
      get "signup-sheet", to: "sessions#signup_sheet", as: :signup_sheet
      get "trainers-report", to: "sessions#trainers_report", as: :trainers_report

      scope module: :sessions do
        get "score/:person_id", to: "scores#edit", as: :edit_score
        post "score/:person_id", to: "scores#update", as: :score
        get "notes/:note_id/edit", to: "notes#edit", as: :edit_note
        patch "notes/:note_id", to: "notes#update", as: :note
        delete "notes/:note_id", to: "notes#destroy"
        post "trainer-statuses", to: "trainer_statuses#update_all", as: :trainer_statuses
        get "roster/new", to: "rosters#new", as: :new_roster
        post "roster", to: "rosters#create", as: :roster
        delete "roster/:person_id", to: "rosters#destroy", as: :remove_roster
        get "graduation", to: "graduations#show", as: :graduation
        post "graduation", to: "graduations#create"
        get "work-history/:person_id", to: "work_histories#show", as: :work_history
      end
    end
  end

  resources :person, path: "person", only: [:show, :destroy] do
    get :redirect_to_hq, to: "person#redirect_to_hq"
    post :toggle_onsite
    post :resend_welcome
    post :reset_onboarding

    scope module: :person do
      get "dashboard", to: "dashboard#show", as: :dashboard

      get "agreements", to: "agreements#index", as: :agreements
      patch "agreements", to: "agreements#update"

      resources :assets, only: [:index, :create, :destroy] do
        collection do
          patch :authorization, action: :update_authorization
        end

        member do
          patch :check_in
          get :change_attachment
          patch :update_attachment
          get :history
        end
      end

      resources :vehicles, only: [:index], controller: "vehicles" do
        collection do
          patch :update_mvr_flags
          patch :update_pvr_flags
          patch :update_agreements
          patch :update_blacklist
        end
      end

      # The shift check in/out page; its POST actions stay under timesheets/shift/* below.
      get "shift-manage", to: "timesheets#shift_manage", as: :shift_manage

      resources :timesheets, only: [:index, :edit, :update, :destroy] do
        collection do
          get :log
          get :breakdown
          post :confirm
          get :backfill
          post :backfill, action: :create_backfill, as: nil
          post :start_shift, path: "shift/start"
          post :end_shift, path: "shift/end"
          post :resignin, path: "shift/resignin"
          get :correct_position, path: "shift/position"
          patch :update_position, path: "shift/position", as: nil
          delete :delete_mistake, path: "shift/entry"
        end
        member do
          post :signoff
        end
      end

      get "work-history", to: "work_history#index", as: :work_history
      get "work-history/position-summary", to: "work_history#position_summary", as: :work_history_position_summary
      get "work-history/position-all", to: "work_history#position_all", as: :work_history_position_all
      get "work-history/entire-year", to: "work_history#entire_year", as: :work_history_entire_year

      resources :missing_requests, path: "timesheets/missing-requests", except: [:index]

      get "training", to: "training#index", as: :training
      patch "training/online-course", to: "training#update_online_course", as: :training_online_course
      post "training/online-course/mark-completed", to: "training#mark_online_course_completed", as: :training_mark_completed
      post "training/online-course/sync", to: "training#sync_online_course_info", as: :training_sync
      post "training/online-course/reset-password", to: "training#reset_online_course_password", as: :training_reset_password

      resources :certifications, only: [:index, :show, :new, :create, :edit, :update, :destroy]

      resources :awards, only: [:index, :new, :create, :edit, :update, :destroy] do
        post :rebuild, on: :collection
      end

      resources :applications, only: [:index]

      get "mail-log", to: "mail_log#index", as: :mail_log
      get "mail-log/:id/body", to: "mail_log#body", as: :mail_log_body
      # The button in the email banner on the person page and the HQ window.
      post "email-suppression/clear", to: "email_suppressions#clear", as: :email_suppression_clear

      get "unified-flagging", to: "unified_flagging#show", as: :unified_flagging
      patch "unified-flagging/known-folks", to: "unified_flagging#update_known_folks", as: :unified_flagging_known_folks
      resources :intake_notes, path: "unified-flagging/notes", only: [:new, :create, :edit, :update, :destroy]

      resources :banners, only: [:index, :new, :create, :edit, :update, :destroy]
      resource :callsign, only: [:edit, :update] do
        post :release
      end
      resource :external_ids, path: "external-ids", only: [:show, :update]
      resources :sessions, only: [:index, :destroy], path: "login-sessions"
      # The passkeys on someone's account, for an Admin to see, remove, and add
      # a hardware key to. Not behind Passkeys.enabled? like the person's own
      # pages: an Admin must be able to clear a passkey even on a Clubhouse that
      # offers none. The controller turns away the three that add one there.
      resources :passkeys, only: [:index, :new, :create, :destroy] do
        post :options, on: :collection
      end

      get "profile", to: "profiles#show", as: :profile

      resource :alerts, only: [:edit, :update], path: "profile/alerts"

      get "profile/:section_id/edit", to: "profiles#edit", as: :edit_profile_section
      patch "profile/:section_id", to: "profiles#update", as: :profile_section

      resources :languages, path: "profile/languages", as: :profile_languages
      resources :photos, only: [:new, :create, :destroy] do
        member do
          get :crop
          patch :crop_save
        end
      end
      resource :membership, only: [:edit, :update]

      get "permissions", to: "permissions#edit", as: :permissions
      patch "permissions", to: "permissions#update"

      get "mentoring", to: "mentoring#index"
      patch "mentoring", to: "mentoring#update", as: :mentoring_update

      resources :messages, only: [:index, :new, :create, :show] do
        get :find_recipient, on: :collection
        get :suggest_callsigns, on: :collection
        post :search_callsigns, on: :collection
        post :select_callsign, on: :collection
        member do
          post :toggle_archive, path: "archive"
          post :toggle_read, path: "read"
          post :create_reply, path: "reply"
        end
      end
      resource :password, only: [:update], controller: :passwords
      get "password", to: "passwords#edit"
      resource :status, only: [:edit, :update]
      get "status-history", to: "status_history#index", as: :status_history
      get "site-log", to: "site_log#index", as: :site_log
      resources :fka, path: "fka", only: [:new, :create, :edit, :update, :destroy]
      resources :swag, only: [:index, :new, :create, :edit, :update, :destroy]
      resources :pogs, only: [:index, :new, :create, :edit, :update, :destroy]

      get "tickets-provisions", to: "tickets_provisions#show", as: :tickets_provisions
      get "tickets-provisions/dashboard", to: "tickets_provisions#dashboard", as: :tickets_provisions_dashboard
      resources :access_documents, path: "tickets-provisions/access-documents",
                only: [:new, :create, :edit, :update, :destroy] do
        get :history, on: :member
      end
      resources :provisions, path: "tickets-provisions/provisions",
                only: [:new, :create, :edit, :update, :destroy]

      resource :bmid, only: [:show, :create, :update], controller: :bmids

      get "schedule", to: "scheduling#index", as: :scheduling
      get "schedule/export", to: "scheduling#export", as: :scheduling_export, constraints: { format: :ics }
      get "schedule/signup-summary", to: "scheduling#signup_summary", as: :scheduling_signup_summary
      get "schedule/qualifications", to: "scheduling#qualifications", as: :scheduling_qualifications
      get "schedule/:slot_id/signups", to: "scheduling#signups", as: :scheduling_signups
      delete "schedule/:slot_id", to: "scheduling#destroy", as: :scheduling_destroy

      get "schedule/sign-ups", to: "available_sign_ups#index", as: :scheduling_sign_ups
      get "schedule/sign-ups/position/:position_id", to: "available_sign_ups#show", as: :scheduling_sign_ups_position
      post "schedule/sign-ups/position/:position_id/slot/:slot_id", to: "available_sign_ups#create", as: :scheduling_sign_ups_slot
      delete "schedule/sign-ups/position/:position_id/slot/:slot_id", to: "available_sign_ups#destroy"
    end
  end

  namespace :admin do
    resources :action_logs, path: "action-logs", only: [:index]

    # The problems people reported from the Bug Report button. Purge clears the
    # whole log at once.
    get "bug-reports", to: "bug_reports#index", as: :bug_reports
    delete "bug-reports", to: "bug_reports#purge", as: :purge_bug_reports

    # Exceptions and integration failures recorded by the system (LMS, email,
    # SMS, and other background work). Purge clears the whole log at once.
    get "error-log", to: "error_logs#index", as: :error_logs
    delete "error-log", to: "error_logs#purge", as: :purge_error_logs

    # What Solid Queue holds -- every job by state, and the processes serving
    # it -- with the repairs a Tech Ninja can make: retry a failed job, delete
    # one, or do either for every failed job at once. The collection routes are
    # drawn before the member ones, so "failed" never reaches destroy; the id
    # constraint is for a non-numeric id, which MariaDB would otherwise cast
    # ("1abc" finds job 1).
    resources :jobs, only: [:index, :destroy], constraints: { id: /\d+/ } do
      post :retry, on: :member
      collection do
        post :retry_all, path: "retry-all"
        delete :destroy_failed, path: "failed"
      end
    end

    # The audit log kept by the first version of the Clubhouse. Frozen in
    # October 2019 and read-only; it is here for historical and investigative
    # purposes.
    get "clubhouse1-log", to: "clubhouse1_log#index", as: :clubhouse1_log

    # The documents the Clubhouse displays: agreements, dashboard links, contact
    # sections, and bookmarks. Each preview loads on demand, so opening the list
    # does not render every document at once.
    resources :documents, except: [:show] do
      member do
        get :body
      end
    end

    # The emails the Clubhouse has recorded. The body of each message loads on
    # demand, so opening the list does not decompress hundreds of them.
    get "mail-log", to: "mail_log#index", as: :mail_log
    get "mail-log/:id/body", to: "mail_log#body", as: :mail_log_body

    # Every request the Clubhouse answered. Expire drops everything past the
    # retention window; a nightly job does the same on its own.
    resources :request_logs, path: "request-logs", only: [:index] do
      delete :expire, on: :collection
    end

    # Twilio, which the Clubhouse sends and receives texts through: the texts
    # Twilio sent and received, what it says about the account, and the
    # settings the Clubhouse texts with. The account panel and the log are
    # routes of their own, each loaded into a lazy frame, so a slow or
    # unreachable Twilio holds up those frames and nothing else.
    get "sms-management", to: "sms_management#index", as: :sms_management
    get "sms-management/twilio", to: "sms_management#twilio", as: :sms_management_twilio
    get "sms-management/messages", to: "sms_management#messages", as: :sms_management_messages
    post "sms-management/lookup", to: "sms_management#lookup", as: :sms_management_lookup
    # Where Twilio posts the texts Rangers send: pointed here at the cutover
    # from Clubhouse 2, or back again. Answers into the account panel's frame.
    patch "sms-management/incoming", to: "sms_management#update_incoming", as: :sms_management_incoming

    # The start and end times that bound each event year. Read by Edit Slots as
    # well as Admin, so the index is wider than the writes it offers.
    resources :event_dates, path: "event-dates", except: [:show]

    # The other websites people can sign in to with their Clubhouse account.
    # Each record holds the client id and secret one website presents.
    resources :oauth_clients, path: "oauth-client", except: [:show]

    # Every passkey on every account. To look, not to touch: a passkey is
    # removed from the page of the person it belongs to.
    resources :passkeys, only: [:index]

    # Which Moodle (LMS) course each training position uses for a year. The
    # three LMS lookups (name sync, enrollment, course catalog) get their own
    # routes so a slow or unreachable LMS only affects the page that called it.
    resources :online_courses, path: "online-course", except: [:show] do
      member do
        get :enrollment
        get "enrollment-roster", action: :enrollment_roster, as: :enrollment_roster
        post "set-name", action: :set_name, as: :set_name
      end
      collection do
        get "moodle-catalog", action: :moodle_catalog, as: :moodle_catalog
        get "moodle-catalog-courses", action: :moodle_catalog_courses, as: :moodle_catalog_courses
      end
    end

    # The permissions the Clubhouse grants, and what confers each one. The ART
    # permissions are minted four at a time from a training position, so that
    # tool gets its own pair of routes rather than a record id.
    resources :permissions, only: [:index, :edit, :update, :destroy] do
      collection do
        get "art", action: :new_art, as: :new_art
        post "art", action: :create_art
      end
    end

    # The wording of each alert a Ranger can subscribe to. The list itself is
    # fixed -- every alert is referenced by id from code -- so the only write
    # is an edit.
    resources :rbs_alerts, path: "rbs-alerts", only: [:index, :edit, :update]

    # A SOQL console onto the Salesforce org the application import reads. Tech
    # Team only. The query rides in the POST body -- SOQL can name a person and
    # outgrow a URL -- and run answers with turbo streams.
    get "salesforce-query", to: "salesforce_query#index", as: :salesforce_query
    post "salesforce-query", to: "salesforce_query#run", as: :run_salesforce_query

    # The shift types the Shift Coverage report can be run for, and the posts
    # (columns) each one shows. Posts belong to one shift type, so they hang off
    # it, and say "posts" in the URL because that is the word people see. A move
    # is a PATCH one place up or down.
    resources :shift_coverage_groups, path: "shift-coverage-management" do
      patch :move, on: :member
      resources :posts, controller: "shift_coverage_positions", except: [:index, :show] do
        patch :move, on: :member
      end
    end

    resources :settings, except: [:create, :destroy]
  end

  # Test-only harness routes for system test fixtures
  if Rails.env.test?
    get "test_harness/autocomplete", to: "test_harness#autocomplete_fixture"
    get "test_harness/search_bar", to: "test_harness#search_bar_fixture"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
