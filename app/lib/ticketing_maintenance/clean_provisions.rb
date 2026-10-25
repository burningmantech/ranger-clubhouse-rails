# frozen_string_literal: true

module TicketingMaintenance
  # Post-event provision cleanup for the event year just ended. Run BEFORE
  # Bank Provisions so event radios are handled first. Port of the Laravel
  # ProvisionMaintenance.cleanProvisionsFromPriorEvent.
  #
  # Earned (unallocated) provisions: claimed or submitted ones were consumed
  # and become used. Available ones roll over untouched -- except event radios,
  # which only stay live if the person actually showed up: someone who rangered
  # or checked out a radio consumed theirs, anyone else's expires.
  #
  # Allocated provisions never roll over: consumed ones (claimed, submitted,
  # or the person's BMID was submitted that year) become used, the rest expire.
  class CleanProvisions < Base
    CONSUMED_STATUSES = [Provision::CLAIMED, Provision::SUBMITTED].freeze

    def self.title = "Clean Provisions From Prior Event"

    def self.description
      "Mark consumed provisions as used and expire the rest: earned provisions roll over unless they " \
        "are unused event radios, allocated provisions never roll over. Run BEFORE Bank Provisions."
    end

    def self.earned_scope
      base = Provision.where(is_allocated: false)
      base.where(status: CONSUMED_STATUSES)
          .or(base.where(status: Provision::AVAILABLE, type: Provision::EVENT_RADIO))
    end

    def self.allocated_scope
      Provision.where(is_allocated: true, status: Provision::CURRENT_STATUSES)
    end

    def execute
      sorted(earned_rows + allocated_rows)
    end

    private

    def earned_rows
      rows = self.class.earned_scope.includes(:person).to_a
      radio_holders = rows.filter_map { |p| p.person_id if p.status == Provision::AVAILABLE }.uniq
      load_work_activity(radio_holders)

      rows.map do |provision|
        if provision.status == Provision::AVAILABLE
          clean_available_radio(provision)
        else
          consume(provision, "marked as used via maintenance function")
        end
      end
    end

    # An available event radio was either backed by real attendance or wasted.
    def clean_available_radio(provision)
      # The comment strings written to the record keep upstream's exact wording
      # (the comment trail is shared with the Laravel app); only the on-screen
      # detail is rephrased.
      reasons = []
      details = []
      if @worked_ids.include?(provision.person_id)
        reasons << "person worked"
        details << "rangered that year"
      end
      if @radio_ids.include?(provision.person_id)
        reasons << "checked out radio"
        details << "checked out a radio"
      end

      if reasons.empty?
        status_row(provision, to: Provision::EXPIRED,
                   detail: "did not ranger and did not check out a radio",
                   comment: "was not banked, did not work, and did not check out an event radio. " \
                            "expired via clean provision maintenance function.",
                   audit_reason: "expired via clean maintenance function")
      else
        consume(provision, "marked as used via maintenance function - reason #{reasons.join(', ')}",
                detail: details.join(", "))
      end
    end

    def allocated_rows
      rows = self.class.allocated_scope.includes(:person).to_a
      bmid_ids = Bmid.where(person_id: rows.map(&:person_id).uniq,
                            year: maintenance_year, status: Bmid::SUBMITTED)
                     .distinct.pluck(:person_id).to_set

      rows.map do |provision|
        if bmid_ids.include?(provision.person_id) || CONSUMED_STATUSES.include?(provision.status)
          consume(provision, "marked as used via maintenance function", detail: "allocated, consumed")
        else
          status_row(provision, to: Provision::EXPIRED, detail: "allocated, not consumed",
                     comment: "marked as expired via maintenance function",
                     audit_reason: "marked as expired via maintenance function")
        end
      end
    end

    def consume(provision, reason, detail: nil)
      provision.consumed_year = maintenance_year
      status_row(provision, to: Provision::USED, detail:, comment: reason, audit_reason: reason)
    end

    # One read per activity source for every available-radio holder. Upstream
    # matched radios on the free-text asset description; the canonical marker
    # both codebases use everywhere else is the radio asset type.
    def load_work_activity(person_ids)
      if person_ids.empty?
        @worked_ids = @radio_ids = Set.new
        return
      end

      @worked_ids = Timesheet.where(person_id: person_ids).for_year(maintenance_year)
                             .distinct.pluck(:person_id).to_set
      @radio_ids = PersonAsset.joins(:asset)
                              .where(person_id: person_ids, asset: { type: Asset::TYPE_RADIO })
                              .where_year("checked_out", maintenance_year)
                              .distinct.pluck(:person_id).to_set
    end
  end
end
