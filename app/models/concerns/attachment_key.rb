# frozen_string_literal: true

# Names the file behind an attachment instead of Rails' random token:
#
#   has_one_attached :original
#   attachment_key(:original) { |blob| "photos/#{blob.filename}" }
#
# Declare it after the has_one_attached it keys; anything else raises.
#
# The block runs on the record when a file is attached, with the blob built
# from it: filename, content type, checksum and size are known, but the record
# may not be saved yet, so `id` can be nil. Keys must be unique per blob -- the
# column has a unique index, so a repeat fails the save before anything is
# uploaded -- and must come from trusted values: `blob.filename` interpolates
# sanitized, a raw upload name does not. Blobs that already exist (attached by
# blob or signed id) keep the key they were uploaded under.
module AttachmentKey
  extend ActiveSupport::Concern

  class_methods do
    def attachment_key(*names, &block)
      names.each do |name|
        unless reflect_on_attachment(name)&.macro == :has_one_attached
          raise ArgumentError, "#{self.name}##{name} is not a has_one_attached"
        end

        define_method(:"#{name}=") do |attachable|
          super(attachable)
          change = attachment_changes[name.to_s]
          if change.is_a?(ActiveStorage::Attached::Changes::CreateOne) && change.blob.new_record?
            change.blob.key = instance_exec(change.blob, &block)
          end
        end
      end
    end
  end
end
