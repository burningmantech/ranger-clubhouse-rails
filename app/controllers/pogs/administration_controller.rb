# frozen_string_literal: true

# Find, correct or delete the pog records of one event year, chosen by the day
# each pog was issued (person_pog.issued_at).
class Pogs::AdministrationController < ApplicationController
  layout "pogs"

  # Not Event Management: it keeps Person › Pogs and the HQ window.
  authorize_role [Role::ADMIN, Role::POG_MANAGEMENT],
                 message: "Admin or Pog Management role required to administer pog records."

  # Pog tracking began with the 2023 event.
  self.year_floor = 2023

  PAGE_SIZE = 100

  before_action :setup_year
  before_action :set_pog, only: %i[edit update destroy]

  helper_method :return_params

  def index
    year_pogs = PersonPog.issued_in(@year)
    @total = year_pogs.count

    # The selects offer only what the year holds. issuer_ids keeps an issuer
    # whose person row is gone, so a filter on them still has an option.
    @issuer_ids = year_pogs.distinct.pluck(:issued_by_id)
    @issuers = Person.basic_info.where(id: @issuer_ids).index_by(&:id)
    @days = year_pogs.distinct.pluck(Arel.sql("DATE(person_pog.issued_at)")).sort
    types_and_statuses = year_pogs.distinct.pluck(:pog, :status)
    @pog_types = PersonPog::POGS & types_and_statuses.map(&:first)
    @statuses = PogFilterForm.status_filters(types_and_statuses.map(&:last))
    @form = PogFilterForm.new(filter_params, issuer_ids: @issuer_ids, days: @days,
                                             pogs: @pog_types, statuses: @statuses)

    matching = @form.apply(year_pogs)
    @meta = page_meta(matching.count, @form.page)
    # Loaded here, so the view's empty? reads the page rather than asking again.
    @pogs = matching.includes(timesheet: :position)
                    .order(issued_at: :desc, id: :desc)
                    .limit(PAGE_SIZE).offset((@meta[:page] - 1) * PAGE_SIZE).to_a
    # The rows show callsigns and nothing else, and person is the widest table
    # in the schema: basic_info for the recipients, and the issuers are loaded.
    @recipients = Person.basic_info.where(id: @pogs.map(&:person_id)).index_by(&:id)
  end

  def edit
  end

  # The audit row comes from PersonPog.audit_model, as on Person › Pogs.
  def update
    if @pog.update(pog_params)
      redirect_to pogs_administration_path(return_params), success: "Pog saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @pog.destroy
    redirect_to pogs_administration_path(return_params), success: "Pog deleted."
  end

  private

  def set_pog
    @pog = PersonPog.find(params.expect(:id))
  end

  def pog_params
    params.expect(person_pog: [:pog, :status, :notes])
  end

  # Where the reader came from: the list's year, filters and page. The list's
  # edit links send it, and the edit page carries it through its form, cancel,
  # back link and delete, so a save or a delete lands back on that page.
  def return_params
    { year: @year, PogFilterForm::PARAM_SCOPE => filter_params.to_h }.compact_blank
  end

  def filter_params
    scoped_params(PogFilterForm::PARAM_SCOPE, *PogFilterForm.attribute_names)
  end

  # A page past the last reads as the last, as RequestLog's pager does.
  def page_meta(total, page)
    total_pages = [(total.to_f / PAGE_SIZE).ceil, 1].max
    { total:, total_pages:, page: page.clamp(1, total_pages) }
  end
end
