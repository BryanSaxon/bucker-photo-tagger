class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :processed_photos, class_name: "Photo", foreign_key: :processed_by_id, dependent: :nullify

  enum :role, { employee: 0, admin: 1 }, default: :employee

  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Short-lived token for the forgot-password flow; long-lived token for admin
  # invitations. Both invalidate automatically once the password is (re)set,
  # because the salt digest they close over changes.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :invitation, expires_in: 14.days do
    password_salt&.last(10)
  end

  # Creates a user with a throwaway password (they set their own via the
  # invitation link) and flags the invite as pending.
  def self.invite!(email_address:, role: :employee)
    create!(
      email_address: email_address,
      role: role,
      password: SecureRandom.base58(24),
      invited_at: Time.current
    )
  end

  # An invited user who hasn't set their own password yet.
  def pending_invite?
    invited_at.present?
  end

  def active?
    deactivated_at.nil?
  end

  def deactivated?
    !active?
  end

  # Block sign-in and end any live sessions immediately.
  def deactivate!
    transaction do
      update!(deactivated_at: Time.current)
      sessions.destroy_all
    end
  end

  def reactivate!
    update!(deactivated_at: nil)
  end

  def display_name
    email_address
  end
end
