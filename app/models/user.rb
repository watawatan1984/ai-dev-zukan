class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  enum :role, {
    user: 0,
    admin: 1
  }, validate: true

  enum :appearance, {
    system: 0,
    light: 1,
    dark: 2
  }, prefix: true, validate: true

  has_many :oauth_identities, dependent: :destroy
  has_many :admin_audit_logs,
    foreign_key: :actor_id,
    inverse_of: :actor,
    dependent: :restrict_with_exception
  has_many :bookmarks, dependent: :destroy
  has_many :bookmarked_resources, through: :bookmarks, source: :resource
  has_many :hidden_resources, dependent: :destroy
  has_many :hidden_resource_items, through: :hidden_resources, source: :resource

  validates :name, presence: true, length: { maximum: 80 }
end
