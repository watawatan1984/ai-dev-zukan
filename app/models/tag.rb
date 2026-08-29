class Tag < ApplicationRecord
  has_many :resource_tags, dependent: :destroy
  has_many :resources, through: :resource_tags

  validates :name, :slug, :normalized_name, presence: true
  validates :slug, :normalized_name, uniqueness: true
end
