module Sources
  module Registry
    module_function

    def catalog(source_name)
      case source_name.to_s
      when "github_mcp"
        GithubCatalog.new(kind: :mcp)
      when "github_skill"
        GithubCatalog.new(kind: :skill)
      when "zenn"
        ZennFeedCatalog.new
      when "qiita"
        QiitaCatalog.new
      else
        raise ArgumentError, "Unknown source: #{source_name}"
      end
    end

    def fetch(source_name, limit: ENV.fetch("SOURCE_IMPORT_LIMIT", 10).to_i)
      catalog(source_name).fetch(limit: limit.to_i.clamp(1, 30))
    end
  end
end
