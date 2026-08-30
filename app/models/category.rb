class Category < ApplicationRecord
  has_many :resources, dependent: :nullify # legacy rollback relation
  has_many :resource_categories, dependent: :restrict_with_exception
  has_many :controlled_resources, through: :resource_categories, source: :resource

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
