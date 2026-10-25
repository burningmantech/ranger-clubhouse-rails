# frozen_string_literal: true

# TRS export: batches of claimed access documents for upload to the ticket
# vendor's Ticket Request System, plus the follow-up that marks them submitted.
#
# Ported from the Ember vc/access-documents/trs page and its
# utils/access-document-export module, folding in the server-side rules from
# Laravel's TicketingManagement::retrieveCurrentByPerson($forDelivery = true)
# (claimed documents only, deceased/dismissed holders dropped, per-document
# delivery and access-date errors).
#
# Deliberate deviations from upstream, all user-approved:
# - The table and the CSV share one delivery string per row. Upstream showed a
#   server-computed value on screen but exported a different client-computed
#   one; the CSV value (what the vendor actually receives today) wins.
# - No analytics beacon; the audit comment on each document is the trail.
module TrsExport
  # TRS rejects batches larger than this; the controller refuses them upfront.
  MAX_BATCH_SIZE = 2000

  ALL_FILTER = "all"

  # Delivery strings exactly as the TRS spreadsheet expects them.
  CREDENTIAL_PICKUP = "Credential Pick Up" # Pick up in Gerlach before the Box Office runs
  WILL_CALL = "Will Call"                  # Box office
  USPS_STANDARD = "Standard Mail"          # Paid items
  USPS_PRIORITY = "USPS Priority"          # Paid items
  USPS_STANDARD_FOR_GIFT = "USPS (Standard Mail)"
  UPS = "UPS"
  PRINT_AT_HOME = "Print At Home"

  # TRS note vocabulary. Deliberately NOT AccessDocument::SHORT_TICKET_LABELS:
  # these literals have appeared in the vendor's Notes column for years and
  # must stay stable across the rename to SAP.
  NOTE_TYPE_LABELS = {
    AccessDocument::STAFF_CREDENTIAL => "CRED",
    AccessDocument::SPT => "SPT",
    AccessDocument::GIFT => "GIFT",
    AccessDocument::LSD => "LSD",
    AccessDocument::VEHICLE_PASS_SP => "SPVP",
    AccessDocument::VEHICLE_PASS_GIFT => "GIFTVP",
    AccessDocument::VEHICLE_PASS_LSD => "LSDVP",
    AccessDocument::SAP => "WAP",
    AccessDocument::SAPSO => "SOWAP"
  }.freeze

  # Base TRS request-column key per type. SC/SAP/SO SAP get an access-date
  # suffix (_MMDD, _anytime, or _unspecified) via trs_column_and_date.
  TRS_COLUMN = {
    AccessDocument::STAFF_CREDENTIAL => "sc",
    AccessDocument::SPT => "spt",
    AccessDocument::GIFT => "gift_ticket",
    AccessDocument::LSD => "lsd",
    AccessDocument::VEHICLE_PASS_SP => "sp_vp",
    AccessDocument::VEHICLE_PASS_GIFT => "gift_vp",
    AccessDocument::VEHICLE_PASS_LSD => "lsd_vp",
    AccessDocument::SAP => "sap",
    AccessDocument::SAPSO => "sap"
  }.freeze

  # A selectable export filter. types: matching document types (nil = all);
  # person_statuses: :pnv (Alpha/Prospective holders only), :not_pnv, or nil;
  # combined: { ticket:, vp: } for "must have both" filters whose rows bundle
  # one person's tickets and vehicle passes together.
  Filter = Data.define(:slug, :label, :types, :person_statuses, :combined) do
    def combined? = !combined.nil?

    def exportable? = slug != ALL_FILTER
  end

  # One table/CSV line: a single document, or a person's ticket+VP bundle on a
  # combined filter. column_counts maps TRS request columns to quantities.
  Row = Data.define(:person, :documents, :note, :delivery, :column_counts, :errors) do
    def selectable? = errors.empty?

    # Checkbox value: every document id the row carries.
    def id_param = documents.map(&:id).join(",")

    def cell(key)
      case key
      when "first_name" then person.first_name
      when "last_name" then person.last_name
      when "email" then person.email
      when "project_name" then "Ranger #{person.callsign}"
      when "delivery_type" then delivery
      when "note" then note
      # fetch, not [] -- the combined-row counts hash defaults to 0, and a
      # column the row never touched must export as an empty cell, not "0".
      else column_counts.fetch(key, "")
      end
    end
  end

  # A claimed document carrying validation problems, listed page-wide.
  BadDocument = Data.define(:document, :errors)

  # A posted id that could not be exported or submitted, with the reason.
  Skipped = Data.define(:ref, :reason)

  PNV_STATUSES = [Person::ALPHA, Person::PROSPECTIVE].freeze

  filter = lambda do |slug, label, types: nil, person_statuses: nil, combined: nil|
    Filter.new(slug:, label:, types:, person_statuses:, combined:)
  end

  # The filter dropdown, groups and slugs byte-identical to the Ember page:
  # slugs are written into audit comments and CSV filenames that ticketing
  # compares across years. Note the composite LSD slug is "lsd_vp", the same
  # string as the LSD vehicle pass TRS column -- an upstream quirk, kept.
  FILTER_GROUPS = [
    [nil, [filter.call(ALL_FILTER, "All")]],
    ["Staff Credentials", [
      filter.call("staff_credential", "Staff Credentials",
                  types: [AccessDocument::STAFF_CREDENTIAL]),
      filter.call("staff_credential_vp", "Staff Credentials + Gift VPs (must have both)",
                  types: [AccessDocument::STAFF_CREDENTIAL, AccessDocument::VEHICLE_PASS_GIFT],
                  combined: { ticket: AccessDocument::STAFF_CREDENTIAL, vp: AccessDocument::VEHICLE_PASS_GIFT }),
      filter.call("vehicle_pass_gift", "Gift Vehicle Passes",
                  types: [AccessDocument::VEHICLE_PASS_GIFT])
    ]],
    ["Special Price", [
      filter.call("spt_vp", "SP Tickets + SP VPs (must have both)",
                  types: [AccessDocument::SPT, AccessDocument::VEHICLE_PASS_SP],
                  combined: { ticket: AccessDocument::SPT, vp: AccessDocument::VEHICLE_PASS_SP }),
      filter.call("special_price_ticket", "Special Price Tickets",
                  types: [AccessDocument::SPT]),
      filter.call("vehicle_pass_sp", "SP Vehicle Passes",
                  types: [AccessDocument::VEHICLE_PASS_SP])
    ]],
    ["Setup Access Passes", [
      filter.call("work_access_pass_ranger", "SAP Ranger",
                  types: [AccessDocument::SAP], person_statuses: :not_pnv),
      filter.call("work_access_pass_ranger_plus_so", "SAP Ranger + Significant Other",
                  types: [AccessDocument::SAP, AccessDocument::SAPSO], person_statuses: :not_pnv),
      filter.call("work_access_pass_so", "SAP Significant Other",
                  types: [AccessDocument::SAPSO]),
      filter.call("work_access_pass_pnv", "SAP Prospective / Alpha",
                  types: [AccessDocument::SAP], person_statuses: :pnv),
      filter.call("work_access_pass_all", "SAP All",
                  types: [AccessDocument::SAP, AccessDocument::SAPSO])
    ]],
    ["Other Tickets", [
      filter.call("gift_ticket", "Gift Tickets", types: [AccessDocument::GIFT]),
      filter.call("lsd_ticket", "LSD Tickets", types: [AccessDocument::LSD]),
      filter.call("lsd_vp", "LSD Tickets + LSD VP (must have both)",
                  types: [AccessDocument::LSD, AccessDocument::VEHICLE_PASS_LSD],
                  combined: { ticket: AccessDocument::LSD, vp: AccessDocument::VEHICLE_PASS_LSD }),
      filter.call("vehicle_pass_lsd", "LSD Vehicle Passes",
                  types: [AccessDocument::VEHICLE_PASS_LSD])
    ]]
  ].freeze

  FILTERS = FILTER_GROUPS.flat_map { |_group, filters| filters }.index_by(&:slug).freeze

  # The three TRS spreadsheet formats, transcribed byte-for-byte from the Ember
  # utils/access-document-export module. These headers mirror the vendor's
  # import template: DO NOT reflow, dedupe, or "fix" them -- the literal &amp;,
  # the out-of-order dates (that way since 2022), the double space in
  # "Setup Access Pass  8/15", and the "Method of"/"Method Of" case difference
  # are all load-bearing.
  PAID_AND_GIFT_TICKET_EXPORT_FORMAT = [
    ["First Name", "first_name"],
    ["Last Name", "last_name"],
    ["Email", "email"],
    ["Question: Method Of Delivery:", "delivery_type"],
    ["Question: Nickname/Project:", "project_name"],
    ["Question: Notes:", "note"],
    ["Request: $250 Ticket", "spt"],
    ["Request: $165 Vehicle Pass", "paid_vp"],
    ["Request: Gift Ticket", "not_used_gift_ticket"], # The transferrable gift ticket is used instead
    ["Request: Gift Vehicle Pass", "gift_vp"],
    ["Request: Transferrable $250 Ticket", "spt_xfer"],
    ["Request: Transferrable $165 Vehicle Pass", "vp_xfer"],
    ["Request: Transferrable Gift Ticket", "gift_ticket"],
    ["Request: Transferrable Gift Vehicle Pass", "vehicle_pass_gift"],
    ["Request: Transferrable $75 Vehicle Pass", "discount_vp_xfer"],
    ["Request: $75 Vehicle Pass", "sp_vp"]
  ].freeze

  UNPAID_EXPORT_FORMAT = [
    ["First Name", "first_name"],
    ["Last Name", "last_name"],
    ["Email", "email"],
    ["Question: Method of Delivery:", "delivery_type"],
    ["Question: Nickname/Project:", "project_name"],
    ["Question: Notes:", "note"],
    ["Request: Gift Vehicle Pass", "gift_vp"],
    ["Request: Setup Access Pass 8/26 &amp; Later", "sap_0826"],
    ["Request: Setup Access Pass 8/27 &amp; Later", "sap_0827"],
    ["Request: Setup Access Pass 8/28 &amp; Later", "sap_0828"],
    ["Request: Setup Access Pass 8/29 &amp; Later", "sap_0829"],
    ["Request: Setup Access Pass 8/8 &amp; Later", "sap_0808"],
    ["Request: Setup Access Pass 8/9 &amp; Later", "sap_0809"],
    ["Request: Setup Access Pass 8/10 &amp; Later", "sap_0810"],
    ["Request: Setup Access Pass 8/11 &amp; Later", "sap_0811"],
    ["Request: Setup Access Pass 8/12 &amp; Later", "sap_0812"],
    ["Request: Setup Access Pass 8/13 &amp; Later", "sap_0813"],
    ["Request: Setup Access Pass 8/14 &amp; Later", "sap_0814"],
    ["Request: Setup Access Pass  8/15 &amp; Later", "sap_0815"],
    ["Request: Setup Access Pass 8/16 &amp; Later", "sap_0816"],
    ["Request: Setup Access Pass 8/17 &amp; Later", "sap_0817"],
    ["Request: Setup Access Pass 8/18 &amp; Later", "sap_0818"],
    ["Request: Setup Access Pass 8/19 &amp; Later", "sap_0819"],
    ["Request: Setup Access Pass 8/20 &amp; Later", "sap_0820"],
    ["Request: Setup Access Pass 8/21 &amp; Later", "sap_0821"],
    ["Request: Setup Access Pass 8/22 &amp; Later", "sap_0822"],
    ["Request: Setup Access Pass 8/23 &amp; Later", "sap_0823"],
    ["Request: Setup Access Pass 8/24 &amp; Later", "sap_0824"],
    ["Request: Setup Access Pass 8/25 &amp; Later", "sap_0825"],
    ["Request: Setup Access Pass - Anytime", "sap_anytime"],
    ["Request: Staff Credential Pickup 8/14 &amp; After", "sc_0814"],
    ["Request: Staff Credential Pickup 8/13 &amp; After", "sc_0813"],
    ["Request: Staff Credential Pickup 8/26 &amp; After", "sc_0826"],
    ["Request: Staff Credential Pickup 8/27 &amp; After", "sc_0827"],
    ["Request: Staff Credential Pickup 8/28 &amp; After", "sc_0828"],
    ["Request: Staff Credential Pickup 8/29 &amp; After", "sc_0829"],
    ["Request: Staff Credential Pickup 8/8 &amp; After", "sc_0808"],
    ["Request: Staff Credential Pickup 8/9 &amp; After", "sc_0809"],
    ["Request: Staff Credential Pickup 8/10 &amp; After", "sc_0810"],
    ["Request: Staff Credential Pickup 8/11 &amp; After", "sc_0811"],
    ["Request: Staff Credential Pickup 8/12 &amp; After", "sc_0812"],
    ["Request: Staff Credential Pickup 8/15 &amp; After", "sc_0815"],
    ["Request: Staff Credential Pickup 8/16 &amp; After", "sc_0816"],
    ["Request: Staff Credential Pickup 8/17 &amp; After", "sc_0817"],
    ["Request: Staff Credential Pickup 8/18 &amp; After", "sc_0818"],
    ["Request: Staff Credential Pickup 8/19 &amp; After", "sc_0819"],
    ["Request: Staff Credential Pickup 8/20 &amp; After", "sc_0820"],
    ["Request: Staff Credential Pickup 8/21 &amp; After", "sc_0821"],
    ["Request: Staff Credential Pickup 8/22 &amp; After", "sc_0822"],
    ["Request: Staff Credential Pickup 8/23 &amp; After", "sc_0823"],
    ["Request: Staff Credential Pickup 8/24 &amp; After", "sc_0824"],
    ["Request: Staff Credential Pickup Anytime", "sc_anytime"],
    ["Request: Staff Credential Pickup 8/25 &amp; After", "sc_0825"]
  ].freeze

  LSD_EXPORT_FORMAT = [
    ["First Name", "first_name"],
    ["Last Name", "last_name"],
    ["Email", "email"],
    ["Question: Method Of Delivery:", "delivery_type"],
    ["Question: Nickname/Project:", "project_name"],
    ["Question: Notes:", "note"],
    # Shipping addresses are unused but the vendor template still carries the
    # headers; the cells always export empty.
    ["Shipping Address:: Country", "not_used_country"],
    ["Shipping Address:: Full Name", "not_used_full_name"],
    ["Shipping Address:: Address", "not_used_address1"],
    ["Shipping Address:: Address Line 2", "not_used_address2"],
    ["Shipping Address:: City", "not_used_city"],
    ["Shipping Address:: State", "not_used_state"],
    ["Shipping Address:: Zip", "not_used_zip"],
    ["Shipping Address:: Phone", "not_used_phone"],
    ["Request: $165 Vehicle Pass - Directed", "lsd_vp"],
    ["Request: $550 Ticket - Directed", "lsd"],
    ["Request: $675 Ticket - Directed", "ignore"],
    ["Request: $775 Ticket - Directed", "ignore"],
    ["Request: $975 Ticket - Directed", "ignore"],
    ["Request: $1500 Ticket - Directed", "ignore"],
    ["Request: $3000 Ticket - Directed", "ignore"],
    ["Request: Non-Transferrable $550 Ticket", "ignore"]
  ].freeze

  PAID_FORMAT_FILTERS = %w[special_price_ticket spt_vp vehicle_pass_sp gift_ticket].freeze
  LSD_FORMAT_FILTERS = %w[lsd_ticket lsd_vp vehicle_pass_lsd].freeze

  class << self
    def find_filter(slug)
      FILTERS[slug]
    end

    def all_filter
      FILTERS[ALL_FILTER]
    end

    # Every claimed document visible under the filter, one Row per document
    # (or per person on a combined filter), people ordered by callsign.
    #
    # @return [Hash] :rows -- [Row], :bad_documents -- page-wide [BadDocument]
    def build_rows(filter)
      documents = load_documents
      errors_by_document = errors_for(documents)

      rows = documents.group_by(&:person)
                      .sort_by { |person, _held| person.callsign.to_s.downcase }
                      .flat_map { |person, held| person_rows(filter, person, held, errors_by_document) }

      bad_documents = documents.filter_map do |document|
        BadDocument.new(document:, errors: errors_by_document[document]) if errors_by_document[document].any?
      end

      { rows:, bad_documents: }
    end

    # Re-derive the filter's rows and keep only those whose documents were all
    # posted back. Anything posted that no longer lands in a kept row --
    # no longer claimed, no longer matching the filter, or half of a broken
    # ticket+VP pair -- comes back as Skipped instead.
    #
    # @return [Hash] :rows -- [Row], :skipped -- [Skipped]
    def rows_for_ids(filter, ids)
      posted = ids.to_set
      rows = build_rows(filter)[:rows].select { |row| row.documents.all? { |doc| posted.include?(doc.id) } }
      { rows:, skipped: skipped_for(posted - rows.flat_map { |row| row.documents.map(&:id) }) }
    end

    # Stamp the audit comment on every exported document and build the CSV.
    #
    # @return [Hash] :rows, :skipped, :csv -- CSV text, :filename
    def export!(filter, ids, operator)
      selection = rows_for_ids(filter, ids)
      rows = selection[:rows]

      AccessDocument.transaction do
        rows.flat_map(&:documents).each do |document|
          document.add_comment("exported with filter #{filter.slug}", operator)
          document.save!(validate: false)
        end
      end

      # The vendor-facing note also records who ran the export.
      rows = rows.map { |row| row.with(note: "#{row.note} exported by CHID ##{operator.id}") }

      { rows: rows,
        skipped: selection[:skipped],
        csv: CsvExportConcern.build(csv_rows(filter, rows)),
        filename: "trs-#{filter.slug.tr('_', '-')}-#{Time.current.strftime('%Y-%m-%d-%H-%M')}.csv" }
    end

    # Flip the posted documents from claimed to submitted, mirroring the
    # upstream markSubmitted action: only still-claimed documents change, and
    # a gift vehicle pass rides along with a staff credential when one is in
    # the same batch.
    #
    # @return [Hash] :rows -- [TicketingMaintenance::Row], :skipped -- [Skipped]
    def mark_submitted!(ids)
      documents = AccessDocument.where(id: ids, status: AccessDocument::CLAIMED)
                                .includes(:person)
                                .to_a
                                .sort_by { |doc| [doc.person&.callsign.to_s.downcase, doc.id] }

      # Only credentials inside this batch count, matching upstream.
      sc_person_ids = documents.filter_map { |doc| doc.person_id if doc.type == AccessDocument::STAFF_CREDENTIAL }.to_set

      rows = documents.map do |document|
        delivery = if document.type == AccessDocument::VEHICLE_PASS_GIFT && sc_person_ids.include?(document.person_id)
                     "w/Staff Credential"
                   else
                     document.delivery_method
                   end
        document.additional_comments = "bulk marked submitted\ndelivery #{delivery}"
        document.status = AccessDocument::SUBMITTED
        error = document.save(validate: false) ? nil : document.errors.full_messages.join(" ")

        TicketingMaintenance::Row.new(person: document.person, ref: document.display_ref,
                                      type_label: document.type_label, change: "claimed → submitted",
                                      detail: "delivery #{delivery}", email: nil, error:)
      end

      { rows:, skipped: skipped_for(ids.to_set - documents.map(&:id)) }
    end

    # Header row plus one cell array per Row, in the filter's TRS format.
    def csv_rows(filter, rows)
      format = export_format(filter)
      [format.map(&:first)] + rows.map { |row| format.map { |_header, key| row.cell(key) } }
    end

    def export_format(filter)
      if PAID_FORMAT_FILTERS.include?(filter.slug)
        PAID_AND_GIFT_TICKET_EXPORT_FORMAT
      elsif LSD_FORMAT_FILTERS.include?(filter.slug)
        LSD_EXPORT_FORMAT
      else
        UNPAID_EXPORT_FORMAT
      end
    end

    # The TRS request-column key and note date fragment for one document.
    # The missing leading space on "Anytime" is an upstream quirk, kept so
    # notes stay comparable across years.
    #
    # @return [Array(String, String)] column key, date fragment
    def trs_column_and_date(document)
      base = TRS_COLUMN[document.type]
      return [base, ""] unless AccessDocument::HAS_ACCESS_DATE_TYPES.include?(document.type)

      if document.access_any_time
        ["#{base}_anytime", "Anytime"]
      elsif document.access_date.nil?
        ["#{base}_unspecified", " UNSPECIFIED ACCESS DATE"]
      else
        ["#{base}_#{document.access_date.strftime('%m%d')}", document.access_date.strftime(" %a %m/%-d")]
      end
    end

    # The TRS delivery string for one document -- used by the table and the
    # CSV alike (see the module comment on this deviation).
    #
    # @return [String, nil] nil when a gift ticket has no usable method
    def delivery_for(document)
      case document.type
      when AccessDocument::STAFF_CREDENTIAL
        CREDENTIAL_PICKUP
      when AccessDocument::SAP, AccessDocument::SAPSO
        PRINT_AT_HOME
      when AccessDocument::SPT, AccessDocument::LSD, AccessDocument::VEHICLE_PASS_LSD, AccessDocument::VEHICLE_PASS_SP
        postal_delivery(document.delivery_method)
      when AccessDocument::VEHICLE_PASS_GIFT
        document.delivery_postal? || document.delivery_priority? ? USPS_STANDARD_FOR_GIFT : UPS
      when AccessDocument::GIFT
        case document.delivery_method
        when AccessDocument::DELIVERY_POSTAL then USPS_STANDARD_FOR_GIFT
        when AccessDocument::DELIVERY_PRIORITY then UPS
        when AccessDocument::DELIVERY_WILL_CALL then WILL_CALL
        end
      end
    end

    private

    def load_documents
      AccessDocument.where(status: AccessDocument::CLAIMED)
                    .includes(:person)
                    .order(:source_year, :id)
                    .to_a
                    .reject { |doc| doc.person.nil? || TicketingManagement::EXCLUDED_HOLDER_STATUSES.include?(doc.person.status) }
    end

    # Per-document problem lists: the shared access-date validation plus the
    # delivery rules from upstream's for_delivery payload. A vehicle pass with
    # no delivery method is fine when its holder also has a staff credential
    # (claimed or submitted) -- the pass travels with the credential.
    #
    # @return [Hash{AccessDocument => Array<String>}]
    def errors_for(documents)
      day_low, day_high = TicketingManagement.sap_day_range
      sc_holder_ids = staff_credential_holder_ids(documents)

      documents.index_with do |document|
        errors = []
        problem = TicketingManagement.access_date_problem(document, day_low, day_high)
        errors << problem if problem

        case document.type
        when AccessDocument::SPT
          errors << "missing delivery method" if document.delivery_none?
        when AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::VEHICLE_PASS_SP
          errors << "missing delivery method" if document.delivery_none? && !sc_holder_ids.include?(document.person_id)
        end

        errors
      end
    end

    def staff_credential_holder_ids(documents)
      return Set.new if documents.empty?

      AccessDocument.where(person_id: documents.map(&:person_id).uniq,
                           type: AccessDocument::STAFF_CREDENTIAL,
                           status: [AccessDocument::CLAIMED, AccessDocument::SUBMITTED])
                    .distinct
                    .pluck(:person_id)
                    .to_set
    end

    def person_rows(filter, person, held, errors_by_document)
      return held.map { |doc| document_row(doc, errors_by_document) } if filter.types.nil?
      return combined_rows(filter, person, held, errors_by_document) if filter.combined?

      case filter.person_statuses
      when :pnv then return [] unless PNV_STATUSES.include?(person.status)
      when :not_pnv then return [] if PNV_STATUSES.include?(person.status)
      end

      held.select { |doc| filter.types.include?(doc.type) }
          .map { |doc| document_row(doc, errors_by_document) }
    end

    # A combined filter bundles one person's tickets and vehicle passes into a
    # single row -- and only when they hold at least one of each.
    def combined_rows(filter, person, held, errors_by_document)
      tickets = held.select { |doc| doc.type == filter.combined[:ticket] }
      passes = held.select { |doc| doc.type == filter.combined[:vp] }
      return [] if tickets.empty? || passes.empty?

      documents = tickets + passes
      counts = Hash.new(0)
      documents.each { |doc| counts[trs_column_and_date(doc).first] += 1 }

      delivery = if filter.combined[:ticket] == AccessDocument::STAFF_CREDENTIAL
                   CREDENTIAL_PICKUP
                 else
                   postal_delivery(tickets.first.delivery_method)
                 end

      [Row.new(person:, documents:, note: documents.map { |doc| note_for(doc) }.join("+"),
               delivery:, column_counts: counts,
               errors: documents.flat_map { |doc| errors_by_document[doc] })]
    end

    def document_row(document, errors_by_document)
      column, = trs_column_and_date(document)
      Row.new(person: document.person, documents: [document], note: note_for(document),
              delivery: delivery_for(document), column_counts: { column => 1 },
              errors: errors_by_document[document])
    end

    def note_for(document)
      _column, date_info = trs_column_and_date(document)
      note = "#{NOTE_TYPE_LABELS[document.type]}#{date_info} - #{document.display_ref}"
      note += " - for #{document.name}" if document.type == AccessDocument::SAPSO
      note
    end

    def postal_delivery(delivery_method)
      case delivery_method
      when AccessDocument::DELIVERY_PRIORITY then USPS_PRIORITY
      when AccessDocument::DELIVERY_POSTAL then USPS_STANDARD
      else WILL_CALL
      end
    end

    def skipped_for(missing_ids)
      return [] if missing_ids.empty?

      found = AccessDocument.where(id: missing_ids.to_a).index_by(&:id)
      missing_ids.sort.map do |id|
        document = found[id]
        reason = if document.nil?
                   "no longer exists"
                 elsif document.status != AccessDocument::CLAIMED
                   "status is now #{document.status}"
                 else
                   "not in this filter's current rows"
                 end
        Skipped.new(ref: "RAD-#{id}", reason:)
      end
    end
  end
end
