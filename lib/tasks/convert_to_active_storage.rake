# lib/tasks/convert_person_photos_to_active_storage.rake
# Rake task to convert existing person_photo records to use ActiveStorage
# Run with: rails convert_person_photos_to_active_storage

namespace :photos do
  desc "Convert existing person_photo records to use ActiveStorage"
  task convert_to_active_storage: :environment do
    ActiveRecord::Base.logger = nil
    ActiveJob::Base.logger = nil
    ActiveStorage.logger = nil

    ActiveStorage::Attachment.delete_all
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Blob.delete_all

    photos_directory = "../import-photos" # bmid path as needed

    FileUtils.rm_f Dir.glob("#{Rails.root.join("storage")}/*")

    puts "Starting conversion of person_photos to ActiveStorage..."

    # Configuration
    total_count = PersonPhoto.count
    processed_count = 0
    error_count = 0

    puts "Found #{total_count} person_photo records to convert"
    puts "Looking for photos in: #{photos_directory}"

    errors = []

    # Attach main photo file
    def attach_photo(record, as, filename)
      path = "../import-photos/#{filename}"
      unless File.exist?(path)
        raise "Photo file not found for PersonPhoto ID #{record.id}: #{filename}"
      end

      attachment = record.send(as)
      attachment.attach(
        io: File.open(path),
        filename: filename,
        content_type: "image/jpeg",
      )
      attachment.save!
    end

    PersonPhoto.includes(:person).find_each(batch_size: 500) do |person_photo|
      person = person_photo.person
      puts "Processing ##{person_photo.id} ##{person.id} #{person.callsign}"
      begin
        orig_filename = person_photo.orig_filename
        image_filename = person_photo.image_filename
        profile_filename = person_photo.profile_filename

        # Step 1: Attach original photo (required for variants)
        if orig_filename.present?
          attach_photo(person_photo, :original, orig_filename)
        else
          errors << "Warning: orig_filename blank for PersonPhoto ID #{person_photo.id}"
          next # Skip if no original photo
        end

        # Step 2: Attach profile variant (image_filename = bmid/profile image)
        if image_filename.present?
          attach_photo(person_photo, :profile, image_filename)
        else
          errors << "Warning: image_filename blank for PersonPhoto ID #{person_photo.id}"
        end

        # Step 3: Attach avatar variant (profile_filename = avatar image)
        if profile_filename.present?
          attach_photo(person_photo, :avatar, profile_filename)
        else
          errors << "Warning: profile_filename blank for PersonPhoto ID #{person_photo.id}"
        end

        processed_count += 1

        if processed_count % 100 == 0
          puts "Processed #{processed_count}/#{total_count} records..."
        end

      rescue => e
        errors << "Error processing PersonPhoto ID #{person_photo.id}: #{e.message}"
        error_count += 1
      end
    end

    puts "\nConversion completed!"
    puts "Successfully processed: #{processed_count} records"
    puts "Errors encountered: #{error_count} records"
    puts "Errors #{errors.join("\n")}"

    if error_count > 0
      puts "\nPlease review the errors above and fix any issues before running the column removal migration."
    else
      puts "\nAll records converted successfully. You can now run the column removal migration."
    end
  end

  desc "Verify ActiveStorage conversion"
  task verify_conversion: :environment do
    puts "Verifying ActiveStorage conversion..."

    total_count = PersonPhoto.count
    with_photo = PersonPhoto.joins(:photo_attachment).count

    # Count records with profile variant
    profile_digest = Digest::SHA256.hexdigest("profile-#{PersonPhoto::PROFILE_WIDTH}x#{PersonPhoto::PROFILE_HEIGHT}")
    with_profile = PersonPhoto.joins(:photo_attachment)
                              .joins("INNER JOIN active_storage_variant_records ON active_storage_variant_records.blob_id = active_storage_blobs.id")
                              .where("active_storage_variant_records.variation_digest = ?", profile_digest)
                              .count

    # Count records with avatar variant
    avatar_digest = Digest::SHA256.hexdigest("avatar-#{PersonPhoto::AVATAR_WIDTH}x#{PersonPhoto::AVATAR_HEIGHT}")
    with_avatar = PersonPhoto.joins(:photo_attachment)
                             .joins("INNER JOIN active_storage_variant_records ON active_storage_variant_records.blob_id = active_storage_blobs.id")
                             .where("active_storage_variant_records.variation_digest = ?", avatar_digest)
                             .count

    # Count records with all three (photo + both variants)
    with_all_photos = PersonPhoto.joins(:photo_attachment)
                                 .joins("INNER JOIN active_storage_variant_records profile_var ON profile_var.blob_id = active_storage_blobs.id AND profile_var.variation_digest = '#{profile_digest}'")
                                 .joins("INNER JOIN active_storage_variant_records avatar_var ON avatar_var.blob_id = active_storage_blobs.id AND avatar_var.variation_digest = '#{avatar_digest}'")
                                 .count

    puts "Total PersonPhoto records: #{total_count}"
    puts "With photo attachment: #{with_photo}"
    puts "With profile variant: #{with_profile}"
    puts "With avatar variant: #{with_avatar}"
    puts "With all (photo + both variants): #{with_all_photos}"

    missing_photo = total_count - with_photo
    missing_profile = total_count - with_profile
    missing_avatar = total_count - with_avatar

    if missing_photo > 0 || missing_profile > 0 || missing_avatar > 0
      puts "\nWarning: Some records are missing photos or variants:"
      puts "Missing photo attachment: #{missing_photo}" if missing_photo > 0
      puts "Missing profile variant: #{missing_profile}" if missing_profile > 0
      puts "Missing avatar variant: #{missing_avatar}" if missing_avatar > 0
      puts "Run the conversion task again or check for missing photo files"
    else
      puts "\nAll records have been successfully converted to ActiveStorage with variants!"
    end
  end
end
