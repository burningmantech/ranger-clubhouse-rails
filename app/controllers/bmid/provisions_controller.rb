# frozen_string_literal: true

# Provision editing from the BMID manage grid (/bmid/manage?mode=edit) and from
# the single-badge editor (/bmid/manage/badges/:person_id/edit).
#
# The badge and its provisions are one thing to the printer: the export writes
# the meals and shower columns of the same CSV row as the badge's titles
# (upstream EventreeBMIDExport::buildExportRow). They are two records here, so
# the pages that prepare a badge for printing have to offer both.
#
# Meals and showers are read-only ON THE BADGE -- they belong to the person's
# provisions -- so neither page can edit them as fields. Both offer a modal
# instead: the cell's button opens the page's one "modal" turbo-frame, the
# shared provision form saves, and the answer is a turbo_stream that closes the
# dialog and redraws just that person's two cells. Both pages spell the cells
# the same way, so one stream serves them both.
#
# The dialog opens on a list, not on a record. A person may hold more than one
# usable provision of a type -- an earned pass and an allocated one, or an
# earned pass that was banked and came back into play because they also hold an
# allocated one -- and the cell's label is the union of all of them. A dialog
# that jumped into one of those records would edit the wrong pass as often as
# the right one, and would leave the others, and any second pass an admin wanted
# to add, reachable only from the person's own provisions page, which throws
# away every unsaved edit in the grid.
#
# Two properties of that arrangement are deliberate, and the reason this
# controller exists rather than the grid linking out to the person's provisions
# page:
#
#   * A provision change commits immediately and on its own. It is a separate
#     record from the badge, so it must not join the bulk save, and it must not
#     leave the row looking edited: the dialog lives outside the bulk-edit form
#     (an HTML form cannot nest anyway) and the cells it redraws hold no fields,
#     so no input or change event ever reaches the bulk-edit controller. Upstream
#     got this wrong -- editing a provision dirtied the row through its
#     read-only attributes.
#
#   * A provision save never writes the badge. It is tempting to snapshot the
#     bmid.meals / bmid.showers columns here, but the printer does not read
#     them: EventreeBMIDExport emits meals_granted / showers_granted, which the
#     relationship loader builds from the live provision rows at export time.
#     The only thing in this codebase that still reads those columns is
#     BmidManagement.badge_person_ids, the "Specials" category -- so writing
#     them would not change a printed badge, it would silently change which
#     badges the roster lists.
#
# The actions and the form come from ProvisionCrudConcern, shared with the
# person and ticketing provision pages. What is different here is the answer:
# every write responds with turbo_streams instead of a redirect.
class Bmid::ProvisionsController < ApplicationController
  include ProvisionCrudConcern

  # A dialog fetched into the modal frame needs no page around it. Naming a
  # layout here would otherwise replace the minimal one turbo-rails installs for
  # frame requests, and rebuild the whole sidebar on every open -- and leave the
  # response carrying two frames with the same id.
  layout -> { turbo_frame_request? ? "turbo_rails/frame" : "bmid" }

  # The manage page's gate, exactly.
  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # The same validated @year as the roster it opens over, so the URL it falls
  # back to is one the roster would actually go to.
  include BmidYearConcern

  helper_method :provision_person, :provision_context, :provision_type

  # The two cells the grid draws. A dialog is always opened from one of them,
  # so anything else in the URL was typed by hand and gets the meals list --
  # the same fallback the concern's new action makes for an unknown type.
  CELL_TYPES = [Provision::MEALS, Provision::WET_SPOT].freeze

  # The dialog's first step: everything the cell's label is describing, so an
  # admin can pick the pass they meant. Only the cell's own type is listed --
  # the button was pressed on either meals or showers, and the other cell has
  # its own.
  def index
    @provisions = usable_provisions.select { |provision| provision.type == provision_type }
  end

  # new and edit come straight from the concern: both simply render this
  # controller's template, which is the dialog wrapped in the page's modal
  # frame.

  def create
    @provision = Provision.new(provision_params)
    @provision.person_id = provision_person.id

    if @provision.save
      provision_saved("Added #{@provision.type_label} for #{provision_person.callsign}.")
    else
      # Back into the frame the form was submitted from, so the dialog stays
      # open holding what was typed. Turbo drops a 200 render of a failed
      # submission, hence the 422.
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @provision.update(provision_params)
      provision_saved("Updated #{@provision.type_label} for #{provision_person.callsign}.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    label = @provision.type_label
    @provision.destroy!
    provision_saved("Deleted #{label} for #{provision_person.callsign}.")
  end

  private

  # --- the person and the record -------------------------------------------

  # The row the modal was opened from. Every link into this controller carries
  # it, so a provision is only ever reachable through the person who holds it.
  # A request with no person_id fails closed rather than falling back to the
  # record's own owner.
  def provision_person
    @provision_person ||= Person.find(params[:person_id])
  end

  # Scoped to the person in the request, so a provision belonging to somebody
  # else 404s rather than being quietly edited from this page.
  def find_provision
    Provision.find_for_person(provision_person.id, params[:id])
  end

  # Which cell the dialog was opened from.
  def provision_type
    type = params[:type]

    CELL_TYPES.include?(type) ? type : Provision::MEALS
  end

  # --- responses ------------------------------------------------------------

  # Close the dialog, redraw the person's two provision cells from a fresh
  # package, and say what happened. Only that one person is recomputed: the
  # grid behind the dialog is holding unsaved edits, and reloading it would
  # throw them away.
  def provision_saved(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: provision_streams(message) }
      # No Turbo (or no JavaScript): fall back to the page the modal was opened
      # from. Only the year and the category survive -- the secondary filters
      # are not worth carrying on every one of a thousand cell links.
      format.html { redirect_to provision_return_path, success: message }
    end
  end

  def provision_streams(message)
    provisions = usable_provisions
    badge = badge_row(Provision.build_package(provisions))

    [
      turbo_stream.update("modal", ""),
      cell_stream("showers_cell", helpers.bmid_showers_cell_id(badge), badge,
                  provisions.select { |provision| provision.type == Provision::WET_SPOT }),
      cell_stream("meals_cell", helpers.bmid_meals_cell_id(badge), badge,
                  provisions.select { |provision| provision.type == Provision::MEALS }),
      ui_toast_stream(message, :success)
    ]
  end

  def cell_stream(partial, dom_id, badge, provisions)
    turbo_stream.replace(dom_id, partial: "bmid/manage/#{partial}",
                                 locals: { bmid: badge, provisions:, editable: true })
  end

  # Ordered so the list reads the same way every time it is opened.
  def usable_provisions
    Provision.retrieve_usable_for_person_ids([provision_person.id]).order(:id).to_a
  end

  # The row the two cells are drawn from. Deliberately a fresh unsaved badge
  # rather than the one on file: the cells read nothing but the person id and
  # the three provision-derived virtuals, and a record that was never loaded
  # cannot be written back by accident.
  def badge_row(package)
    badge = Bmid.new(person_id: provision_person.id, year: @year)
    # Already in hand, so the cell's button label does not go looking for it.
    badge.person = provision_person
    badge.meals_granted = package.meals
    badge.showers_granted = package.showers
    badge.have_allocated_provisions = package.have_allocated
    badge
  end

  # --- ProvisionCrudConcern hooks -------------------------------------------

  # The person and the view identity ride along so a validation failure re-posts
  # to the same place and the no-Turbo redirect lands back on the same roster.
  def provision_context
    context = { person_id: provision_person.id, year: @year, filter: manage_filter }
    context[:from] = Bmid::ManageHelper::BADGE_ORIGIN if from_badge_editor?
    context
  end

  def provision_form_path(provision)
    if provision.new_record?
      bmid_provisions_path(provision_context)
    else
      bmid_provision_path(provision, provision_context)
    end
  end

  # Where a save lands when Turbo is not doing the work. The cell's buttons are
  # ordinary links, so "open in new tab" and a middle-click both reach the
  # dialog as a plain page, and then this is the only way back.
  def provision_return_path
    if from_badge_editor?
      edit_bmid_badge_path(person_id: provision_person.id, year: @year, filter: manage_filter)
    else
      bmid_manage_path(year: @year, filter: manage_filter,
                       mode: Bmid::ManageController::EDIT_MODE)
    end
  end

  def from_badge_editor?
    params[:from] == Bmid::ManageHelper::BADGE_ORIGIN
  end

  def provision_return_label
    from_badge_editor? ? "#{provision_person.callsign}'s BMID" : "BMID Management"
  end

  # An unknown category means the default one, the same way the manage page
  # reads it -- a hand-edited URL cannot send the fallback redirect somewhere
  # the page would not go on its own.
  def manage_filter
    filter = params[:filter].presence
    BmidManagement::FILTERS.include?(filter) ? filter : BmidManagement::DEFAULT_FILTER
  end
end
