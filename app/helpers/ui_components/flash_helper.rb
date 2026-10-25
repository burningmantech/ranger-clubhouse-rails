# frozen_string_literal: true

module UiComponents
  module FlashHelper
    def ui_flash_successful(thing, verb)
      flash[:success] = ui_success_text(thing, verb)
    end

    # Said on the page the rejected form comes back on. flash.now keeps it there
    # and nowhere else -- a plain flash would show again on whatever page the
    # person opened next, attached to nothing they did.
    def ui_flash_submit_error
      flash.now[:error] = "The information could not be saved due to form errors."
    end

    def ui_success_text(thing, verb)
      "#{thing} #{verb}."
    end
  end
end
