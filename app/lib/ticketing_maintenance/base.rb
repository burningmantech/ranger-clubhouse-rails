# frozen_string_literal: true

module TicketingMaintenance
  # One maintenance task: card metadata for the index page plus the shared
  # selection-and-mutation walk behind its preview and commit.
  #
  # execute(commit: false) is the dress rehearsal the preview page renders;
  # commit: true performs the same walk and saves. Both run the same selection
  # code so the two can never drift (the Vc::MaintenanceController rule).
  #
  # Rows save with validate: false -- legacy rows routinely fail modern
  # validations, and a validation failure here would silently skip a record the
  # operator was just told about -- paired with audit_reason so ActionLog and
  # AccessDocumentChange record why. A save failure lands in the row's error
  # column instead of raising. Every selection matches only rows still awaiting
  # the change, so re-running after a partial failure picks up the remainder.
  class Base
    class << self
      def slug = name.demodulize.underscore.dasherize

      def execute(commit: false, reason: nil) = new(commit:, reason:).execute

      # Help text for the operator-reason field on the preview page; non-nil
      # makes the reason required (bump-expiration).
      def reason_prompt = nil

      def requires_reason? = reason_prompt.present?

      # The expire tasks fill each row's email so operators can notify people;
      # the ledger shows the column whenever rows carry one.
      def show_email? = false

      # Why the task cannot run right now (a blank setting), nil when runnable.
      def blocked_reason = nil

      # Extra fact worth showing on the task's index card (a default date).
      def card_note = nil

      # Distinguishes tasks from link-out cards on the index page.
      def link? = false
    end

    def initialize(commit:, reason: nil)
      @commit = commit
      @reason = reason
    end

    private

    def commit? = @commit

    attr_reader :reason

    def current_year = Current.year

    # The event year post-event tasks clean up after.
    def maintenance_year = @maintenance_year ||= TicketingMaintenance.maintenance_year

    # The standard single-pass task body: load the selection with people,
    # produce one ledger row per record, sort by callsign.
    def walk(scope = self.class.scope, &)
      sorted(scope.includes(:person).map(&))
    end

    # Flip a record's status, producing the "old → new" ledger row. Snapshots
    # the old status itself so no caller can print "banked → banked".
    def status_row(record, to:, comment:, audit_reason:, detail: nil)
      change = "#{record.status} → #{to}"
      record.status = to
      save_row(record, change:, comment:, audit_reason:, detail:)
    end

    # Assigns the audit fields, saves when committing, and returns the ledger
    # row. The caller mutates the record and describes the change first.
    def save_row(record, change:, comment:, audit_reason:, detail: nil)
      error = nil
      if commit?
        record.audit_reason = audit_reason
        record.additional_comments = comment
        error = "could not be saved" unless record.save(validate: false)
      end
      build_row(record, change:, detail:, error:)
    rescue StandardError => e
      build_row(record, change:, detail:, error: e.message)
    end

    # A ledger row for a record the task deliberately leaves alone.
    def skip_row(record, detail:)
      build_row(record, change: "unchanged", detail:)
    end

    def build_row(record, change:, detail: nil, error: nil)
      person = record.person
      Row.new(person:,
              ref: record.persisted? ? record.display_ref : nil,
              type_label: record.type_label,
              change:, detail:,
              email: self.class.show_email? ? person&.email : nil,
              error:)
    end

    # Orphaned records (person row gone) sort last instead of blowing up.
    def sorted(rows) = rows.sort_by { |row| row.person&.callsign&.downcase || "~" }
  end
end
