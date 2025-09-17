class UserFieldSet < ApplicationRecord
  belongs_to :user

  has_many :sections,
           -> { order(:position, :id) },
           class_name: "UserFieldSection",
           dependent: :destroy,
           inverse_of: :user_field_set

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :user, presence: true
  validate :only_one_active_per_user, if: :active?

  after_commit :reset_risk_field_set_cache

  class << self
    def active_for_owner(owner)
      return unless owner

      owner
        .user_field_sets
        .active
        .includes(sections: :field_definitions)
        .order(updated_at: :desc)
        .first
    end
  end

  def deactivate!
    update!(active: false)
  end

  private

  def only_one_active_per_user
    scope = user.user_field_sets.active
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, "Ya existe un catálogo activo para este usuario") if scope.exists?
  end

  def reset_risk_field_set_cache
    RiskFieldSet.reset_cache!(owner: user)
  end
end