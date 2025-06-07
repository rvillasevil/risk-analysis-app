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
end