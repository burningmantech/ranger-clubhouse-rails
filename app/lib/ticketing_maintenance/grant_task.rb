# frozen_string_literal: true

module TicketingMaintenance
  # Shared creation walk for the three grant tasks. Each new document mirrors
  # the Laravel GrantPasses.grantAccessDocumentToPeople fields, and a commit
  # leaves the same access-document-bulk-grant ActionLog entry upstream does.
  class GrantTask < Base
    private

    # Builds (and on commit saves) one granted document for a person, returning
    # its ledger row. The bare-year expiry expands to Sep 15 via the model's
    # expiry_date= setter. delivery_method is explicit because the type-based
    # before_save default misses the special-price vehicle pass, and the column
    # is NOT NULL.
    def grant_row(person, type:, status:, delivery_method:, access_date: nil, detail: nil)
      document = AccessDocument.new(person:, type:, status:,
                                    source_year: current_year,
                                    expiry_date: current_year,
                                    access_date:, delivery_method:)
      row = save_row(document, change: "new → #{status}",
                     comment: "created via maintenance function",
                     audit_reason: "maintenance - granted #{document.type_label}",
                     detail:)
      @granted << { id: document.id, person_id: person.id } if commit? && row.error.nil?
      row
    end

    # Wraps the task body so each commit records one bulk-grant audit entry per
    # document type, matching upstream.
    def granting(type)
      @granted = []
      rows = yield
      if commit? && @granted.any?
        ActionLog.record(Current.person_id, "access-document-bulk-grant", "bulk grant",
                         { type:, documents: @granted })
      end
      rows
    end
  end
end
