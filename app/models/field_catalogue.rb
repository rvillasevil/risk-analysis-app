class FieldCatalogue < ApplicationRecord
  STATUSES = %w[draft ready failed].freeze

  belongs_to :owner, class_name: 'User'

  has_many :sections, class_name: 'FieldSection', dependent: :destroy, inverse_of: :catalogue
  has_many :fields, through: :sections, source: :fields
  has_many :messages, class_name: 'FieldCatalogueMessage', dependent: :destroy, inverse_of: :field_catalogue

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(created_at: :desc) }

  def ready!
    update!(status: 'ready')
  end

  def failed!(error)
    data = metadata.presence || {}
    data['last_error'] = error
    update!(status: 'failed', metadata: data)
  end

  def active?
    status == 'ready'
  end

  def ensure_thread!(thread_id)
    update!(thread_id: thread_id) if thread_id.present? && thread_id != self.thread_id
  end

  def to_sections_hash
    sections.includes(:fields).order(:position).each_with_object({}) do |section, hash|
      hash[section.identifier.to_sym] = {
        title: section.title,
        fields: section.fields.order(:position).map(&:to_risk_field_hash)
      }
    end
  end

  def self.active_for(owner)
    return unless owner

    ready.where(owner: owner).order(created_at: :desc).first
  end

  def self.for_owner(owner)
    where(owner: owner).ordered
  end

  scope :ready, -> { where(status: 'ready') }
  scope :draft, -> { where(status: 'draft') }
end