# frozen_string_literal: true

class Vc::ReservedHandlesController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC, Role::EDIT_HANDLE_RESERVATIONS],
                 message: "Admin, VC, or Edit Handle Reservations role required to view reserved handles."

  # VC alone gets a read-only view, matching the upstream policy where only
  # Admin and Edit Handle Reservations may change the list.
  authorize_ability :manage_reserved_handles,
                    roles: [Role::EDIT_HANDLE_RESERVATIONS],
                    only: %i[new create edit update destroy expire upload upload_run],
                    deny_to: :vc_reserved_handles_path,
                    message: "Admin or Edit Handle Reservations role required to change reserved handles."

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  before_action :set_reservation, only: %i[edit update destroy]

  def index
    @filter_params = filter_params
    @reservations = HandleReservation.find_for_query(index_query).to_a
    @total_count = HandleReservation.count
    @active_count = HandleReservation.active.count
    @expired_count = @total_count - @active_count
  end

  def new
    # AR seeds reservation_type with the column default, "uncategorized".
    @reservation = HandleReservation.new
  end

  def create
    @reservation = HandleReservation.new(reservation_params)

    if @reservation.save
      redirect_to index_anchor_path(@reservation), success: "Reserved handle created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @reservation.update(reservation_params)
      redirect_to index_anchor_path(@reservation), success: "Reserved handle updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reservation.destroy!

    redirect_to vc_reserved_handles_path, success: "Reserved handle deleted."
  end

  def expire
    expired = HandleReservation.expire_handles!

    if expired.any?
      redirect_to vc_reserved_handles_path,
                  success: "#{expired.size} expired #{"handle".pluralize(expired.size)} deleted."
    else
      redirect_to vc_reserved_handles_path, info: "No handles were found to have expired."
    end
  end

  def upload
    @upload_form = Vc::ReservedHandleUploadForm.new
  end

  def upload_run
    @upload_form = Vc::ReservedHandleUploadForm.new(upload_params)

    return render :upload, status: :unprocessable_entity unless @upload_form.valid?

    @results = HandleReservationUpload.execute(**@upload_form.attributes.symbolize_keys)
    @error_count = @results.count { |row| row[:error] }

    if @upload_form.commit && @error_count.zero?
      redirect_to vc_reserved_handles_path,
                  success: "#{@results.size} reserved #{"handle".pluralize(@results.size)} saved."
    else
      # A partial commit leaves only the lines that still need fixing in the
      # box, so verifying again reports the work that is left rather than
      # re-reporting the rows that were just saved.
      @upload_form.handles = failed_lines.join("\n") if @upload_form.commit

      # Verify results and partial-commit failures re-render on the POST. The
      # 422 is what makes Turbo render the response — it silently drops a 200
      # form response — matching slot copies' preview submit.
      render :upload, status: :unprocessable_entity
    end
  end

  private

  def failed_lines
    @results.filter_map { |row| row[:line] if row[:error] }
  end

  def set_reservation
    @reservation = HandleReservation.find(params[:id])
  end

  def index_anchor_path(reservation)
    vc_reserved_handles_path(anchor: "reserved-handle-#{reservation.id}")
  end

  def filter_params
    { reservation_type: params[:reservation_type].presence || ALL_FILTER,
      status: params[:status].presence || ALL_FILTER }
  end

  def index_query
    query = {}
    query[:reservation_type] = @filter_params[:reservation_type] unless @filter_params[:reservation_type] == ALL_FILTER

    case @filter_params[:status]
    when "active" then query[:active] = 1
    when "expired" then query[:expired] = 1
    end

    query
  end

  def reservation_params
    params.expect(handle_reservation: [:handle, :reservation_type, :expires_on, :twii_year, :reason])
  end

  def upload_params
    scoped_params(:upload, :handles, :reservation_type, :expires_on, :reason, :twii_year, :commit)
  end
end
