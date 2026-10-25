# frozen_string_literal: true

class Setting < ApplicationRecord
  include BasicCacheHelper

  self.table_name = "setting"
  self.primary_key = "name"

  # Type constants
  TYPE_BOOL = "bool"
  TYPE_DATE = "date"
  TYPE_DATETIME = "datetime"
  TYPE_EMAIL = "email"
  TYPE_FLOAT = "float"
  TYPE_INTEGER = "integer"
  TYPE_STRING = "string"
  TYPE_URL = "url"

  # Setting name constants
  ACCOUNT_CREATION_EMAIL = "AccountCreationEmail"
  ALLOW_SIGNUPS_WITHOUT_PHOTO = "AllowSignupsWithoutPhoto"
  ALL_YOU_CAN_EAT_EVENT_WEEK_THRESHOLD = "AllYouCanEatEventWeekThreshold"
  ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD = "AllYouCanEatEventPeriodThreshold"
  AUDITOR_REGISTRATION_DISABLED = "AuditorRegistrationDisabled"
  BROADCAST_CLUBHOUSE_NOTIFY = "BroadcastClubhouseNotify"
  BROADCAST_CLUBHOUSE_SANDBOX = "BroadcastClubhouseSandbox"
  BROADCAST_MAIL_SANDBOX = "BroadcastMailSandbox"
  BROADCAST_MAIL_TEST_ADDRESS = "BroadcastMailTestAddress"
  BROADCAST_SMS_SANDBOX = "BroadcastSMSSandbox"
  DAILY_REPORT_EMAIL = "DailyReportEmail"
  DASHBOARD_PERIOD = "DashboardPeriod"
  DATABASE_CREATED_ON = "DatabaseCreatedOn"
  GEMINI_API_KEY = "GeminiAPIKey"
  GEMINI_MODEL = "GeminiModel"
  GOOGLE_ANALYTICS_ID = "GoogleAnalyticsID"
  HQ_WINDOW_INTERFACE_ENABLED = "HQWindowInterfaceEnabled"
  JOINING_RANGER_SPECIAL_TEAMS_URL = "JoiningRangerSpecialTeamsUrl"
  MAILING_LIST_UPDATE_REQUEST_EMAIL = "MailingListUpdateRequestEmail"
  MEAL_DATES = "MealDates"
  MEAL_HALF_POG_ENABLED = "MealHalfPogEnabled"
  MEAL_INFO_AVAILABLE = "MealInfoAvailable"
  MOTOR_POOL_PROTOCOL_ENABLED = "MotorPoolProtocolEnabled"
  MVR_DEADLINE = "MVRDeadline"
  ONBOARD_ALPHA_SHIFT_PREP_LINK = "OnboardAlphaShiftPrepLink"
  ONLINE_COURSE_ENABLED = "OnlineCourseEnabled"
  ONLINE_COURSE_SITE_URL = "OnlineCourseSiteUrl"
  ONLINE_COURSE_DISABLED_ALLOW_SIGNUPS = "OnlineCourseDisabledAllowSignups"
  MOODLE_DOMAIN = "MoodleDomain"
  MOODLE_TOKEN = "MoodleToken"
  MOODLE_HALF_COURSE_ID = "MoodleHalfCourseId"
  MOODLE_FULL_COURSE_ID = "MoodleFullCourseId"
  MOODLE_SERVICE_NAME = "MoodleServiceName"
  MOODLE_STUDENT_ROLE_ID = "MoodleStudentRoleID"
  PHOTOS_EXPIRED_EMAIL = "PhotosExpiredEmail"
  PHOTO_UPLOAD_ENABLE = "PhotoUploadEnable"
  PROSPECTIVE_APPLICATION_MAIL_SANDBOX = "ProspectiveApplicationMailSandbox"
  RADIO_CHECKOUT_AGREEMENT_ENABLED = "RadioCheckoutAgreementEnabled"
  RADIO_INFO_AVAILABLE = "RadioInfoAvailable"
  RANGER_FEEDBACK_FORM_URL = "RangerFeedbackFormUrl"
  RANGER_MANUAL_URL = "RangerManualUrl"
  RANGER_POLICIES_URL = "RangerPoliciesUrl"
  RANGER_PERSONAL_VEHICLE_POLICY_URL = "RangerPersonalVehiclePolicyUrl"
  REQUEST_LOG_ENABLED = "RequestLogEnabled"
  RRN_EMAIL = "RRNEmail"
  SP_TICKET_THRESHOLD = "SpTicketThreshold"
  TICKET_MAIL_PRIORITY_PRICE = "TicketMailPriorityPrice"
  TICKET_MAIL_STANDARD_PRICE = "TicketMailStandardPrice"
  SANDMAN_REQUIRE_AFFIDAVIT = "SandmanRequireAffidavit"
  SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS = "SandmanRequirePerimeterExpWithinYears"
  SES_MAX_SEND_RATE = "SesMaxSendRate"
  SES_SNS_TOPIC_ARN = "SesSnsTopicArn"
  SF_ENABLE_WRITEBACKS = "SFEnableWritebacks"
  SF_PRD_AUTH_URL = "SFprdAuthUrl"
  SF_PRD_CLIENT_ID = "SFprdClientId"
  SF_PRD_CLIENT_SECRET = "SFprdClientSecret"
  SF_PRD_PASSWORD = "SFprdPassword"
  SF_PRD_USERNAME = "SFprdUsername"
  SC_TICKET_THRESHOLD = "ScTicketThreshold"
  SEND_WELCOME_EMAIL = "SendWelcomeEmail"
  SHIFT_MANAGEMENT_SELF_ENABLED = "ShiftManagementSelfEnabled"
  SHIFT_SIGNUP_FROM_EMAIL = "ShiftSignupFromEmail"
  SHIFT_CHECK_IN_EARLY_PERIOD = "ShiftCheckInEarlyPeriod"
  SHIFT_CHECK_IN_LATE_PERIOD = "ShiftCheckInLatePeriod"
  SHIRT_LONG_SLEEVE_HOURS_THRESHOLD = "ShirtLongSleeveHoursThreshold"
  SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD = "ShirtShortSleeveHoursThreshold"
  SHOWER_POG_THRESHOLD = "ShowerPogThreshold"
  SHOWER_ACCESS_EVENT_WEEK_THRESHOLD = "ShowerAccessEventWeekThreshold"
  SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD = "ShowerAccessEntireEventThreshold"
  TAS_ALPHA_FAQ = "TAS_Alpha_FAQ"
  TAS_BOX_OFFICE_OPEN_DATE = "TAS_BoxOfficeOpenDate"
  TAS_DEFAULT_ALPHA_SAP_DATE = "TAS_DefaultAlphaWAPDate"
  TAS_DEFAULT_SOSAP_DATE = "TAS_DefaultSOWAPDate"
  TAS_DEFAULT_SAP_DATE = "TAS_DefaultWAPDate"
  TAS_LSD_PAY_BY_DATE_TIME = "TAS_LSD_PayByDateTime"
  TAS_PAY_BY_DATE_TIME = "TAS_PayByDateTime"
  TAS_PICKUP_LOCATIONS = "TAS_Pickup_Locations"
  TAS_SPECIAL_PRICE_VEHICLE_PASS_COST = "TAS_Special_Price_Vehicle_Pass_Cost"
  TAS_SPECIAL_PRICE_TICKET_COST = "TAS_Special_Price_Ticket_Cost"
  TAS_SUBMIT_DATE = "TAS_SubmitDate"
  TAS_TICKET_FAQ = "TAS_Ticket_FAQ"
  TAS_PROVISIONS_FAQ = "TAS_Provisions_FAQ"
  TAS_VP_FAQ = "TAS_VP_FAQ"
  TAS_SAP_DATE_RANGE = "TAS_SAPDateRange"
  TAS_SAPSO_MAX = "TAS_SAPSOMax"
  TAS_SAP_FAQ = "TAS_SAP_FAQ"
  TAS_SAP_REPORT_EMAIL = "TAS_SAP_Report_Email"
  THANK_YOU_CARDS_HASH = "ThankYouCardsHash"
  TICKET_VENDOR_EMAIL = "TicketVendorEmail"
  TICKET_VENDOR_NAME = "TicketVendorName"
  TICKETING_PERIOD = "TicketingPeriod"
  TICKETS_AND_STUFF_ENABLE_PNV = "TicketsAndStuffEnablePNV"
  TIMESHEET_CORRECTION_ENABLE = "TimesheetCorrectionEnable"
  TRAINING_SEASONAL_ROLE_ENABLED = "TrainingSeasonalRoleEnabled"
  TROUBLESHOOTER_MENTOR_SURVEY_URL = "TroubleshooterMentorSurveyURL"
  TWILIO_ACCOUNT_SID = "TwilioAccountSID"
  TWILIO_AUTH_TOKEN = "TwilioAuthToken"
  TWILIO_SERVICE_ID = "TwilioServiceId"
  VEHICLE_PENDING_EMAIL = "VehiclePendingEmail"
  EVENT_MANAGEMENT_ON_PLAYA_ENABLED = "EventManagementOnPlayaEnabled"

  # Setting descriptions and metadata
  DESCRIPTIONS = {
    ACCOUNT_CREATION_EMAIL => {
      description: "Alert email address when accounts register",
      type: TYPE_EMAIL
    },
    ALLOW_SIGNUPS_WITHOUT_PHOTO => {
      description: "Allow shift sign-ups without requiring an approved photo",
      type: TYPE_BOOL
    },
    ALL_YOU_CAN_EAT_EVENT_WEEK_THRESHOLD => {
      description: "Event week hour threshold to earn an All-You-Can-Eat-Pass",
      type: TYPE_INTEGER,
      default: 0
    },
    ALL_YOU_CAN_EAT_EVENT_PERIOD_THRESHOLD => {
      description: "Event period (pre-event,event,post-event weeks) hour threshold to earn an All-You-Can-Eat-Pass",
      type: TYPE_INTEGER,
      default: 0
    },
    AUDITOR_REGISTRATION_DISABLED => {
      description: "Prevent Auditors from registering for an account in the Clubhouse",
      type: TYPE_BOOL,
      default: false
    },
    BROADCAST_CLUBHOUSE_NOTIFY => {
      description: "Enable RBS notification of new Clubhouse messages",
      type: TYPE_BOOL
    },
    BROADCAST_CLUBHOUSE_SANDBOX => {
      description: "Enable RBS Clubhouse Message sandbox mode (Clubhouse messages not created)",
      type: TYPE_BOOL
    },
    BROADCAST_MAIL_SANDBOX => {
      description: "Enable RBS sandbox email mode",
      type: TYPE_BOOL
    },
    BROADCAST_MAIL_TEST_ADDRESS => {
      description: "Leave blank to send broadcast emails to each Ranger. For testing, enter one address with a ? where the Ranger's id goes: every broadcast email goes there instead (test+?@example.com sends Ranger 8's to test+8@example.com). When BroadcastMailSandbox is on it still stops every email, and until RANGER_CLUBHOUSE_RBS_EMAIL_LIVE is set broadcast email only ever goes to this address. New-message alert emails (Me, Person and HQ Messages) go to this address too.",
      type: TYPE_STRING
    },
    BROADCAST_SMS_SANDBOX => {
      description: "Sandbox SMS messages",
      type: TYPE_BOOL
    },
    DAILY_REPORT_EMAIL => {
      description: "Email address to send the Clubhouse Daily Report",
      type: TYPE_EMAIL
    },
    DASHBOARD_PERIOD => {
      description: "The Dashboard Period",
      type: TYPE_STRING,
      default: "auto",
      options: [
        ["After Event / Off Season (November thru March)", "after-event"],
        ["Before Event (November thru mid-to-late August)", "before-event"],
        ["Event Period (Early Man through October)", "event"],
        ["Post Event (September thru November)", "post-event"]
      ]
    },
    DATABASE_CREATED_ON => {
      description: "For the Staging & Training servers, the date database was created on. (automatically set)",
      type: TYPE_DATETIME,
      default: ""
    },
    GEMINI_API_KEY => {
      description: "Google Gemini API key used to process freeform text (handle extraction, etc)",
      type: TYPE_STRING,
      is_credential: true
    },
    GEMINI_MODEL => {
      description: "Google Gemini model used for handle extraction (e.g., gemini-2.5-flash)",
      type: TYPE_STRING
    },
    GOOGLE_ANALYTICS_ID => {
      description: "The Google Analytics property ID",
      type: TYPE_STRING
    },
    HQ_WINDOW_INTERFACE_ENABLED => {
      description: "Enable the HQ Window Interface (normally enabled during the event)",
      type: TYPE_BOOL,
      default: true
    },
    JOINING_RANGER_SPECIAL_TEAMS_URL => {
      description: "How To Join Ranger Special Teams Document URL",
      type: TYPE_STRING
    },
    MAILING_LIST_UPDATE_REQUEST_EMAIL => {
      description: "Email address(es) to send a message when an active Ranger requests to update the mailing list subscriptions",
      type: TYPE_EMAIL
    },
    MEAL_DATES => {
      description: "Commissary dates and hours",
      type: TYPE_STRING
    },
    MEAL_HALF_POG_ENABLED => {
      description: "Enable or disable issuing of half meal pogs",
      type: TYPE_BOOL,
      default: true
    },
    MEAL_INFO_AVAILABLE => {
      description: "True if meal information is available.",
      type: TYPE_BOOL
    },
    MOTOR_POOL_PROTOCOL_ENABLED => {
      description: "Allow the Vehicle Use Protocol to be signed, and to enable the dashboard prompt",
      type: TYPE_BOOL,
      default: false
    },
    MVR_DEADLINE => {
      description: "The Clubhouse will show the MVR request form link, if eligible, up until the month and day (not year) at 23:59. Format is MM-DD",
      type: TYPE_STRING
    },
    ONBOARD_ALPHA_SHIFT_PREP_LINK => {
      description: "Used by the Onboarding Checklist for PNVs. Link to how to prep for your Alpha Shift in the Ranger Manual",
      type: TYPE_STRING
    },
    ONLINE_COURSE_ENABLED => {
      description: "Enable online course link",
      type: TYPE_BOOL
    },
    ONLINE_COURSE_SITE_URL => {
      description: "Online course Url",
      type: TYPE_STRING
    },
    ONLINE_COURSE_DISABLED_ALLOW_SIGNUPS => {
      description: "Enable shift sign-ups even if the Online Course is disabled (VERY DANGEROUS)",
      type: TYPE_BOOL,
      default: false
    },
    MOODLE_DOMAIN => {
      description: "The LMS domain name",
      type: TYPE_STRING
    },
    MOODLE_TOKEN => {
      description: "Moodle Web Service Token",
      type: TYPE_STRING,
      is_credential: true
    },
    MOODLE_HALF_COURSE_ID => {
      description: "Moodle online course ID for active Rangers (2+ years)",
      type: TYPE_STRING
    },
    MOODLE_FULL_COURSE_ID => {
      description: "Moodle full online course ID for PNVs, Auditors, Binaries, and Inactive Rangers",
      type: TYPE_STRING
    },
    MOODLE_SERVICE_NAME => {
      description: "Moodle service name to use",
      type: TYPE_STRING
    },
    MOODLE_STUDENT_ROLE_ID => {
      description: "The LMS (Moodle) role id to assign to new users (usually student)",
      type: TYPE_INTEGER
    },
    PHOTOS_EXPIRED_EMAIL => {
      description: "Weekly email send when archived photos older than 6 months have been deleted",
      type: TYPE_EMAIL
    },
    PHOTO_UPLOAD_ENABLE => {
      description: "Enable Photo Uploading. If disabled, Admins and VCs will still be able to upload photos on another person's behalf.",
      type: TYPE_BOOL
    },
    PROSPECTIVE_APPLICATION_MAIL_SANDBOX => {
      description: "Prospective Application Mail Sandbox. Leave blank to allow applicant emails to go to the applicant. For testing purposes, enter an email address to where the messages should be sent to instead.",
      type: TYPE_EMAIL
    },
    RADIO_CHECKOUT_AGREEMENT_ENABLED => {
      description: "Allows the Radio Checkout Agreement to be signed.",
      type: TYPE_BOOL
    },
    RADIO_INFO_AVAILABLE => {
      description: "True if radio information has been uploaded.",
      type: TYPE_BOOL
    },
    RANGER_FEEDBACK_FORM_URL => {
      description: "Ranger Feedback Form URL",
      type: TYPE_STRING
    },
    RANGER_MANUAL_URL => {
      description: "The current Ranger Manual document",
      type: TYPE_STRING
    },
    RANGER_POLICIES_URL => {
      description: "Ranger Policy Document URL",
      type: TYPE_STRING
    },
    RANGER_PERSONAL_VEHICLE_POLICY_URL => {
      description: "Ranger Personal Vehicle Document URL (used by Me > Vehicles)",
      type: TYPE_STRING
    },
    REQUEST_LOG_ENABLED => {
      description: "Record every request the Clubhouse answers in the Request Log",
      type: TYPE_BOOL,
      default: true
    },
    RRN_EMAIL => {
      description: "The Ranger Regional Network team email address. Use to process Ranger applications.",
      type: TYPE_EMAIL
    },
    SP_TICKET_THRESHOLD => {
      description: "Credit threshold for a Special Price Ticket. Shown on the Schedule and Ticket announce pages",
      type: TYPE_FLOAT,
      default: 0
    },
    TICKET_MAIL_PRIORITY_PRICE => {
      description: "The price to ship SPTs and Gift Tickets via USPS priority shipping",
      type: TYPE_FLOAT
    },
    TICKET_MAIL_STANDARD_PRICE => {
      description: "The price to ship SPTs and Gift Tickets via standard USPS standard shipping",
      type: TYPE_FLOAT
    },
    SANDMAN_REQUIRE_AFFIDAVIT => {
      description: "Require the Sandman Affidavit be signed in order to work a Sandman shift",
      type: TYPE_BOOL,
      default: false
    },
    SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS => {
      description: "Require a Sandman to have worked a Burn Perimeter or Sandman positions within X years. Leave blank to skip this check.",
      type: TYPE_INTEGER,
      default: 5
    },
    SES_MAX_SEND_RATE => {
      description: "How many emails per second Amazon SES lets this account send. Broadcast emails go out in batches of this many (50 at most), one batch a second. Leave blank for 40.",
      type: TYPE_INTEGER,
      default: 40
    },
    SES_SNS_TOPIC_ARN => {
      description: "ARN of the SNS topic SES publishes delivery, bounce and complaint reports to. Until this is set the /infrastructure/aws-sns endpoint refuses every message.",
      type: TYPE_STRING
    },
    SF_ENABLE_WRITEBACKS => {
      description: "Enable Salesforce Object Update",
      type: TYPE_BOOL
    },
    SF_PRD_AUTH_URL => {
      description: "Salesforce Production Authentication URL",
      type: TYPE_STRING,
      is_credential: true
    },
    SF_PRD_CLIENT_ID => {
      description: "Salesforce Production Client ID",
      type: TYPE_STRING,
      is_credential: true
    },
    SF_PRD_CLIENT_SECRET => {
      description: "Salesforce Production Client Secret",
      type: TYPE_STRING,
      is_credential: true
    },
    SF_PRD_PASSWORD => {
      description: "Salesforce Production Password (login password + security token)",
      type: TYPE_STRING,
      is_credential: true
    },
    SF_PRD_USERNAME => {
      description: "Salesforce Production Username",
      type: TYPE_STRING,
      is_credential: true
    },
    SC_TICKET_THRESHOLD => {
      description: "Credit threshold for staff credential. Shown on the Schedule and Ticket announce pages",
      type: TYPE_FLOAT,
      default: 0
    },
    SEND_WELCOME_EMAIL => {
      description: "Enable Welcome email when an account is created",
      type: TYPE_BOOL
    },
    SHIFT_MANAGEMENT_SELF_ENABLED => {
      description: "Enable Shift Management Self permission",
      type: TYPE_BOOL,
      default: false
    },
    SHIFT_SIGNUP_FROM_EMAIL => {
      description: "From email address for shift sign up messages",
      type: TYPE_EMAIL
    },
    SHIFT_CHECK_IN_EARLY_PERIOD => {
      description: "How soon, in minutes, is the person allowed to check into a shift. Set to blank to disable the check.",
      type: TYPE_INTEGER,
      default: 30
    },
    SHIFT_CHECK_IN_LATE_PERIOD => {
      description: "How late, in minutes, is the person allowed to check into a shift. Set to blank to disable the check.",
      type: TYPE_INTEGER,
      default: 15
    },
    SHIRT_LONG_SLEEVE_HOURS_THRESHOLD => {
      description: "Hour threshold to earn a long sleeve shirt",
      type: TYPE_INTEGER,
      default: 0
    },
    SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD => {
      description: "Hour threshold to earn a short sleeve shirt/t-shirt",
      type: TYPE_INTEGER,
      default: 0
    },
    SHOWER_POG_THRESHOLD => {
      description: "Hour threshold to earn a shower pog to The Wet Spot",
      type: TYPE_INTEGER,
      default: 0
    },
    SHOWER_ACCESS_EVENT_WEEK_THRESHOLD => {
      description: "Event week hour threshold to earn shower access for the next event",
      type: TYPE_INTEGER,
      default: 60
    },
    SHOWER_ACCESS_ENTIRE_EVENT_THRESHOLD => {
      description: "Pre-event/event/post-event period hour threshold to earn shower access for the next event",
      type: TYPE_INTEGER,
      default: 130
    },
    TAS_ALPHA_FAQ => {
      description: "Alpha SAP FAQ Link",
      type: TYPE_STRING
    },
    TAS_BOX_OFFICE_OPEN_DATE => {
      description: "Playa Box Office Opening date and time",
      type: TYPE_DATETIME
    },
    TAS_DEFAULT_ALPHA_SAP_DATE => {
      description: "Default Alpha SAP Access Date",
      type: TYPE_DATE
    },
    TAS_DEFAULT_SOSAP_DATE => {
      description: "Default SAP SO Access Date",
      type: TYPE_DATE
    },
    TAS_DEFAULT_SAP_DATE => {
      description: "Default SAP Access Date",
      type: TYPE_DATE
    },
    TAS_LSD_PAY_BY_DATE_TIME => {
      description: "The date and time LSD items have to be paid for. Shown on various banners.",
      type: TYPE_DATETIME
    },
    TAS_PAY_BY_DATE_TIME => {
      description: "The date and time items have (non-LSD & Gift) to be paid for. Shown on the Ticketing is closed page.",
      type: TYPE_DATETIME
    },
    TAS_PICKUP_LOCATIONS => {
      description: "Locations w/hours to pickup staff credentials and will-call items. Shown on the ticketing page",
      type: TYPE_STRING
    },
    TAS_SPECIAL_PRICE_VEHICLE_PASS_COST => {
      description: "Special Price Vehicle Pass in dollars. (cents not supported)",
      type: TYPE_INTEGER
    },
    TAS_SPECIAL_PRICE_TICKET_COST => {
      description: "Special Price Ticket cost in dollars. (cents not supported)",
      type: TYPE_INTEGER
    },
    TAS_SUBMIT_DATE => {
      description: "Use to tell the user when the regular ticketing window will closed. Format: YYYY-MM-DD.",
      type: TYPE_STRING
    },
    TAS_TICKET_FAQ => {
      description: "Ticketing FAQ Link",
      type: TYPE_STRING
    },
    TAS_PROVISIONS_FAQ => {
      description: "Ticketing Provisions FAQ Link",
      type: TYPE_STRING
    },
    TAS_VP_FAQ => {
      description: "Vehicle Pass FAQ Link",
      type: TYPE_STRING
    },
    TAS_SAP_DATE_RANGE => {
      description: "Allowable SC & SAP August day range. Use used Format: DD-DD. (just the start & ending days, not month). Use to build SAP date options and the TRS spreadsheet.",
      type: TYPE_STRING
    },
    TAS_SAPSO_MAX => {
      description: "Max. SAP SO Count",
      type: TYPE_INTEGER
    },
    TAS_SAP_FAQ => {
      description: "SAP FAQ Link",
      type: TYPE_STRING
    },
    TAS_SAP_REPORT_EMAIL => {
      description: "Email address(es) to send nightly SAPs Needed Report to",
      type: TYPE_EMAIL
    },
    THANK_YOU_CARDS_HASH => {
      description: "Thank You card page password. SHA-256 encoded.",
      type: TYPE_STRING,
      is_credential: true
    },
    TICKET_VENDOR_EMAIL => {
      description: "Ticketing Vendor Support Email",
      type: TYPE_EMAIL
    },
    TICKET_VENDOR_NAME => {
      description: "Ticketing Vendor Name",
      type: TYPE_STRING
    },
    TICKETING_PERIOD => {
      description: "Ticketing Period / Season",
      type: TYPE_STRING,
      options: [
        ["off season - show banked tickets", "offseason"],
        ["announce - tickets have been awarded but ticketing window is not open", "announce"],
        ["open - tickets can be claimed", "open"],
        ["closed - show claims and banks. Changes not directly allowed", "closed"]
      ]
    },
    TICKETS_AND_STUFF_ENABLE_PNV => {
      description: "Enable Ticketing Page for PNVs",
      type: TYPE_BOOL
    },
    TIMESHEET_CORRECTION_ENABLE => {
      description: "Allow users to submit Timesheet Corrections. Note: The Timecard Year Round permission allows access year round.",
      type: TYPE_BOOL
    },
    TRAINING_SEASONAL_ROLE_ENABLED => {
      description: "Enable Training Seasonal Role",
      type: TYPE_BOOL,
      default: false
    },
    TROUBLESHOOTER_MENTOR_SURVEY_URL => {
      description: "If a person worked a TS Mentor shift, present this url on the dashboard",
      type: TYPE_URL
    },
    TWILIO_ACCOUNT_SID => {
      description: "Twilio Account SID",
      type: TYPE_STRING,
      is_credential: true
    },
    TWILIO_AUTH_TOKEN => {
      description: "Twilio Authentication Token",
      type: TYPE_STRING,
      is_credential: true
    },
    TWILIO_SERVICE_ID => {
      description: "Twilio Service ID of SMS Channel",
      type: TYPE_STRING,
      is_credential: true
    },
    VEHICLE_PENDING_EMAIL => {
      description: "Email(s) to notify when vehicle requests are queued up for review. (nightly mail)",
      type: TYPE_EMAIL
    },
    EVENT_MANAGEMENT_ON_PLAYA_ENABLED => {
      description: "Enables Event Management (E.M.) On Playa role AND allows E.M. Year Round to view Emergency Contact Info plus read Clubhouse Messages",
      type: TYPE_BOOL
    }
  }.freeze

  # Callbacks
  after_initialize :set_default_value
  # Once committed, not on save: a reader between the delete and the commit
  # would cache the old row again, with no expiry, in the cache every server
  # and job shares -- and turning the broadcast sandbox on would not take.
  after_commit :clear_cache

  # Validations
  validates :name, presence: true
  validates :value, allow_nil: true, length: { maximum: 65535 }
  validate :check_value_type
  validate :check_test_address_pattern, if: -> { name == BROADCAST_MAIL_TEST_ADDRESS && value.present? }

  # Override find to use DESCRIPTIONS and firstOrNew behavior
  def self.find(id)
    desc = DESCRIPTIONS[id]
    return nil unless desc

    find_by(name: id) || new(name: id)
  end

  # Find or raise RecordNotFound
  def self.find!(id)
    result = find(id)
    raise ActiveRecord::RecordNotFound, "Couldn't find Setting with 'name'=#{id}" unless result
    result
  end

  # Delete every stored setting the Clubhouse no longer knows about. A name
  # that is not described here can never be read or edited, so the row only
  # takes up space and confuses anyone reading the table directly.
  #
  # @return [Array<String>] the names that were deleted, in alphabetical order
  def self.purge_undefined!
    rows = where.not(name: DESCRIPTIONS.keys).order(:name).to_a
    rows.each(&:destroy)
    rows.map(&:name)
  end

  # Every described setting whose name contains the filter, stored or not: one
  # with no row comes back unsaved, holding its default, as in Clubhouse 2.
  def self.find_for_query(query)
    names = DESCRIPTIONS.keys
    filter = query[:filter]&.downcase
    names = names.select { |name| name.downcase.include?(filter) } if filter.present?

    rows = where(name: names).index_by(&:name)
    names.map { |name| rows[name] || new(name:) }.sort_by { |s| s.name.downcase }
  end

  # Get the value of a setting or multiple settings
  # @param setting [String, Array<String>] setting name(s)
  # @param throw_on_empty [Boolean] raise error if value is empty
  # @return [Mixed] single value or hash of values
  def self.get_value(setting, throw_on_empty: false)
    is_array = setting.is_a?(Array)
    names = is_array ? setting : [setting]

    lookup = []
    values = {}

    # Find all the cached settings
    names.each do |name|
      desc = DESCRIPTIONS[name]
      raise ArgumentError, "'#{name}' is an unknown setting." unless desc

      cached_value = get_cached(name, desc[:type])
      if cached_value != :not_found
        values[name] = cached_value
      else
        lookup << name
      end
    end

    return values if is_array && lookup.empty?
    return values[names.first] if !is_array && lookup.empty?

    # Lookup the settings from database
    rows = where(name: lookup).index_by(&:name)

    lookup.each do |name|
      row = rows[name]
      desc = DESCRIPTIONS[name]

      value = stored_or_default(row, desc, throw_on_empty)
      set_cached(name, value)
      values[name] = value
    end

    is_array ? values : values[names.first]
  end

  # A setting read straight from the table, past the cache, for a switch every
  # read of which must see the latest save -- whether broadcast email may go
  # out. A cached copy can lag: a reader that fetched the row just before a
  # save committed writes the old value back after the save has cleared it,
  # and solid_cache keeps it for weeks.
  def self.fresh_value(name)
    stored_or_default(find_by(name:), DESCRIPTIONS.fetch(name), false)
  end

  # Virtual attributes
  def type
    DESCRIPTIONS[name]&.dig(:type)
  end

  def description
    DESCRIPTIONS[name]&.dig(:description)
  end

  def options
    DESCRIPTIONS[name]&.dig(:options)
  end

  def is_credential
    DESCRIPTIONS[name]&.dig(:is_credential) || false
  end

  def default_value
    DESCRIPTIONS[name]&.dig(:default)
  end

  def has_default?
    DESCRIPTIONS[name]&.key?(:default) == true
  end

  def value=(data)
    data = data.split(/[,\n]/).reject(&:blank?).join("\n") if self.type == TYPE_EMAIL
    super data
  end

  private

  def set_default_value
    return if persisted? || value.present?

    desc = DESCRIPTIONS[name]
    self.value = desc[:default] if desc && desc.key?(:default)
  end

  # In production, job workers read settings from the same shared cache as the
  # web server (solid_cache), so deleting the key is all a worker needs to see
  # the new value -- no restart.
  def clear_cache
    cache_delete(name)
    # Some settings gate which roles a person is granted, and those role sets
    # are cached per person with no expiry.
    RoleManager.purge_all if RoleManager::ROLE_SETTINGS.include?(name)
  end

  def self.get_cached(name, type)
    return :not_found unless cache_exist?(name)

    cast_value(type, cache_read(name))
  end

  def self.set_cached(name, value)
    cache_write(name, value)
  end

  def self.stored_or_default(row, desc, throw_on_empty)
    value = if row&.value
              cast_value(desc[:type], row.value)
            elsif desc.key?(:default)
              cast_value(desc[:type], desc[:default])
            end

    if throw_on_empty && (value.nil? || value == "")
      raise "Setting is empty."
    end

    value
  end

  def self.cast_value(type, value)
    case type
    when TYPE_BOOL
      ActiveModel::Type::Boolean.new.cast(value)
    when TYPE_INTEGER
      value.to_i
    when TYPE_FLOAT
      value.to_f
    else
      value
    end
  end

  # The broadcast test address is a pattern: one address with a ? where each
  # Ranger's id goes. Anything else would send broadcast email nowhere at all.
  def check_test_address_pattern
    return if Rbs.test_address(value, 1)

    errors.add(:value, "The value must be one email address with a single ? before the @, such as test+?@example.com, " \
      "short enough to hold any Ranger's id.")
  end

  def check_value_type
    value = self.value
    return true unless value.present?

    case self.type
    when TYPE_STRING
      true
    when TYPE_BOOL
      if value.empty?
        value = false
        return true
      end
      return true if value.match?(/\A(t|true|1)\z/i)
      return true if value.match?(/\A(f|false|0)\z/i)

      errors.add(:value, "Is not a boolean value (true or false)")
      false
    when TYPE_EMAIL
      return true unless value.present?
      emails = value.split(/[,\n]/).reject(&:blank?)
      return true if emails.empty?

      no_errors = true
      emails.each do |email|
        unless email.match(URI::MailTo::EMAIL_REGEXP)
          no_errors = false
          errors.add(:value, "#{email} is not a valid email address")
        end
      end
      no_errors
    when TYPE_URL
      begin
        URI.parse(value)
        true
      rescue URI::InvalidURIError
        false
      end
    when TYPE_DATETIME
      !!Timeliness.parse(value, :datetime, strict: true)
    when TYPE_DATE
      !!Timeliness.parse(value, :date, strict: true)
    when TYPE_FLOAT
      begin
        Float(value)
        true
      rescue ArgumentError, TypeError
        errors.add(:value, "#{value} is not a valid float value")
        false
      end
    when TYPE_INTEGER
      begin
        Integer(value)
        true
      rescue ArgumentError, TypeError
        errors.add(:value, "#{value} is not a valid integer value")
      end
    else
      raise ArgumentError, "Unknown setting type: #{type.inspect}"
    end
  end
end
