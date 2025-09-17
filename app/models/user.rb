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
  has_many :client_invitations, class_name: 'ClientInvitation', foreign_key: :owner_id, dependent: :destroy

  after_commit :sync_risk_assistants_client_owned, if: -> { saved_change_to_role? } 

  has_one_attached :logo
  
  has_many :risk_assistants, class_name: 'RiskAssistant', dependent: :destroy
  has_many :field_catalogues, foreign_key: :owner_id, dependent: :destroy  
  has_many :user_field_sets, dependent: :destroy
  has_many :user_field_sections, through: :user_field_sets
  has_many :user_field_definitions, through: :user_field_sections
  has_one :active_user_field_set, -> { active.order(updated_at: :desc) }, class_name: 'UserFieldSet'  
  has_many :policy_analyses, dependent: :destroy

  has_many :client_records, class_name: 'Client', dependent: :destroy

  validates :role, presence: true
  validates :role, inclusion: { in: roles.keys }  
  validates :company_name, presence: true, if: :owner?
  validates :owner, presence: true, if: :client?

  def can_add_client?
    true
  end

  def catalogue_owner
    owner || self
  end

  def active_field_catalogue
    UserFieldSet.active_for_owner(self)
  end

  def active_catalogue_for_clients
    catalogue_owner.active_field_catalogue
  end

  private

  def sync_risk_assistants_client_owned
    risk_assistants.update_all(client_owned: client?)
  end
end
