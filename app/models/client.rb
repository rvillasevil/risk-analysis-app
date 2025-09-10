class Client < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(inactive: false) }

  validates :name, presence: true
end