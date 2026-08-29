class SeoController < ApplicationController
  def sitemap
    @resources = Resource.publicly_visible.order(updated_at: :desc).limit(50_000)
    expires_in 1.hour, public: true
  end

  def robots
    render plain: <<~ROBOTS
      User-agent: *
      Allow: /
      Disallow: /admin
      Disallow: /my
      Sitemap: #{sitemap_url(format: :xml)}
    ROBOTS
  end
end
