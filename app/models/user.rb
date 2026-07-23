class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :processed_photos, class_name: "Photo", foreign_key: :processed_by_id, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
