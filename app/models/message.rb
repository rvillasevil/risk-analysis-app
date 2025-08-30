class Message < ApplicationRecord
  belongs_to :risk_assistant

  validates :sender, presence: true
  validates :content, presence: true
  enum role: {
    user:       "user",
    assistant:  "assistant",
    developer:  "developer"
  }, _suffix: true
  validates :role, inclusion: { in: %w[user assistant developer] }
  validates :key, uniqueness: { scope: :risk_assistant_id }, allow_blank: true

  # "assistant_guard" messages are now visible to users
  INTERNAL_SENDERS = %w[assistant_confirmation assistant_raw assistant_flag assistant_summary].freeze
  
  # Messages that should be displayed to the end user
  scope :visible_to_user, -> { where.not(role: "developer").where.not(sender: INTERNAL_SENDERS) }


  # Saves or updates a message identified by key for the given risk assistant.
  # Existing records with the same key will be overwritten to keep keys unique.
  def self.save_unique!(risk_assistant:, key:, **attrs)
    msg = risk_assistant.messages.find_or_initialize_by(key: key)
    msg.assign_attributes(attrs)
    msg.save!
    msg
  end
end