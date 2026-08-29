class Category < ApplicationRecord
  has_many :resources, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
