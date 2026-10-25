# frozen_string_literal: true

# Builders for the ticketing and BMID suites that sweep whole tables and
# construct their own records instead of leaning on the shared fixtures.
#
# Including suites must define YEAR (the year under test); builders read it via
# self.class::YEAR so each suite keeps its own. `document` defaults its status
# to qualified — a suite whose documents are mostly live overrides
# default_document_status.
module TicketingTestHelper
  # A SAP by default: it is the document type most of these suites watch.
  # delivery_method is set explicitly because the column is NOT NULL and the
  # model's callback misses it on create.
  def document(holder, type: AccessDocument::SAP, status: default_document_status,
               source_year: self.class::YEAR, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year:,
                           delivery_method: AccessDocument::DELIVERY_NONE, **attributes)
  end

  def default_document_status = AccessDocument::QUALIFIED

  # A wet spot pass: it needs no item count and no meal periods, so it is the
  # least noisy stand-in when the test is about who holds what.
  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE,
                    source_year: self.class::YEAR, **attributes)
    Provision.create!(person: holder, type:, status:, source_year:,
                      expires_on: Date.new(self.class::YEAR + 3, 9, 1), **attributes)
  end

  def slot_for(position_id, year: self.class::YEAR, begins: nil, ends: nil, active: true)
    begins ||= Time.zone.local(year, 6, 1, 9, 0, 0)
    Slot.create!(position: position_for(position_id),
                 begins:, ends: ends || begins + 6.hours, max: 10, active:)
  end

  # The positions fixture carries no explicit ids, so positions looked up by
  # constant have to be made here.
  def position_for(id)
    Position.find_or_create_by!(id:) { |position| position.title = "Position #{id}" }
  end

  def sign_up(holder, slot)
    PersonSlot.create!(person: holder, slot:)
  end

  def august(day)
    Time.zone.local(self.class::YEAR, 8, day, 12, 0, 0)
  end

  def sap_date_range(value)
    setting = Setting.find_by(name: Setting::TAS_SAP_DATE_RANGE) || Setting.new(name: Setting::TAS_SAP_DATE_RANGE)
    setting.update!(value:)
  end
end
