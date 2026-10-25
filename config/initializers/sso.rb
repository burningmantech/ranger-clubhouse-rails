# frozen_string_literal: true

# A mode that means nothing, or a client missing its settings, stops the boot
# rather than the first sign-in. After initialize, so the autoloader is up.
Rails.application.config.after_initialize do
  Sso.validate!
end
