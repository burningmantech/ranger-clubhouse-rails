# frozen_string_literal: true

class TicketingInfo
  PERIOD_ANNOUNCE = "announce"
  PERIOD_CLOSED = "closed"
  PERIOD_OFF_SEASON = "offseason"
  PERIOD_OPEN = "open"


  attr_reader :box_office_open_date,
              :faqs,
              :is_enabled_for_pnv,
              :lsd_paid_by,
              :mail_priority_price,
              :mail_standard_price,
              :paid_by,
              :period,
              :pickup_locations,
              :ranger_ticketing_email,
              :sc_credits,
              :sp_vp_cost,
              :spt_cost,
              :spt_credits,
              :submit_date,
              :ticket_vendor_email,
              :ticket_vendor_name,
              :sap_alpha_default_date,
              :sap_date_range,
              :sap_default_date,
              :sap_so_default_date,
              :sap_so_max

  def initialize
    @period = Setting.get_value(Setting::TICKETING_PERIOD)
    @is_enabled_for_pnv = Setting.get_value(Setting::TICKETS_AND_STUFF_ENABLE_PNV)

    @sap_so_max = Setting.get_value(Setting::TAS_SAPSO_MAX)
    @box_office_open_date = Setting.get_value(Setting::TAS_BOX_OFFICE_OPEN_DATE)
    @sap_default_date = Setting.get_value(Setting::TAS_DEFAULT_SAP_DATE)
    @sap_date_range = Setting.get_value(Setting::TAS_SAP_DATE_RANGE)
    @sap_alpha_default_date = Setting.get_value(Setting::TAS_DEFAULT_ALPHA_SAP_DATE)
    @sap_so_default_date = Setting.get_value(Setting::TAS_DEFAULT_SOSAP_DATE)

    @submit_date = Setting.get_value(Setting::TAS_SUBMIT_DATE)

    @ticket_vendor_email = Setting.get_value(Setting::TICKET_VENDOR_EMAIL)
    @ticket_vendor_name = Setting.get_value(Setting::TICKET_VENDOR_NAME)
    @ranger_ticketing_email = EmailAddresses::TICKETING

    @spt_credits = Setting.get_value(Setting::SP_TICKET_THRESHOLD)
    @sc_credits = Setting.get_value(Setting::SC_TICKET_THRESHOLD)

    @pickup_locations = Setting.get_value(Setting::TAS_PICKUP_LOCATIONS)

    @paid_by = Setting.get_value(Setting::TAS_PAY_BY_DATE_TIME)

    @lsd_paid_by = Setting.get_value(Setting::TAS_LSD_PAY_BY_DATE_TIME)

    @spt_cost = Setting.get_value(Setting::TAS_SPECIAL_PRICE_TICKET_COST)
    @sp_vp_cost = Setting.get_value(Setting::TAS_SPECIAL_PRICE_VEHICLE_PASS_COST)

    @mail_standard_price = Setting.get_value(Setting::TICKET_MAIL_STANDARD_PRICE)
    @mail_priority_price = Setting.get_value(Setting::TICKET_MAIL_PRIORITY_PRICE)

    @faqs = {
      ticketing: Setting.get_value(Setting::TAS_TICKET_FAQ),
      sap: Setting.get_value(Setting::TAS_SAP_FAQ),
      vp: Setting.get_value(Setting::TAS_VP_FAQ),
      alpha: Setting.get_value(Setting::TAS_ALPHA_FAQ),
      provisions: Setting.get_value(Setting::TAS_PROVISIONS_FAQ)
    }
  end

  # The selectable SC & SAP access dates: sap_date_range is a "DD-DD" span of
  # August days in the current event year. Empty when the setting is unusable.
  def sap_selectable_dates
    start_day, end_day = sap_date_range.to_s.split("-").map(&:to_i)
    return [] unless start_day&.positive? && end_day&.positive? && end_day >= start_day && end_day <= 31

    (start_day..end_day).map { |day| Date.new(Current.year, 8, day) }
  end
end
