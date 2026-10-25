# frozen_string_literal: true

module Autocomplete
  # PersonAdapter turns the thin-client search request ({query, mode, limit, filters})
  # into PersonSearch parameters and normalizes the per-field result shape into
  # the unified autocomplete envelope.
  #
  # The person mode is named "person_manage". Any future code that ingests a legacy
  # "account" literal (e.g. a persisted localStorage value) must map it to
  # "person_manage".
  class PersonAdapter
    include Rails.application.routes.url_helpers

    GROUP_TITLES = {
      "callsign" => "Callsign",
      "email" => "Email",
      "fka" => "FKA",
      "id" => "Person Record #",
      "last" => "Last Name",
      "name" => "Real Name",
      "old-email" => "Old Email"
    }.freeze

    # Field-match priority for deduplicating a person who matched several fields.
    # Lowest wins as the row's primary identity; any matched FKA is still merged on.
    FIELD_PRIORITY = {
      "id" => 0,
      "callsign" => 1,
      "name" => 2,
      "last" => 3,
      "fka" => 4,
      "email" => 5,
      "old-email" => 6
    }.freeze

    # Shown when an email search is attempted without email-view permission.
    EMAIL_NO_PERMISSION_TEXT = "You do not have permission to search by email"

    # Shown when a phone search is attempted without permission to read phones.
    PHONE_NO_PERMISSION_TEXT = "You do not have permission to search by phone number"

    # HQ mode restricts to active-like statuses
    HQ_STATUSES = [
      Person::ACTIVE,
      Person::ALPHA,
      Person::INACTIVE,
      Person::INACTIVE_EXTENSION,
      Person::ECHELON,
      Person::PROSPECTIVE
    ].freeze

    attr_reader :query, :mode, :limit, :filters

    def initialize(query:, mode:, limit: 5, filters: {})
      @query = query
      @mode = mode
      @limit = limit
      @filters = filters
    end

    def search
      search_params = build_search_params
      # Email search is gated on the canonical email-view rule
      # (ADMIN/MENTOR/VC/VIEW_EMAIL), not VIEW_PII. Phone search is gated on the
      # rule the person page shows phone numbers under (ADMIN/MENTOR/VC/VIEW_PII).
      can_view_email = Current.can_view_email?

      results = PersonSearch.execute(search_params, can_view_email:, can_view_phone: Current.can_view_pii?)
      transform_results(results)
    end

    private

    def build_search_params
      params = { query: query, limit: }

      case mode
      when "hq"
        params[:statuses] = HQ_STATUSES
        params[:search_fields] = "callsign"
      else
        # person_manage and any unspecified mode use the same default search shape.
        # A status_group filter does NOT narrow the search here: the grouped search
        # always runs across all categories so the chip bar keeps real counts (and
        # zero-empty categories stay suppressed). The selected category is applied as
        # a display filter in transform_status_grouped_results instead.
        params[:search_fields] = "callsign,name,fka"
        params[:status_groups] = true
      end

      params
    end

    def transform_results(results)
      return empty_response(empty_text: empty_text_for_mode) if results.blank?

      first = results.first
      if first.is_a?(Hash) && first.key?(:title) && first.key?(:results)
        transform_status_grouped_results(results)
      else
        transform_flat_results(results)
      end
    end

    def transform_status_grouped_results(status_groups)
      counts_by_key = {}
      items_by_key = {}
      titles_by_key = {}

      status_groups.each do |status_group|
        key = status_group_key(status_group[:title])
        group_items = extract_items_from_field_groups(status_group[:results])

        # Counts cover every category so the chip bar is complete; the rows themselves
        # are cached per-category because only ONE category is shown at a time (below).
        counts_by_key[key] = group_items.size
        items_by_key[key] = group_items
        titles_by_key[key] = status_group[:title]
      end

      # Build the chip bar from every category that has results (zero-match categories
      # dropped), in the canonical STATUS_GROUPS order.
      filter_options = PersonSearch::STATUS_GROUPS.filter_map do |sg|
        key = status_group_key(sg[:title])
        count = counts_by_key[key] || 0
        next if count.zero?

        { value: key, label: sg[:title], active: false, count: }
      end

      # Only ONE status group is shown at a time. Honor the requested chip when it has
      # results; otherwise default to the first non-empty category. The shown category
      # and its chip stay in sync so the bar always reflects what's on screen.
      requested_key = filters.is_a?(Hash) ? filters["status_group"] : nil
      active_key =
        if requested_key.present? && counts_by_key[requested_key].to_i.positive?
          requested_key
        else
          filter_options.first&.dig(:value)
        end
      active_option = filter_options.find { |option| option[:value] == active_key }
      active_option[:active] = true if active_option

      shown = items_by_key[active_key] || []
      group_ids = shown.map { |item| item[:id] }
      groups = group_ids.any? ? [{ key: active_key, title: titles_by_key[active_key], item_ids: group_ids }] : []

      {
        banner: status_group_banner(status_groups),
        filters: [{ key: "status_group", label: "Status", multi: false, options: filter_options }],
        groups:,
        flat_item_ids: group_ids,
        items: shown
      }
    end

    # Banner text:
    # - more than one status category with results -> "Multiple status categories found"
    # - exactly one category with results -> "Showing results for <Category> status(es)"
    def status_group_banner(status_groups)
      return nil if status_groups.blank?

      if status_groups.size > 1
        "Multiple status categories found"
      else
        "Showing results for #{status_groups.first[:title]} status(es)"
      end
    end

    # Context-specific empty-state text. Keyed on the search context the query
    # implies so the message matches what was actually searched (id lookup / email /
    # explicit field-tag / default).
    def empty_text_for_mode
      q = query.to_s.strip

      return "No callsigns matched" if mode == "hq"
      return "No person found with that record number" if q.start_with?("+")

      if q.include?("@")
        return Current.can_view_email? ? "No people matched that email" : EMAIL_NO_PERMISSION_TEXT
      end

      if (match = PersonSearch::FIELD_TAG_REGEXP.match(q))
        return PHONE_NO_PERMISSION_TEXT if match[1].casecmp?(PersonSearch::FIELD_PHONE) && !Current.can_view_pii?

        return "No people matched that #{field_tag_label(match[1])}"
      end

      "No people were found matching callsign, name, or FKA"
    end

    # Human-readable label for an explicit field-tag prefix.
    def field_tag_label(tag)
      {
        "callsign" => "callsign",
        "name" => "name",
        "fka" => "FKA",
        "last" => "last name",
        "phone" => "phone number"
      }[tag.to_s.downcase] || tag.to_s.downcase
    end

    def transform_flat_results(field_groups)
      groups = []
      items = {}
      flat_ids = []

      field_groups.each do |field_group|
        field = field_group[:field]
        people = field_group[:people]
        next if people.blank?

        group_ids = []
        people.each do |person|
          item = person_to_item(person, field)
          items[item[:id]] = item
          group_ids << item[:id]
          flat_ids << item[:id]
        end

        groups << {
          key: field,
          title: GROUP_TITLES[field] || field.titleize,
          item_ids: group_ids
        }
      end

      {
        filters: build_filter_model_for_mode,
        groups:,
        flat_item_ids: flat_ids,
        items: items.values
      }
    end

    # Build the status_group filter model for the current mode.
    # Returns filter definitions so chips remain visible across filtered/unfiltered responses.
    def build_filter_model_for_mode
      # Every mode but hq runs the same status-grouped person search, so they all
      # get the status chip bar; hq searches a fixed status set and has none.
      return [] if mode == "hq"
      # Email searches are status-agnostic (a flat Email/Old Email list), so a status
      # chip bar is meaningless — and previously rendered as countless chips. Suppress it.
      return [] if query.to_s.include?("@")

      active_key = filters.is_a?(Hash) ? filters["status_group"] : nil
      options = PersonSearch::STATUS_GROUPS.map do |sg|
        key = status_group_key(sg[:title])
        {
          value: key,
          label: sg[:title],
          active: active_key.present? ? active_key == key : false
        }
      end

      # If no explicit filter is active, mark the first option as active (default)
      options.first[:active] = true if active_key.blank? && options.any?

      [{ key: "status_group", label: "Status", multi: false, options: }]
    end

    def status_group_key(title)
      title.parameterize(separator: "_")
    end

    # Build one item per person, even when a person matched several fields. The
    # highest-priority field (callsign > name > ...) becomes the row's identity,
    # and any matched FKA is carried onto the survivor so the row still shows its
    # "FKA: ..." line. Preserves first-seen order.
    def extract_items_from_field_groups(field_groups)
      by_id = {}
      order = []

      field_groups.each do |field_group|
        field = field_group[:field]
        field_group[:people]&.each do |person|
          entry = by_id[person.id]

          unless entry
            entry = by_id[person.id] = { person:, field:, fka: nil }
            order << person.id
          end

          if FIELD_PRIORITY.fetch(field, 99) < FIELD_PRIORITY.fetch(entry[:field], 99)
            entry[:person] = person
            entry[:field] = field
          end

          entry[:fka] ||= person.try(:fka_match).presence
        end
      end

      order.map do |id|
        entry = by_id[id]
        merge_fka_match(entry[:person], entry[:fka])
        person_to_item(entry[:person], entry[:field])
      end
    end

    # Set the singleton fka_match accessor on the survivor so _person_item can
    # render the FKA line even when the winning field isn't "fka". Mirrors
    # PersonSearch#annotate_fka_match without touching the Person model.
    def merge_fka_match(person, value)
      return if value.blank?

      person.singleton_class.attr_accessor(:fka_match) unless person.respond_to?(:fka_match)
      person.fka_match = value
    end

    def person_to_item(person, field)
      item_id = "p#{person.id}_#{field}"

      build_item(
        id: item_id,
        value: person.id,
        label: person.callsign,
        html: render_person_html(person, field),
        # Result-click destination: the person manage page.
        url: person_path(person.id),
        meta: {
          id: person.id,
          status: person.status,
          callsign: person.callsign
        }
      )
    end

    def render_person_html(person, field)
      ApplicationController.render(
        partial: "autocomplete/person_item",
        locals: { person:, field: }
      )
    end

    def build_item(id:, value:, label:, html:, meta: {}, url: nil)
      {
        id: id.to_s,
        value: value.to_s,
        label:,
        html:,
        url:,
        meta:
      }
    end

    def empty_response(empty_text: nil)
      {
        empty_text:,
        filters: [],
        groups: [],
        flat_item_ids: [],
        items: []
      }
    end
  end
end
