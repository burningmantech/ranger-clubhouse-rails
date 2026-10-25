class PersonPhoto < ApplicationRecord
  include ActiveModel::Serializers::JSON
  include PhotoRejections

  self.table_name = "person_photo"

  # Shown to user, and used for BMID printing.
  PROFILE_WIDTH = 350
  PROFILE_HEIGHT = 450

  # Shown to everyone else
  AVATAR_WIDTH = 140
  AVATAR_HEIGHT = 180

  belongs_to :person
  belongs_to :review_person, class_name: "Person", optional: true
  belongs_to :upload_person, class_name: "Person", optional: true
  belongs_to :edit_person, class_name: "Person", optional: true

  has_one_attached :original
  has_one_attached :profile
  has_one_attached :avatar

  attachment_key(:original, :profile, :avatar) { |blob| photo_key(blob) }

  REJECTED_DELETE_AFTER = 6.months

  # Don't allow images uploaded images to stick around for long that have not been submitted.
  UPLOAD_DELETE_AFTER = 3.hour

  # Minimum determinant value for matrix inversion (prevents singular matrices)
  MATRIX_DETERMINANT_EPSILON = 1e-10

  # Reasonable bounds for transformation parameters to prevent resource exhaustion
  MAX_SCALE = 10.0
  MIN_SCALE = 0.1
  MAX_TRANSLATION = 10_000.0

  # photo has been approved
  APPROVED = "approved"
  # photo was rejected, will be deleted after REJECTED_DELETE_AFTER. We want the rejected photos
  # to stick around to allow the photo wranglers to see if duplicate photos were
  # submitted, or to identify a bad photo upload pattern.

  REJECTED = "rejected" # photo wranglers rejected the photo
  SUBMITTED = "submitted" # photo has been cropped by the user and is awaiting review

  # photo has been uploaded but has yet to be cropped. The photo will be deleted if it remains
  # in this state for more than UPLOAD_DELETE_AFTER
  UPLOADED = "uploaded"

  ARCHIVED = "archived"

  STATUSES = [APPROVED, ARCHIVED, REJECTED, SUBMITTED, UPLOADED].freeze

  # User does not have a photo on file. Reporting Pseudo status.
  MISSING = "missing"

  class Info
    attr_accessor :photo_status, :photo, :upload_enabled, :rejections, :reject_message

    def initialize(photo_status:, photo:, upload_enabled:, rejections:, reject_message:)
      @photo_status = photo_status
      @photo = photo
      @upload_enabled = upload_enabled
      @rejections = rejections
      @reject_message = reject_message
    end
  end

  MAX_FILE_SIZE = 20.megabytes

  validates :status, presence: true, inclusion: { in: STATUSES }

  # JSON text column; legacy rows hold "{}" (reads as an empty Hash) or an array of reason keys.
  serialize :reject_reasons, coder: JSON

  # Virtual attributes

  # The person's other rejected photos, oldest first. find_for_query preloads
  # a whole page of rows at once; a lone photo loads its own on first use.
  attr_writer :reject_history

  def reject_history
    @reject_history ||= self.class.where(person_id:, status: REJECTED).where.not(id:)
                            .with_attached_avatar.order(:created_at).to_a
  end

  # Set by find_for_query for per-person listings: true when the photo is the
  # person's current photo (the most recent approved one).
  attr_accessor :is_active

  # Scopes
  scope :with_person_tables, -> {
    includes(
      person: Person.basic_info,
      review_person: Person.basic_info,
      upload_person: Person.basic_info,
      edit_person: Person.basic_info
    )
  }

  scope :approved, -> { where(status: PersonPhoto::APPROVED) }
  scope :submitted, -> { where(status: PersonPhoto::SUBMITTED) }
  # The person's current photo is the most recent approved photo.
  scope :current_first, -> { approved.order(created_at: :desc, id: :desc) }

  # Callbacks
  after_save :cleanup_photos

  # Class Methods
  class << self
    def find_for_query(params)
      photo_status = params[:status]
      person_status = params[:person_status]
      person_id = params[:person_id]
      include_rejects = params[:include_rejects]
      sort = params[:sort] || ""

      page = (params[:page] || 1).to_i
      page_size = (params[:page_size] || 100).to_i

      query = joins(:person)
                .includes(:person, :review_person, :upload_person, :edit_person)
                .with_attached_profile
                .with_attached_avatar

      query = query.where(person_id: person_id) if person_id
      query = query.where(status: photo_status) if photo_status
      query = query.where(person: { status: person_status }) if person_status

      total = query.count

      if total.zero?
        return {
          person_photo: [],
          meta: {
            page: page,
            total: 0,
            total_pages: 0
          }
        }
      end

      page = [page - 1, 0].max

      query = query.order("person.callsign": :asc) if sort == "callsign" && person_id.nil?
      query = query.order("person_photo.created_at": :desc)

      rows = query.offset(page * page_size).limit(page_size).to_a

      if person_id
        current_id = current_first.where(person_id: person_id).pick(:id)
        rows.each { |row| row.is_active = row.id == current_id }
        rows = rows.partition(&:is_active).flatten
      end

      if include_rejects
        person_ids = rows.map(&:person_id).uniq
        row_ids = rows.map(&:id)
        rejected_by_person = where(person_id: person_ids)
                               .where.not(id: row_ids)
                               .where(status: REJECTED)
                               .with_attached_avatar
                               .order(:created_at)
                               .group_by(&:person_id)

        rows.each do |row|
          row.reject_history = rejected_by_person[row.person_id] || []
        end
      end

      {
        person_photo: rows,
        meta: {
          total: total,
          total_pages: ((total + page_size - 1) / page_size).to_i,
          page_size: page_size,
          page: page + 1
        }
      }
    end

    def find_all_submitted
      where(status: SUBMITTED).order(:created_at).includes(:person)
    end

    def delete_same_status(person_id, status, photo_id)
      self.where.not(id: photo_id).where(person_id: person_id, status: status).destroy_all
    end

    def delete_pending(person_id, photo_id)
      self.where.not(id: photo_id).where(person_id: person_id, status: [UPLOADED, SUBMITTED]).destroy_all
    end

    def retrieve_info(person)
      photo = person.submitted_photo || person.photo

      status = photo ? photo.status : MISSING
      rejections = []
      reject_message = nil

      if status == REJECTED
        rejections = Array(photo.reject_reasons).map do |reason|
          r = REJECTIONS[reason.to_sym]
          r ? r[:message] : "Reason #{reason}"
        end

        reject_message = photo.reject_message if photo.reject_message.present?
      end

      Info.new(
        photo_status: status,
        photo:,
        upload_enabled: Setting.get_value(Setting::PHOTO_UPLOAD_ENABLE),
        rejections:,
        reject_message:
      )
    end
  end

  # Generate profile and avatar attachments from photo with crop transformations
  # Applies user's cropping transformation matrix to create final profile (350×450) and avatar (140×180) images
  def generate_cropped_attachments!(crop_params, user_id:)
    # Purge the superseded images; their files go in an ActiveStorage::PurgeJob.
    profile.purge_later
    avatar.purge_later

    # Process and attach new images with user's crop transformation
    process_and_generate_images(crop_params, user_id: user_id)

    # Ensure changes are persisted and reload associations
    save! if changed?
    reload

  rescue LoadError => e
    raise StandardError, "Failed to process cropped attachments: #{e.message}"
  end

  # Generate default profile and avatar attachments using center crop
  def generate_default_attachments!(user_id:)
    # Purge the superseded images; their files go in an ActiveStorage::PurgeJob.
    profile.purge_later
    avatar.purge_later

    # Process and attach images with no crop params (uses center crop)
    process_and_generate_images(nil, user_id: user_id)

    # Ensure changes are persisted and reload associations
    save! if changed?
    reload
  rescue LoadError => e
    raise StandardError, "Failed to process default attachments: #{e.message}"
  end

  # Save crop transformation data to original attachment metadata
  # Stores the 2D affine transformation matrix from CropperJS with descriptive keys:
  # {scale_x, skew_x, skew_y, scale_y, translate_x, translate_y}
  def update_crop_data!(crop_params)
    blob = original.blob
    blob.metadata[:crop_data] = crop_params
    blob.save!
  end

  # Check if cropping data exists in original attachment metadata
  def has_cropping_data?
    original.attached? && original.blob.metadata.key?(:crop_data) && original.blob.metadata[:crop_data].present?
  end

  # Retrieve crop transformation data from original attachment metadata
  def crop_data
    original.blob.metadata[:crop_data] if has_cropping_data?
  end

  def is_approved?
    status == APPROVED
  end

  def is_pending?
    status == UPLOADED || status == SUBMITTED
  end

  # Display dimensions (width, height) of the cropped profile image. Legacy
  # imported rows carry the width/height columns; CH3 rows read the attachment
  # metadata. Returns nil when no dimensions are known.
  def profile_dimensions
    return [width, height] if width.to_i.positive? && height.to_i.positive?
    return unless profile.attached?

    w, h = profile.metadata.values_at("width", "height")
    [w, h] if w && h
  end

  def reject_labels
    reasons = reject_reasons
    return nil if reasons.blank?

    reasons.map do |reason|
      reason = reason.to_sym
      REJECTIONS[reason] ? REJECTIONS[reason][:label] : "Reason #{reason}"
    end
  end

  private

  # Memoized bicubic interpolator for performance
  def bicubic_interpolator
    @bicubic_interpolator ||= Vips::Interpolate.new("bicubic")
  end

  # Extract the CropperJS matrix components [a, b, c, d, e, f] from crop params
  def matrix_components(crop_params)
    [
      crop_params[:scale_x]&.to_f || 1.0,
      crop_params[:skew_x]&.to_f || 0.0,
      crop_params[:skew_y]&.to_f || 0.0,
      crop_params[:scale_y]&.to_f || 1.0,
      crop_params[:translate_x]&.to_f || 0.0,
      crop_params[:translate_y]&.to_f || 0.0
    ]
  end

  # Validate transformation parameters to prevent resource exhaustion
  def validate_transformation_params!(params)
    a, b, c, d, e, f = matrix_components(params)

    # Scale along each transformed axis (column norms, rotation-safe)
    scale_x = Math.sqrt(a ** 2 + b ** 2)
    scale_y = Math.sqrt(c ** 2 + d ** 2)

    if scale_x > MAX_SCALE || scale_y > MAX_SCALE
      raise StandardError, "Scale values exceed maximum allowed (#{MAX_SCALE})"
    end

    if scale_x < MIN_SCALE || scale_y < MIN_SCALE
      raise StandardError, "Scale values below minimum allowed (#{MIN_SCALE})"
    end

    if e.abs > MAX_TRANSLATION || f.abs > MAX_TRANSLATION
      raise StandardError, "Translation values exceed maximum allowed (#{MAX_TRANSLATION})"
    end

    if (a * d - b * c).abs < MATRIX_DETERMINANT_EPSILON
      raise StandardError, "Transformation matrix is singular (determinant ≈ 0)"
    end
  end

  # Where a photo file sits in storage: by filename under photos/, the layout
  # Clubhouse 2 used in the same bucket, with the staging server's kept apart.
  def photo_key(blob)
    dir = Current.is_staging? ? "staging/photos" : "photos"
    "#{dir}/#{blob.filename}"
  end

  # Common method to attach a generated image
  def attach_generated_image(attachment_name, temp_path, user_id, type)
    io = File.open(temp_path, "rb")
    send(attachment_name).attach(
      io: io,
      # Time.current: this name is the storage key, and Current.time stands still on the training server.
      filename: "photo-#{user_id}-#{Time.current.to_i}-#{type}.jpg",
      content_type: "image/jpeg"
    )
    io.close
  end

  # Process photo and generate profile and avatar images
  # Yields profile and avatar tempfile paths for attachment
  def process_and_generate_images(crop_params = nil, user_id:)
    require "vips"

    profile_temp = Tempfile.new(["profile", ".jpg"])
    profile_temp.close
    avatar_temp = Tempfile.new(["avatar", ".jpg"])
    avatar_temp.close

    begin
      original.blob.open do |photo_file|
        original_image = Vips::Image.new_from_file(photo_file.path, access: :random, autorotate: false)

        # Generate profile image
        profile_image = if crop_params
                          apply_crop_transformation(original_image, crop_params)
                        else
                          original_image.thumbnail_image(PROFILE_WIDTH, height: PROFILE_HEIGHT, crop: :centre)
                        end
        profile_image.write_to_file(profile_temp.path, Q: 95, strip: true)

        # Generate avatar from profile
        avatar_image = profile_image.thumbnail_image(AVATAR_WIDTH, height: AVATAR_HEIGHT, crop: :centre)
        avatar_image.write_to_file(avatar_temp.path, Q: 95, strip: true)
      end

      # Attach both images
      attach_generated_image(:profile, profile_temp.path, user_id, "profile")
      attach_generated_image(:avatar, avatar_temp.path, user_id, "avatar")
    ensure
      profile_temp&.unlink
      avatar_temp&.unlink
    end
  end

  # Apply crop transformation to create profile-sized image
  #
  # The frontend sends the full CropperJS affine matrix [a, b, c, d, e, f].
  # CropperJS applies it with the transform origin at the center of the
  # natural-size image, so a natural-image point p renders at canvas point
  #   q = L·p + T   with L = [[a, c], [b, d]] and T = center + (e, f) − L·center
  # The canvas is exactly PROFILE_WIDTH×PROFILE_HEIGHT, so rendering that
  # mapping over the canvas area reproduces what the user saw — rotation
  # included — as the final profile image.
  def apply_crop_transformation(original_image, crop_params)
    validate_transformation_params!(crop_params)
    a, b, c, d, e, f = matrix_components(crop_params)

    cx = original_image.width / 2.0
    cy = original_image.height / 2.0
    tx = cx + e - (a * cx + c * cy)
    ty = cy + f - (b * cx + d * cy)

    # Pre-shrink with a proper resampling kernel when downscaling — a bare
    # affine would alias. The affine then applies the residual transform
    # exactly (per-axis k factors account for resize rounding).
    scale = Math.sqrt((a * d - b * c).abs)
    if scale < 1
      source = original_image.resize(scale)
      kx = source.width.to_f / original_image.width
      ky = source.height.to_f / original_image.height
    else
      source = original_image
      kx = ky = 1.0
    end

    # vips matrix order is [row1col1, row1col2, row2col1, row2col2]
    source.affine(
      [a / kx, c / ky, b / kx, d / ky],
      interpolate: bicubic_interpolator,
      oarea: [0, 0, PROFILE_WIDTH, PROFILE_HEIGHT],
      odx: tx,
      ody: ty,
      background: [255.0],
      extend: :background
    )
  end

  # Approving a photo makes it the person's current photo: every other photo
  # they have (prior approved photo, rejected history, pending uploads) is
  # deleted. Rejected photos are otherwise kept so the photo wranglers can
  # track resubmission of the same photo or spot a rejected-submission pattern;
  # pending-photo cleanup during upload/crop is handled by delete_pending.
  def cleanup_photos
    return unless saved_change_to_status? && status == APPROVED

    self.class.where(person_id:).where(status: APPROVED).where.not(id:).update_all(status: ARCHIVED)
  end
end
