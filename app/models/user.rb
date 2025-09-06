class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :risk_assistants, class_name: 'RiskAssistant', dependent: :destroy
  has_many :policy_analyses, dependent: :destroy
end
