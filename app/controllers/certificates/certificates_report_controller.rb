# frozen_string_literal: true

# Who holds each certification.
#
# Two levels: an index naming every certification and how many people hold it,
# and a roster page per certification carrying the dates and card numbers.
#
# Only people with an active status are counted. Someone who has left keeps
# their certification records, and counting them would overstate who can be
# called on.
class Certificates::CertificatesReportController < ApplicationController
  include CsvExportConcern

  layout "certificates"

  authorize_role [Role::ADMIN, Role::CERTIFICATION_MGMT],
                 message: "Admin or Certification Management role required to view the certificates report."

  # Legal names and email addresses are each held to their own role, so a reader
  # who may see the roster does not automatically see either one.
  before_action :set_visible_columns

  def index
    @certifications = Certification.order(:title).load

    respond_to do |format|
      format.html do
        @holder_counts = listed_holders.group(:certification_id).distinct.count(:person_id)
        @total_records = @holder_counts.values.sum
      end
      format.csv { send_csv(index_csv_rows, filename: "certificates-report.csv") }
    end
  end

  def show
    @certification = Certification.find(params[:id])
    @status_counts = holders.group("person.status").distinct.count(:person_id)
    @total_count = @status_counts.values.sum
    @filter_params = { status: UiComponents::FilterBarHelper.known_filter(params[:status], @status_counts.keys) }
    @records = filtered_holders.load
    @shown_count = @records.map(&:person_id).uniq.size

    respond_to do |format|
      format.html do
        @card_count = holders.where.not(card_number: [nil, ""]).distinct.count(:person_id)
        @missing_card_count = @total_count - @card_count
      end
      format.csv { send_csv(detail_csv_rows, filename: detail_csv_filename) }
    end
  end

  private

  def set_visible_columns
    @show_names = Current.can_view_pii?
    @show_emails = Current.can_view_email?
  end

  # Every certification record belonging to someone still on the roster.
  def active_holders
    PersonCertification.joins(:person).where(person: { status: Person::ACTIVE_STATUSES })
  end

  # Records for the certifications this page actually lists. The table carries no
  # foreign keys, so a record can outlive the certification it names, and those
  # records belong in no column and no count.
  def listed_holders
    active_holders.where(certification_id: @certifications.map(&:id))
  end

  def holders
    active_holders.where(certification_id: @certification.id)
  end

  # Callsign order comes from the database: the collation already ignores case,
  # so "aurora" and "Aurora" sort together. The id breaks ties, so a reader
  # diffing two exports sees only what actually changed.
  def by_callsign(scope)
    scope.includes(:person).order("person.callsign", :id)
  end

  def filtered_holders
    records = by_callsign(holders)
    status = @filter_params[:status]
    return records if status == UiComponents::FilterBarHelper::ALL_FILTER

    records.where(person: { status: })
  end

  def detail_csv_filename
    "certificates-report-#{@certification.title.parameterize.presence || @certification.id}.csv"
  end

  # Who a row is about. Both exports open with these columns, in this order.
  def person_header
    header = ["Callsign", "Status"]
    header << "Name" if @show_names
    header << "Email" if @show_emails
    header
  end

  def person_cells(person)
    cells = [person.callsign, person.status]
    cells << person.desired_full_name if @show_names
    cells << person.email if @show_emails
    cells
  end

  # One row per person, one group of columns per certification, so a reader can
  # sort or pivot the sheet on any certification they like.
  def index_csv_rows
    header = person_header
    @certifications.each do |certification|
      header.push(certification.title, "Card/Certificate #", "Issued On", "Trained On", "Notes")
    end

    rows = [header]
    by_callsign(listed_holders).group_by(&:person_id).each_value do |records|
      # Last one wins where a person holds the same certification twice. The id
      # tiebreaker above makes that the newest record, and the same one every time.
      held = records.index_by(&:certification_id)
      row = person_cells(records.first.person)

      @certifications.each do |certification|
        record = held[certification.id]
        row.push(record ? certification.title : nil,
                 record&.card_number, record&.issued_on, record&.trained_on, record&.notes)
      end
      rows << row
    end
    rows
  end

  # The roster as it is being read, filters and all.
  def detail_csv_rows
    rows = [person_header + ["Issued On", "Trained On", "Card/Certificate #", "Notes"]]
    @records.each do |record|
      rows << person_cells(record.person) +
              [record.issued_on, record.trained_on, record.card_number, record.notes]
    end
    rows
  end
end
