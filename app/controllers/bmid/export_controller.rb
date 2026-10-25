# frozen_string_literal: true

# The Eventree export (Ember vc/bmid-print port): review the qualified badges
# for the year, select a batch, download the vendor CSV, and mark everything
# in the batch as submitted. A badge may not exist as a row until this page
# exports it -- EventreeBmidExport re-derives badges from the posted person
# ids and INSERTs the synthesized ones.
#
# The POST renders its results at 422 for the TRS-export reason: Turbo drops a
# 200 form response. Unlike TRS, the download survives the page -- the CSV is
# attached to the BmidExport row and stays re-downloadable from Previous
# Exports.
class Bmid::ExportController < ApplicationController
  # A validated @year: the export writes badges, and an unparseable year would
  # otherwise save them into year 0. See BmidYearConcern.
  include BmidYearConcern

  layout "bmid"

  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # Upstream's error when nothing selected survives the printable gate.
  NOTHING_PRINTABLE = "No prep or ready-to-print status BMIDs found. " \
                      "Previously submitted BMIDs are ignored."

  Skipped = Struct.new(:callsign, :reason)

  def index
    load_review
  end

  def create
    @category_filter = category_filter

    ids = IdList.parse(params.permit(ids: [])[:ids])

    if ids.empty?
      redirect_to bmid_export_path(year: @year, filter: @category_filter),
                  alert: "Select at least one badge to export."
      return
    end

    batch_info = params[:batch_info].to_s.strip.first(BmidExport::BATCH_INFO_LIMIT)
    result = EventreeBmidExport.export!(ids, year: @year, batch_info: batch_info,
                                        exporter: Current.person)

    if result[:exported].empty?
      redirect_to bmid_export_path(year: @year, filter: @category_filter), alert: NOTHING_PRINTABLE
      return
    end

    @export = result[:export]
    @exported = result[:exported]
    @skipped = skipped_entries(result)

    render :create, status: :unprocessable_entity
  end

  # Undo an export batch from the Previous Exports list. Scoped to the current
  # year: a previous year's badges have been through the printer, so those
  # batches stay as they are.
  def unsubmit
    export = BmidExport.for_year(current_year).find_by(id: params[:id])
    if export.nil?
      redirect_to bmid_export_path,
                  alert: "That batch is not available to un-submit. Only the current " \
                         "year's batches can be un-submitted."
      return
    end

    @export = export
    @result = EventreeBmidExport.unsubmit!(export, year: current_year)
    @skipped = unsubmit_skipped_entries(@result)

    render :unsubmit, status: :unprocessable_entity
  end

  private

  def load_review
    @category_filter = category_filter
    @q = params[:q].to_s.strip

    badges = BmidManagement.retrieve_category_to_manage(@category_filter, @year)
    preload_photos(badges)
    partition_badges(badges)
    @rows = text_filtered(@selectable)

    # The hero counts describe the whole category, so they hold still while
    # the text search narrows the table below them.
    @printable_count = @selectable.count(&:print_ready?)
    @no_photo_count = @selectable.count { |badge| !badge.has_approved_photo }
    @unqualified_count = @selectable.count(&:not_qualified_to_print?)

    @previous_exports = BmidExport.for_year(@year)
                                  .includes(:person, csv_file_attachment: :blob)
                                  .order(created_at: :desc, id: :desc)
  end

  # The status buckets the table pulls out, plus the selectable rest. No
  # 'printed' bucket: the upstream client defines one, but the status does not
  # exist in the database and the bucket has always been empty.
  def partition_badges(badges)
    @buckets = Bmid::ExportHelper::BUCKETS.keys.index_with { [] }
    @selectable = []

    badges.each do |badge|
      case badge.status
      when Bmid::DO_NOT_PRINT then @buckets[:do_not_print] << badge
      when Bmid::ISSUES then @buckets[:issues] << badge
      when Bmid::SUBMITTED then @buckets[:submitted] << badge
      else
        if badge.person_status_printable?
          @selectable << badge
        else
          @buckets[:unusual] << badge
        end
      end
    end
  end

  # has_approved_photo reaches through the person to their current photo; the
  # association is loaded once for everyone rather than a query per row --
  # same read, same reason as Bmid::ManageController#preload_photos.
  def preload_photos(badges)
    people = badges.filter_map(&:person)
    return if people.empty?

    ActiveRecord::Associations::Preloader.new(records: people, associations: :photo).call
  end

  # An unknown category means the default rather than an empty page -- same
  # rule as Bmid::ManageController.
  def category_filter
    filter = params[:filter].presence
    BmidManagement::FILTERS.include?(filter) ? filter : BmidManagement::DEFAULT_FILTER
  end

  # Case-insensitive substring over the same fields the manage roster
  # searches. Deliberately not a regular expression: the text comes straight
  # from a URL and a user-supplied pattern is a denial-of-service surface
  # (bmid-manage PRD decision, 2026-07-28).
  def text_filtered(badges)
    return badges if @q.blank?

    needle = @q.downcase
    badges.select do |badge|
      [badge.person&.callsign, badge.title1, badge.title2, badge.title3, badge.team, badge.notes]
        .any? { |value| value.to_s.downcase.include?(needle) }
    end
  end

  # Per-id reasons for everything posted that was not exported: the person no
  # longer exists, their status bars printing, or the badge moved on (most
  # often: already submitted by an earlier batch).
  def skipped_entries(result)
    rejected = result[:rejected].map { |badge| Skipped.new(badge.person.callsign, skip_reason(badge)) }
    missing = result[:missing_ids].map { |id| Skipped.new("Person ##{id}", "no longer exists") }

    rejected + missing
  end

  def skip_reason(badge)
    return "person status is #{badge.person.status}" unless badge.person_status_printable?

    "badge status is #{Bmid::ManageHelper::STATUS_LABELS.fetch(badge.status, badge.status)}"
  end

  # Per-badge reasons an un-submit left something as it was: the badge's row
  # vanished, its status moved on, or another batch owns its submission now.
  def unsubmit_skipped_entries(result)
    moved_on = result[:skipped].map do |badge|
      Skipped.new(badge.person&.callsign || "Person ##{badge.person_id}",
                  unsubmit_skip_reason(badge))
    end
    missing = result[:missing_ids].map do |id|
      Skipped.new("Person ##{id}", "no #{current_year} badge on file any more")
    end

    moved_on + missing
  end

  def unsubmit_skip_reason(badge)
    unless badge.status == Bmid::SUBMITTED
      return "badge status is now #{Bmid::ManageHelper::STATUS_LABELS.fetch(badge.status, badge.status)}"
    end

    badge.batch.present? ? "now submitted under batch \"#{badge.batch}\"" : "now submitted under another batch"
  end
end
