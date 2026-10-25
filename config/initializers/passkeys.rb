# frozen_string_literal: true

# An address no passkey could belong to stops the boot rather than every
# sign-in. After initialize, so the autoloader is up.
Rails.application.config.after_initialize do
  Passkeys.validate!
end
