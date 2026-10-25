# frozen_string_literal: true

# The roll-up shown above a filtered roster: one line per distinct value of
# some attribute, counting the people who hold it and how many of them have
# signed up.
#
# Shared by the Quartermaster roster pages -- Events Rangered groups by years
# of service, Potential Swag by service milestone -- because the :matching
# contract below is subtle and was learned the hard way. It must not live in
# two places and drift.
module RosterRollup
  # @param rows [Array] anything responding to the grouping attribute and to
  #   #signed_up
  # @param attribute [Symbol] what to group by; also the key the line carries
  # @yieldparam row [Object] optional predicate for :matching -- the rows a
  #   line's own link would deliver once the page's other filters are applied.
  #   Without it :matching is just :people.
  #
  #   :people counts everyone on the line; :matching counts the ones a
  #   narrowing control would actually hand over. A control that navigates has
  #   to be labelled with :matching, or it offers "25 years (2)" and then
  #   delivers one person.
  #
  #   Lines are never dropped, even when nothing matches: a line's link is also
  #   what validates the page's filter, so losing it would turn a narrowing
  #   request into a widening one.
  # @return [Array<Hash>] { <attribute>:, people:, signed_up:, matching: },
  #   largest value first
  def self.by(rows, attribute, &matching)
    rows.group_by(&attribute)
        .map { |value, people|
          { attribute => value, people: people.size,
            signed_up: people.count(&:signed_up),
            matching: matching ? people.count(&matching) : people.size }
        }
        .sort_by { |line| -line[attribute] }
  end
end
