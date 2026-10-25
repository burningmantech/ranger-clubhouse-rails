# frozen_string_literal: true

module OptionsLabels
  def options_to_labels_hash(options)
    options.each_with_object({}) do |option, hash|
      if option.is_a? Array
        hash[option[1]] = option[0]
      else
        hash[option] = option
      end
    end
  end
end
