# frozen_string_literal: true

class Quartermaster::SwagController < ApplicationController
  layout "quartermaster"

  authorize_role [Role::ADMIN, Role::EDIT_SWAG],
                 message: "Admin or Edit Swag role required to manage the swag catalog."

  before_action :set_swag, only: %i[edit update destroy]

  # The Ember page's tabs, in their original order. Every type is listed on the
  # index whether or not it holds anything, so the catalog's shape stays put.
  TYPE_LABELS = {
    Swag::TYPE_DEPT_SHIRT => "Ranger Shirts",
    Swag::TYPE_DEPT_PIN => "Ranger Service Pins",
    Swag::TYPE_DEPT_PATCH => "Ranger Service Patches",
    Swag::TYPE_ORG_PATCH => "Org Service Patches",
    Swag::TYPE_ORG_PIN => "Org Service Pins",
    Swag::TYPE_OTHER => "Other"
  }.freeze

  def index
    counts = Swag.group(:type, :active).count

    @types = TYPE_LABELS.map do |type, label|
      inactive = counts[[type, false]].to_i
      { type:, label:, count: counts[[type, true]].to_i + inactive, inactive: }
    end
    @total_count = counts.values.sum
  end

  def type
    @type = params[:type]

    unless TYPE_LABELS.key?(@type)
      return redirect_to quartermaster_swag_path, error: "That swag type could not be found."
    end

    @type_label = TYPE_LABELS[@type]
    @swags = Swag.find_for_query(type: @type)
    @inactive_count = @swags.count { |swag| !swag.active }
  end

  def new
    requested = params[:type]
    @swag = Swag.new(active: true,
                     type: TYPE_LABELS.key?(requested) ? requested : Swag::TYPE_DEPT_SHIRT)
    load_form_collections
  end

  def create
    @swag = Swag.new(swag_params)

    if @swag.save
      redirect_to swag_anchor_path(@swag), success: "Swag created."
    else
      load_form_collections
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_collections
  end

  def update
    if @swag.update(swag_params)
      redirect_to swag_anchor_path(@swag), success: "Swag updated."
    else
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  # Destroying cascades: the swag's issued records go with it, and any person
  # wearing it as their shirt choice has that choice cleared (see Swag's
  # before_destroy). The edit page warns with the issued count before this runs.
  def destroy
    type = @swag.type
    @swag.destroy!

    redirect_to quartermaster_swag_type_path(type), success: "Swag deleted."
  end

  private

  def set_swag
    @swag = Swag.find(params[:id])
  end

  # A rejected form keeps whatever type was submitted, which may be blank or
  # unknown; the type page's route cannot be built from that, so both the label
  # and the return path fall back to the index.
  def load_form_collections
    @type_options = TYPE_LABELS.invert
    @shirt_type_options = ShirtHelper::SHIRT_TYPE_LABELS.invert
    @issued_count = @swag.person_swag.count
    @type_label = TYPE_LABELS[@swag.type]
    @cancel_path = @type_label ? quartermaster_swag_type_path(@swag.type) : quartermaster_swag_path
  end

  # A type change moves the item to a different page, so the redirect always
  # follows the saved type rather than the one the form was opened from.
  def swag_anchor_path(swag)
    quartermaster_swag_type_path(swag.type, anchor: "swag-#{swag.id}")
  end

  # The shirt type field stays in the DOM while hidden, so its value is dropped
  # whenever the item is not a shirt. Otherwise switching a shirt to a pin would
  # leave a stale "long-sleeve" behind.
  #
  # This belongs on the model as a before_save, the way PersonLanguage and
  # Person clear their own custom fields; it sits here only because Swag is
  # frozen for the translation. Move it when the model reopens.
  def swag_params
    attrs = params.expect(swag: [:title, :active, :type, :shirt_type, :description])
    attrs[:shirt_type] = "" unless attrs[:type] == Swag::TYPE_DEPT_SHIRT
    attrs
  end
end
