# frozen_string_literal: true

# The Eventree export (Laravel App\Lib\EventreeBMIDExport port): turn a set of
# printable badges into the 14-column CSV the badge vendor ingests, mark every
# badge in the batch as submitted, consume the provisions the CSV promised,
# and keep the file on the batch record.
#
# Deliberately not ported: the with_photos ZIP branch. The shipping upstream
# client never requests it, so production exports have been CSV-only.
class EventreeBmidExport
  BUDGET_CODE = "Rangers 660"

  CSV_HEADERS = [
    "First name", "Last name", "Email", "Playa Name", "Position", "Department",
    "Supervisor", "Arrival Date", "Shower Access For Entire Event",
    "Pre-Event Meals", "During Event Meals", "Post Event Meals",
    "Title 2", "Title 3"
  ].freeze

  # Export a batch by person id: re-derive the badges server side (so a stale
  # page cannot smuggle a row past the gate), keep the printable ones, then in
  # one transaction mark every one of them submitted (INSERTing the badges
  # that only existed as synthesized rows), consume their provisions, and
  # record the batch with the file attached.
  #
  # Departed people are deliberately not excluded from the derive -- upstream
  # parity; their person status fails is_printable? and they come back in
  # rejected: instead of silently vanishing from the batch.
  #
  # @param person_ids [Array<Integer>] the posted selection
  # @param year [Integer] the event year, stamped into any-time arrival dates
  # @param batch_info [String]
  # @param exporter [Person]
  # @return [Hash] export: the saved BmidExport (nil when nothing printable),
  #   exported: [Bmid], rejected: [Bmid] that failed is_printable?,
  #   missing_ids: posted ids with no person behind them any more
  def self.export!(person_ids, year:, batch_info:, exporter:)
    badges = Bmid.find_for_person_ids(year, person_ids)
    printable, rejected = badges.partition(&:is_printable?)

    result = { export: nil, exported: printable, rejected: rejected,
               missing_ids: person_ids - badges.map(&:person_id) }
    return result if printable.empty?

    result[:export] = new(printable, year:, batch_info:, exporter:).run!
    result
  end

  # Undo a batch: return every badge the batch submitted to in_prep, return
  # the provisions the batch consumed, and remove the batch record with its
  # CSV. A badge that moved on since the export -- edited on the manage page,
  # or re-exported under another batch -- is left alone and reported.
  #
  # Reverted badges land on in_prep rather than their pre-export status: the
  # batch does not record what that was, and in_prep sends them back through
  # review, which is where an undone batch belongs.
  #
  # @param export [BmidExport]
  # @param year [Integer] the event year the batch's badges live under
  # @return [Hash] reverted: [Bmid] returned to in_prep, skipped: [Bmid] left
  #   untouched, missing_ids: exported person ids with no badge row any more,
  #   provisions_by_person: the returned provisions grouped by person id
  def self.unsubmit!(export, year:)
    badges = Bmid.where(year: year, person_id: export.person_ids).includes(:person).to_a
    reverted, skipped = badges.partition do |badge|
      badge.status == Bmid::SUBMITTED && badge.batch.to_s == export.batch_info.to_s
    end
    provisions = consumed_provisions(export, reverted.map(&:person_id)).group_by(&:person_id)

    ActiveRecord::Base.transaction do
      reverted.each do |badge|
        badge.status = Bmid::IN_PREP
        badge.batch = nil
        badge.append_notes("Un-submitted from print export")
        badge.audit_reason = "un-submitted from print export"
        badge.save!(validate: false)
        Provision.mark_unsubmitted_for_bmid(provisions[badge.person_id] || [])
      end
      export.destroy!
    end

    { reverted: reverted, skipped: skipped,
      missing_ids: export.person_ids - badges.map(&:person_id),
      provisions_by_person: provisions }
  end

  # The provisions this batch consumed: still submitted, carrying the export
  # stamp, and touched no earlier than the batch itself. The time fence keeps
  # a provision submitted by an older export -- same stamp, older touch --
  # from being returned by this one.
  def self.consumed_provisions(export, person_ids)
    Provision.where(person_id: person_ids, status: Provision::SUBMITTED)
             .where("comments LIKE ?", "%#{Provision.sanitize_sql_like(Provision::BMID_EXPORT_COMMENT)}%")
             .where(updated_at: (export.created_at - 1.day)..)
  end
  private_class_method :consumed_provisions

  def initialize(badges, year:, batch_info:, exporter:)
    @badges = badges
    @year = year
    @batch_info = batch_info.to_s
    @exporter = exporter
  end

  def run!
    # Built before anything is written: marking submitted consumes the very
    # provisions the meal and shower columns are derived from.
    csv = build_csv

    # Time.current to the second: this name is the storage key, and Current.time stands still on the training server.
    export = BmidExport.new(person: exporter,
                            batch_info: batch_info,
                            person_ids: badges.map(&:person_id),
                            filename: "ranger-bmids-#{Time.current.strftime('%Y-%m-%d-%H-%M-%S')}.csv")
    export.csv_file.attach(io: StringIO.new(csv), filename: export.filename,
                           content_type: "text/csv")

    ActiveRecord::Base.transaction do
      mark_submitted
      export.save!
    end

    export
  end

  private

  attr_reader :badges, :year, :batch_info, :exporter

  def build_csv
    CsvExportConcern.build([CSV_HEADERS, *badges.map { |badge| csv_row(badge) }])
  end

  # One vendor row. Meals and showers come from the live provisions
  # (meals_granted / showers_granted), not the bmid meals and showers columns
  # -- upstream parity; the columns are stale snapshots nothing prints.
  def csv_row(badge)
    person = badge.person
    meals = badge.meals_granted

    [
      person.first_name,
      person.last_name,
      person.email,
      person.callsign,
      badge.title1 || "",
      BUDGET_CODE,
      "", # Supervisor is not required.
      arrival_date(badge),
      badge.showers_granted ? "Yes" : "No",
      meals&.pre ? "Yes" : "No",
      meals&.event ? "Yes" : "No",
      meals&.post ? "Yes" : "No",
      badge.title2 || "",
      badge.title3 || ""
    ]
  end

  # Upstream hardcodes 07/15 of the wall-clock year for any-time access; the
  # export's own year is used here so a late-run export cannot drift.
  def arrival_date(badge)
    return "07/15/#{year}" if badge.access_any_time
    return "" if badge.access_date.blank?

    badge.access_date.to_time.strftime("%m/%d/%Y")
  end

  # Upstream markSubmitted(): status to submitted, provisions consumed, a note
  # recording what was fed and washed, and the batch stamp. save! INSERTs the
  # synthesized badges -- exporting is what materializes them.
  def mark_submitted
    provisions_by_person = Provision.retrieve_usable_for_person_ids(badges.map(&:person_id))
                                    .group_by(&:person_id)

    badges.each do |badge|
      provisions = provisions_by_person[badge.person_id] || []

      badge.status = Bmid::SUBMITTED
      badge.append_notes("Exported #{consumption_note(provisions)}")
      Provision.mark_submitted_for_bmid(provisions)
      badge.audit_reason = "exported to print"
      badge.batch = batch_info
      badge.save!(validate: false)
    end
  end

  # "[meals all alloc, event earned] [showers alloc]" -- the exact upstream
  # wording, so export notes written by both systems read the same.
  def consumption_note(provisions)
    alloc_meals = {}
    earned_meals = {}
    alloc_showers = false
    earned_showers = false

    provisions.each do |provision|
      case provision.type
      when Provision::WET_SPOT
        provision.is_allocated ? (alloc_showers = true) : (earned_showers = true)
      when Provision::MEALS
        Provision.populate_meal_matrix(provision, provision.is_allocated ? alloc_meals : earned_meals)
      end
    end

    meals = []
    meals << "#{Provision.sort_meals_matrix(alloc_meals)} alloc" if alloc_meals.any?
    meals << "#{Provision.sort_meals_matrix(earned_meals)} earned" if earned_meals.any?
    meals << "none" if meals.empty?

    showers = []
    showers << "alloc" if alloc_showers
    showers << "earned" if earned_showers
    showers << "none" if showers.empty?

    "[meals #{meals.join(', ')}] [showers #{showers.join(', ')}]"
  end
end
