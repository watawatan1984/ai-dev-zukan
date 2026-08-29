class ResourceTag < ApplicationRecord
  enum :origin, {
    source: 0,
    ai: 1,
    admin: 2
  }, prefix: true, validate: true

  belongs_to :resource
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :resource_id }
end
