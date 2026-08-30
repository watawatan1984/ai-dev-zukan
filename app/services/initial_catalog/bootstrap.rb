module InitialCatalog
  class Bootstrap
    SOURCE_KINDS = {
      "github_mcp" => :mcp,
      "github_skill" => :skill,
      "zenn" => :zenn_article,
      "qiita" => :qiita_article
    }.freeze
    MAX_LIMIT = 100

    Result = Data.define(:target, :enqueued_sources) do
      def complete?
        enqueued_sources.sort == Bootstrap::SOURCE_KINDS.keys.sort
      end
    end

    def self.call(limit: MAX_LIMIT)
      new(limit:).call
    end

    def initialize(limit:)
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      enqueued_sources = SOURCE_KINDS.keys.each do |source_name|
        SourceImportJob.perform_later(source_name, limit:)
      end
      Result.new(target: limit, enqueued_sources:)
    end

    private

    attr_reader :limit
  end
end
