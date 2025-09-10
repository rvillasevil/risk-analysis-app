class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { owner: 0, client: 1 }

  MAX_CLIENTS = 20

  def can_add_client?
    clients.count < MAX_CLIENTS
  end  

  after_initialize { self.role ||= :client }  

  belongs_to :owner, class_name: 'User', optional: true
  has_many :clients, class_name: 'User', foreign_key: :owner_id, dependent: :nullify

  has_one_attached :logo
  
  has_many :risk_assistants, class_name: 'RiskAssistant', dependent: :destroy
  has_many :policy_analyses, dependent: :destroy

  has_many :client_records, class_name: 'Client', dependent: :destroy

  validates :role, presence: true
  validates :role, inclusion: { in: roles.keys }  
  validates :company_name, presence: true, if: :owner?
  validates :owner, presence: true, if: :client?

  def can_add_client?
    true
  end
end
