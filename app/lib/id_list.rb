# frozen_string_literal: true

# Record ids from a submitted list: checkbox values, or ids[] in a link.
#
# Only whole positive numbers count. to_i reads "abc" as 0 and "7x" as 7, and
# id 0 names nothing: a form that keeps it can say something was chosen and
# then find nothing, or pass a presence check it should fail.
module IdList
  module_function

  # The ids, in the order sent and without repeats. Blanks -- the hidden field
  # a checkbox group sends so that clearing every box still arrives -- and
  # anything else that is not an id are dropped.
  def parse(values) = Array(values).filter_map { |value| id(value) }.uniq

  # An array of nothing but ids and that hidden blank. An editor whose list
  # replaces what is stored asks this first: anything else, read through parse,
  # would come out as "fewer ids" and revoke whatever it stood in for.
  def clean?(values) = values.is_a?(Array) && values.all? { |value| value == "" || id(value) }

  def id(value)
    id = value.to_s[/\A\d+\z/]&.to_i
    id if id&.positive?
  end

  # For forms built on ActiveModel::Attributes. Handed over as an instance, not
  # registered under a name: a registration lives in an initializer, and a
  # server already running never runs one.
  #
  #   attribute :position_ids, IdList::Type.new, default: -> { [] }
  class Type < ActiveModel::Type::Value
    # cast rather than cast_value: Value#cast hands nil back untouched, and a
    # list that was never sent is no ids.
    def cast(value) = IdList.parse(value)
  end
end
