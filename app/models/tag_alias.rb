class TagAlias < ApplicationRecord
  belongs_to :tag

  validates :name, :normalized_name, presence: true
  validates :normalized_name, uniqueness: true
end
