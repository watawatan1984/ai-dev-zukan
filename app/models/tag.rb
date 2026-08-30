class Tag < ApplicationRecord
  has_many :resource_tags, dependent: :destroy # legacy rollback relation
  has_many :resources, through: :resource_tags # legacy rollback relation
  has_many :controlled_resource_tags, dependent: :restrict_with_exception
  has_many :controlled_resources, through: :controlled_resource_tags, source: :resource
  has_many :tag_aliases, dependent: :destroy

  validates :name, :slug, :normalized_name, presence: true
  validates :slug, :normalized_name, uniqueness: true
end
