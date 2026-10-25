# frozen_string_literal: true

# A validation error's message with its field called by another name.
#
# Every message names its own field (config/locales/en.yml), by the model's
# human_attribute_name: "Email can't be blank." A page that labels the field
# differently -- the registration form's "Email address", an application's
# "Approved Handle" -- asks for the message built with its own name rather than
# putting the name in front, which would say it twice.
module ValidationMessage
  def self.naming(error, name)
    # A message added as a string is already written; only a key is built.
    return error.message unless error.raw_type.is_a?(Symbol)

    options = error.options.except(*ActiveModel::Error::CALLBACKS_OPTIONS).merge(attribute: name)
    error.base.errors.generate_message(error.attribute, error.raw_type, options)
  end
end
