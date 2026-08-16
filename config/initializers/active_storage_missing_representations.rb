# A missing thumbnail should be a 404, not a 500. Active Storage's
# representation controllers don't rescue anything, so two ordinary production
# situations take the whole request down:
#
#   * The photo is deleted while its thumbnail is being generated. The
#     controller looks up the blob, spends seconds downloading and transforming
#     the image, and by then ActiveStorage::PurgeJob has removed the blob row —
#     so inserting the variant record raises ActiveRecord::InvalidForeignKey
#     (active_storage_variant_records → active_storage_blobs).
#
#   * The blob row exists but its object isn't in the bucket (uploads from an
#     older storage configuration). That surfaces as
#     ActiveStorage::FileNotFoundError, or — because R2 answers HEAD on a
#     missing key in a way the AWS SDK's waiter re-raises rather than reporting
#     as "absent" — a bare Aws::S3::Errors::NotFound.
#
# In every one of these cases the representation genuinely isn't there, so head
# :not_found and let the browser show a broken image instead of erroring.
Rails.application.config.to_prepare do
  missing_representation_errors = [
    ActiveRecord::InvalidForeignKey,  # blob purged mid-transform
    ActiveRecord::RecordNotFound,     # blob purged before the lookup
    ActiveStorage::FileNotFoundError  # blob row without an object behind it
  ]
  # aws-sdk-s3 is loaded lazily along with the storage service, so its error
  # classes can't be referenced here at boot — match them by name instead.
  missing_representation_error_names = %w[
    Aws::S3::Errors::NotFound
    Aws::S3::Errors::NoSuchKey
  ]

  ActiveStorage::Representations::BaseController.rescue_from StandardError do |error|
    missing = missing_representation_errors.any? { |klass| error.is_a?(klass) } ||
      missing_representation_error_names.include?(error.class.name)
    raise error unless missing

    logger.info "Representation unavailable (#{error.class}): #{request.fullpath}"
    head :not_found
  end
end
