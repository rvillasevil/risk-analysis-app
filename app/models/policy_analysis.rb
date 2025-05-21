class PolicyAnalysis < ApplicationRecord
  belongs_to :user
  # pasa de has_one a has_many
  has_many_attached :documents
end
