class SkuSync < ApplicationRecord
  enum :status, { running: 0, completed: 1, failed: 2 }, default: :running

  scope :recent, -> { order(created_at: :desc) }

  # The most recent sync attempt, used to show status in the UI.
  def self.latest
    recent.first
  end

  # Is a sync currently in progress? (Prevents overlapping manual triggers.)
  def self.in_progress?
    running.exists?
  end

  def mark_completed!(count)
    update!(status: :completed, synced_count: count, finished_at: Time.current)
  end

  def mark_failed!(error)
    update!(status: :failed, error_message: error.to_s, finished_at: Time.current)
  end

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end
end
