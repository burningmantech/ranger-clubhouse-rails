# frozen_string_literal: true

# One badge, edited from the BMID roster and handed back to it.
#
# The roster's Edit column used to link at the person's own badge page
# (/person/:id/bmid). That page belongs to a person, not to an event year: it
# loads and saves Current.year whatever row was clicked, so a prior-year row
# quietly opened -- and saved -- this year's badge. The roster worked around
# that by withholding the link on prior years, which left a whole year of
# badges editable only in Edit Mode.
#
# This editor is the roster's own. It takes the year from the view it was
# opened from, and it round-trips that view -- the category, the five secondary
# filters, the sort, the layout -- so a save returns the admin to the exact row
# they clicked instead of the top of a several-hundred-row table.
class Bmid::BadgesController < ApplicationController
  layout "bmid"

  # The roster's gate, exactly.
  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # A validated @year: this controller writes, and an unparseable one would
  # otherwise save a badge into year 0. See BmidYearConcern.
  include BmidYearConcern

  before_action :load_badge

  # Exactly what the roster's bulk grid may set, and exactly its blank-means-
  # none rule -- borrowed rather than restated, because one badge must not mean
  # two different things depending on which of the two controls saved it.
  #
  # (person_id and year are absent from both: they identify the badge, and a
  # badge that does not exist yet would otherwise be able to write itself onto
  # somebody else's year.)
  BADGE_FIELDS = Bmid::ManageController::ROW_FIELDS
  BLANK_TO_NIL_FIELDS = Bmid::ManageController::BLANK_TO_NIL_FIELDS

  helper_method :badge_return_path

  def edit; end

  # PATCH creates as readily as it updates: the badge is identified by person
  # and year rather than by an id, so there is one address whether or not a row
  # is on file yet. The roster's bulk save works the same way.
  def update
    was_new = @bmid.new_record?
    @bmid.assign_attributes(badge_params)

    if @bmid.save
      redirect_to badge_return_path,
                  success: "Badge #{was_new ? "created" : "updated"} for #{@person.callsign}."
    else
      # Turbo drops a 200 rendered from a PATCH, so the re-render has to say 422.
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # The badge is always loaded through find_for_person_manage, which runs
  # BmidRelationshipLoader. That is what makes the row safe to save:
  # Bmid#after_save pushes the badge's access date out to every changeable SAP
  # and Staff Credential the person holds, so a badge assembled by hand --
  # without its documents loaded -- would blank an arrival date no one touched.
  # Never build a Bmid here.
  def load_badge
    @person = Person.find(params[:person_id])
    @bmid = Bmid.find_for_person_manage(@person.id, @year)
    @ticketing_info = TicketingInfo.new
    @provisions_by_type = usable_provisions
  end

  # What the meals and showers cells offer to manage, keyed by type. The same
  # read the roster's Edit Mode makes, for the same two cells.
  #
  # A person can hold more than one usable pass of a type, and the cell's label
  # is the union of them, so each cell opens the list rather than a record.
  # Ordered by id so the list reads the same way every time, including after a
  # save redraws the cell.
  def usable_provisions
    Provision.retrieve_usable_for_person_ids([@person.id]).order(:id).group_by(&:type)
  end

  # Deliberately no load_provision_package, even though this page now edits
  # provisions. The printer does not read the persisted meals/showers columns --
  # the export emits meals_granted / showers_granted, built from the live
  # provision rows -- and the only remaining reader is the "Specials" category
  # query, so writing them would change which badges the roster lists rather
  # than anything that gets printed. The bulk save does not write them either;
  # one badge must not mean two things depending on which control saved it.
  #
  # (/person/:id/bmid still snapshots them. That is a real disagreement between
  # the two editors of one record, and it is not this page's to settle.)
  def badge_params
    values = params.expect(bmid: [*BADGE_FIELDS])

    # The form renders the SAP control disabled on a badge with no changeable
    # pass, or one whose pass has already gone off to be printed, so a date
    # arriving for one of those did not come from this page. Dropped rather
    # than written, exactly as the roster's bulk save drops it: update_sap
    # would otherwise stamp it onto every other changeable pass the person
    # holds, including banked ones no page ever showed.
    values = values.except(:admission_date) if @bmid.sap_disabled?

    BLANK_TO_NIL_FIELDS.each do |field|
      values[field] = values[field].presence if values.key?(field)
    end

    values
  end

  # The roster this editor was opened from -- same year, category, filters,
  # sort, and layout -- scrolled to the row that was clicked. The roster names
  # every row after its person, which is the only key a badge has before its
  # first save.
  def badge_return_path
    bmid_manage_path(helpers.bmid_view_params(anchor: helpers.bmid_row_dom_id(@bmid)))
  end
end
