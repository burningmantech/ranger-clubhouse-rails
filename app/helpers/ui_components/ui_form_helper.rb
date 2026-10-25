# frozen_string_literal: true

module UiComponents
  # Form Helper
  # The wrapper every page builds its fields through: AppFormBuilder plus the
  # error summary above the form. form_row, form_error_summary and
  # input_counter_data stay in FormHelper, beside the builder.
  module UiFormHelper
    # Creates a styled form with automatic error summary display
    #
    # @param model [ActiveRecord::Base] The form model
    # @param url [String] The form submission URL
    # @param options [Hash] Form options
    # @option options [Boolean] :no_error_summary Skip the error summary at top
    #
    # @example Basic usage
    #   ui_form(@user, users_path) do |f|
    #     f.text_field :name, label: "Name"
    #   end
    #
    def ui_form(model, url, options = {}, &block)
      show_error_summary = !options.delete(:no_error_summary)
      options[:builder] = AppFormBuilder
      options[:model] = model if model
      options[:url] = url

      # Add form controller for error focus management
      options[:data] ||= {}
      options[:data][:controller] = class_names("form", options[:data][:controller])

      errors = if show_error_summary && model.respond_to?(:errors) && model.errors.any?
                 form_error_summary(model)
               else
                 "".html_safe
               end

      safe_join([errors, form_with(**options, &block)])
    end
  end
end
