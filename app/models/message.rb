class Message < ApplicationRecord
  belongs_to :risk_assistant

  validates :sender, presence: true
  validates :content, presence: true
  validates :role, inclusion: { in: %w[user assistant] }
end