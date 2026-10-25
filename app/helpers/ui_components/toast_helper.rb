# frozen_string_literal: true

# DaisyUI Toast/Notification Helper
# Uses DaisyUI alert component for toast styling
# See: https://daisyui.com/components/toast/
# See: https://daisyui.com/components/alert/
#
module UiComponents
  module ToastHelper
    # Base toast styling utility
    TOAST_BASE = "toast-base"

    # role: a warning or an error interrupts a screen reader ("alert"); the rest
    # wait for it to finish what it is reading ("status").
    # stays: shown until closed. An error is not taken away before it is read.
    TOAST_TYPES = {
      success: { color: :success, icon: :check, type: :solid, role: "status" },
      info: { color: :secondary, icon: "circle-info", type: :solid, role: "status" },
      warning: { color: :warning, icon: :exclamation, type: :solid, role: "alert" },
      # Rails' own flash keys, from redirect_to ... notice: / alert:.
      notice: { color: :success, icon: :check, type: :solid, role: "status" },
      alert: { color: :error, icon: :exclamation, type: :solid, role: "alert", stays: true },
      error: { color: :error, icon: :exclamation, type: :solid, role: "alert", stays: true }
    }.freeze

    # Map colors to utility class names
    TOAST_COLOR_CLASSES = {
      success: "toast-success",
      secondary: "toast-info",
      warning: "toast-warning",
      error: "toast-error"
    }.freeze

    def ui_toast_render(toast_message, toast_type, for_streaming = false)
      type_info = TOAST_TYPES[toast_type.to_sym] || TOAST_TYPES[:info]
      color_class = TOAST_COLOR_CLASSES[type_info[:color]]

      locals = {
        toast_message:,
        attrs: {
          class: "#{TOAST_BASE} #{color_class}",
          role: type_info[:role],
          "data-controller": "toast",
          "data-toast-auto-hide-value": ("false" if type_info[:stays]),
          # Kept out of the copy Back restores, or an error left open would
          # come back with the page it was about.
          "data-turbo-temporary": true
        },
        countdown: !type_info[:stays],
        icon: type_info[:icon],
        icon_type: type_info[:type]
      }

      if for_streaming
        turbo_stream.append "toast-container", partial: "common/toast", locals:
      elsif respond_to?(:render_to_string)
        render_to_string partial: "common/toast", locals:
      elsif respond_to?(:render)
        render partial: "common/toast", locals:
      else
        raise "ui_toast_render being called in a controller context."
      end
    end

    def ui_toast_stream(message, type)
      ui_toast_render(message, type, true)
    end
  end
end
