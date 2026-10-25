# frozen_string_literal: true

# How many of each shirt size a group of people needs, per shirt kind.
# (Upstream Ember web/app/utils/shirt-groups-sort.js.) Used by the Alpha
# Schedule's apparel sheet so the quartermaster can count out a shift's boxes.
#
# A person with no size recorded is counted under UNKNOWN rather than dropped:
# an unknown size is still a shirt someone has to hand over.
class ShirtTotals
  UNKNOWN = "Unknown"

  # :param is the kind's key in a query string, so a page filtering by shirt
  # kind does not have to keep its own parallel list of readers.
  KINDS = [
    { name: "T-Shirts", param: :tshirt, reader: :tshirt_swag },
    { name: "T-Shirt Backups", param: :tshirt_secondary, reader: :tshirt_secondary_swag },
    { name: "Long Sleeves", param: :long_sleeve, reader: :long_sleeve_swag }
  ].freeze

  Kind = Data.define(:name, :param, :sizes)
  Size = Data.define(:title, :count)

  # The title a person's shirt of this kind prints as, blank or missing sizes
  # included. Shared with the views so a sheet's rows and its totals can never
  # label the same shirt differently.
  def self.title_for(person, reader)
    person.public_send(reader)&.title.presence || UNKNOWN
  end

  # Whether any of this person's three sizes is missing. Lives here so "missing
  # a size" and the UNKNOWN bucket can only ever mean the same thing.
  def self.missing_any_size?(person)
    KINDS.any? { |kind| title_for(person, kind[:reader]) == UNKNOWN }
  end

  # @param people [Array<Person>]
  # @return [Array<Kind>] one per shirt kind, sizes smallest-first
  def self.for_people(people)
    KINDS.map do |kind|
      counts = people.group_by { |person| title_for(person, kind[:reader]) }
      Kind.new(name: kind[:name], param: kind[:param], sizes: sort_sizes(counts))
    end
  end

  # Ordered the way a quartermaster reads a size run -- XS, S, M, L, XL --
  # using the app's own shirt weights rather than alphabetically, which would
  # print "L, M, S, XL, XS" on a sheet whose whole job is counting boxes.
  # Unknown sorts last: it is a pile to resolve, not a size.
  #
  # Public so every page that lists shirts by title sorts them identically --
  # PotentialShirtsReport's order lines read their run through this too.
  def self.title_sort_key(title)
    name, weight = Swag.shirt_sort_weight(title)
    [title == UNKNOWN ? 1 : 0, name.downcase, weight]
  end

  def self.sort_sizes(counts)
    counts.map { |title, group| Size.new(title:, count: group.size) }
          .sort_by { |size| title_sort_key(size.title) }
  end

  private_class_method :sort_sizes
end
