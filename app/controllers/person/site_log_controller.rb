# frozen_string_literal: true

# When a person was marked on site or off site, and by whom.
class Person::SiteLogController < ApplicationController
  layout "person"

  include PersonConcern

  # Current.has_event_management? (these two Event Management roles) plus
  # Admin, which has_role? does not grant implicitly. Replaces PersonConcern's
  # broader gate.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA],
                 message: "Admin or Event Management permission is required to view the site log."

  def index
    changes = PersonOnSite.where(person: @person)
    # The whole history's counts order the Marked By options and, summed, give
    # the total; the matching counts label them with what each choice shows.
    @creator_counts = changes.creator_counts
    @creators = Person.where(id: @creator_counts.keys.compact).select(:id, :callsign).index_by(&:id)
    @form = PersonOnSiteFilterForm.new(filter_params, creator_ids: @creator_counts.keys)
    @matching_counts = @form.apply_all_but_creator(changes).creator_counts
    @total = @creator_counts.values.sum
    @rows = @form.apply(PersonOnSite.history_for(@person, @form.sort)).to_a
    @durations = PersonOnSite.on_site_durations(@person)
  end

  private

  def filter_params
    scoped_params(PersonOnSiteFilterForm::PARAM_SCOPE, *PersonOnSiteFilterForm.attribute_names)
  end
end
