# frozen_string_literal: true

# Swag Distribution: what swag (shirts, service pins and patches, etc.) was
# handed out during an event, one row per person. (Ember
# reports/swag-distribution port.)
#
# Upstream buckets each item in the Ember route; here the categorisation lives
# with the data so the page and the CSV export share one set of rules.
#
# One knowing divergence from upstream: org pins get their own category. The
# Ember switch has no case for the org-pin type, so every org pin -- 9% of all
# items in 2025 -- rendered in "Other" as e.g. "2024-Org Service Pin".
class SwagDistributionReport
  # Category order everywhere: the item lines, the stat boxes, the filter
  # options, and the CSV columns. Upstream's column order, with Org Pins
  # slotted before Other.
  CATEGORIES = %i[tshirts long_sleeves toaster_pins service_pins
                  service_patches org_patches org_pins other].freeze

  # Singular: prefixes each item line on the roster. The two shirt names come
  # from ShirtHelper, which is the one place shirt types are named -- spelling
  # them again here would let this report drift from the swag catalog and a
  # person's swag history.
  CATEGORY_LABELS = {
    tshirts: ShirtHelper::SHIRT_TYPE_LABELS[Swag::SHIRT_T_SHIRT],
    long_sleeves: ShirtHelper::SHIRT_TYPE_LABELS[Swag::SHIRT_LONG_SLEEVE],
    toaster_pins: "Toaster Pin", service_pins: "Service Pin",
    service_patches: "Service Patch", org_patches: "Org Patch",
    org_pins: "Org Pin", other: "Other"
  }.freeze

  # Plural: titles the stat boxes, filter options, and CSV columns.
  CATEGORY_TITLES = {
    tshirts: "#{CATEGORY_LABELS[:tshirts]}s",
    long_sleeves: "#{CATEGORY_LABELS[:long_sleeves]}s",
    toaster_pins: "Toaster Pins", service_pins: "Service Pins",
    service_patches: "Service Patches", org_patches: "Org Patches",
    org_pins: "Org Pins", other: "Other"
  }.freeze

  # person is a Person carrying only what the page reads (see .execute), so
  # callsign_link can still route from it. items keeps every PersonSwag row --
  # the same swag issued twice is two rows on purpose: two shirts really were
  # handed out.
  Row = Data.define(:person, :items, :by_category)

  # @param year [Integer, nil] nil means every year on record
  # @return [Array<Row>] callsign ascending, case-insensitively (upstream's
  #   strcasecmp); items within a row arrive title-sorted from find_for_query
  def self.execute(year)
    items = PersonSwag.find_for_query(year_issued: year)

    # "All" means every year on record, and .years_on_record spells that list
    # without NULL. A row with no year was never attributed to an event, so
    # counting it here -- where no per-year view can ever reach it -- would stop
    # the year totals from summing to the All totals with nothing to explain it.
    items = items.select(&:year_issued) if year.nil?

    # Only the three columns the page reads, rather than every column of a wide
    # PII table: the roster shows a callsign and callsign_link routes on the id.
    people = Person.basic_info.where(id: items.map(&:person_id).uniq).index_by(&:id)

    items.group_by(&:person_id)
         .filter_map { |person_id, person_items|
           # person_swag carries no database foreign keys and the table is
           # shared with the upstream Laravel app, so a row can outlive the
           # person it names. There is nothing to render for one, and taking the
           # whole report down over it is worse than leaving it out.
           person = people[person_id]
           next unless person

           Row.new(person:, items: person_items,
                   by_category: person_items.group_by { |item| categorize(item.swag) })
         }
         .sort_by { |row| row.person.callsign.to_s.downcase }
  end

  # Upstream's bucketing (Ember route setupController), plus the org-pin fix.
  # Toaster pins are a title match, not a type -- that is upstream's rule too.
  #
  # A row whose swag no longer resolves (same missing-foreign-key story as the
  # person above) lands in Other, where .item_title names it as unknown.
  def self.categorize(swag)
    case swag&.type
    when Swag::TYPE_DEPT_SHIRT
      case swag.shirt_type
      when Swag::SHIRT_T_SHIRT then :tshirts
      when Swag::SHIRT_LONG_SLEEVE then :long_sleeves
      else :other
      end
    when Swag::TYPE_DEPT_PIN
      swag.title.to_s.match?(/toaster/i) ? :toaster_pins : :service_pins
    when Swag::TYPE_DEPT_PATCH then :service_patches
    when Swag::TYPE_ORG_PATCH then :org_patches
    when Swag::TYPE_ORG_PIN then :org_pins
    else :other
    end
  end

  # What one issued item is called on the roster and in the export. Matches the
  # person swag page's wording for a row whose swag is gone.
  #
  # @param year [Integer, nil] the page's scope; nil (All) stamps each item with
  #   the year it was issued, without which the same shirt issued at two events
  #   reads exactly like one issued twice at a single event.
  def self.item_title(item, year)
    title = item.swag&.title || "unknown swag #{item.swag_id}"
    year ? title : "#{title} (#{item.year_issued})"
  end

  # The years anyone was handed swag in, ascending. Feeds the year selector, so
  # it is clamped to the window the controller will actually honour: an offered
  # year outside it would fall back to the current year with nothing said.
  #
  # @param range [Range] the accepted years, normally year_floor..current_year
  def self.years_on_record(range)
    PersonSwag.distinct.pluck(:year_issued).compact.select { |year| range.cover?(year) }.sort
  end

  # Items per category across the whole roster, every category present even at
  # zero. Built from the same rows the roster shows, so a stat and the lines it
  # summarises cannot disagree.
  #
  # @param rows [Array<Row>]
  # @return [Hash{Symbol => Integer}] in CATEGORIES order
  def self.category_counts(rows)
    CATEGORIES.index_with { |category|
      rows.sum { |row| row.by_category[category]&.size || 0 }
    }
  end
end
