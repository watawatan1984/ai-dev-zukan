# Controlled Taxonomy and Faceted Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the uncontrolled single-category taxonomy with a controlled multi-category vocabulary, reclassify all 400 public resources without mutating approved revisions, and deliver understandable OR-within/AND-between faceted search on desktop and mobile.

**Architecture:** Keep the existing Rails SSR/Hotwire application and additive PostgreSQL migration strategy. Introduce a YAML-backed baseline taxonomy, database-backed audited runtime tag vocabulary, many-to-many resource categories, canonical tag aliases, a separate NVIDIA taxonomizer, normalized search selection and facet-count services, and a guarded reclassification release workflow. Preserve `resources.category_id`, old tag rows, current URLs, and current approved revisions as rollback data.

**Tech Stack:** Ruby on Rails 8, PostgreSQL/Supabase, Solid Queue, Hotwire/Stimulus, Tailwind CSS, NVIDIA NIM API, Minitest, Capybara/Selenium, Docker Compose, Render.

**Spec:** [`docs/superpowers/specs/2026-08-30-taxonomy-faceted-search-design.md`](../specs/2026-08-30-taxonomy-faceted-search-design.md)

## Global Constraints

- Do not change `Resource.kind` enum values or public resource URLs.
- Do not delete or rewrite `resources.category_id`, legacy `resource_tags` joins, legacy `Category`/`Tag` rows, or approved `ResourceRevision` rows in this release.
- Do not let AI, imports, or revision approval create categories or tags dynamically.
- Keep the 14 categories fixed in `config/taxonomy.yml`. Seed initial tags from YAML, then treat active database tags and aliases as the runtime allowlist so audited admin tag additions work without a deploy.
- Use the 14 approved category slugs exactly as written in the spec.
- A publishable classification has 1–3 controlled categories and 2–6 controlled canonical tags.
- Same-facet values use OR; different facets use AND. `MCP + Blog + Zenn` means `MCP OR (Blog AND Zenn)`.
- Keep source collection and AI summarization behavior unchanged; taxonomy generation is a separate operation.
- Do not add a front-end or Ruby dependency. Use existing Rails, Stimulus, Tailwind, and test tooling.
- Use `apply_patch` for source edits. Do not stage `.chatgpt/` browser artifacts.
- Run all Ruby/Rails checks through Docker because host Ruby is not part of the supported development path.
- Stop after local verification and a production dry-run report. Applying the production migration, reclassification, publication, Git push, or Render deployment requires a separate explicit production approval.

---

## File and Responsibility Map

### New files

| File | Responsibility |
|---|---|
| `config/taxonomy.yml` | Fixed category definitions and baseline tag, alias, group, filterability, and order definitions |
| `db/migrate/20260830150000_create_controlled_taxonomy.rb` | Add `resource_categories`, `controlled_resource_tags`, `tag_aliases`, tag governance columns, and revision taxonomy columns |
| `app/models/resource_category.rb` | Many-to-many category assignment with origin provenance |
| `app/models/controlled_resource_tag.rb` | Taxonomy-v2 tag assignment kept separate from legacy `resource_tags` |
| `app/models/tag_alias.rb` | One normalized alias to one canonical tag |
| `app/services/taxonomy/registry.rb` | Read and validate `config/taxonomy.yml`; resolve canonical slugs and aliases |
| `app/services/taxonomy/sync_vocabulary.rb` | Idempotently upsert controlled vocabulary and deactivate non-controlled entries without deleting them |
| `app/services/taxonomy/validate_suggestion.rb` | Enforce category/tag counts and allowed canonical slugs |
| `app/services/search/index_text.rb` | Build searchable text independently from display taxonomy mutation |
| `app/integrations/ai/taxonomy_suggestion.rb` | Typed classification result object |
| `app/integrations/ai/nvidia_taxonomizer.rb` | Request constrained classifications from NVIDIA without regenerating summaries |
| `app/services/taxonomy/generate_suggestion.rb` | Claim and persist taxonomy generation lifecycle/provenance |
| `app/jobs/classify_revision_job.rb` | Solid Queue wrapper for classification |
| `app/services/taxonomy/build_reclassification_candidate.rb` | Clone immutable approved revisions into taxonomy-v2 draft revisions |
| `app/services/taxonomy/enqueue_reclassification.rb` | Idempotently create/enqueue candidates for the public catalog |
| `app/services/taxonomy/quality_report.rb` | Verify counts, unknown values, duplicates, low confidence, and review sample score |
| `app/services/taxonomy/export_review_sample.rb` | Produce deterministic 20-per-kind review artifact |
| `app/services/taxonomy/publish_reclassification.rb` | Explicitly confirmed, idempotent taxonomy-v2 publication |
| `app/services/search/selection.rb` | Normalize, validate, cap, and canonicalize public search parameters |
| `app/services/search/facet_counts.rb` | Calculate candidate counts while excluding only the counted facet |
| `app/views/resources/_filter_panel.html.erb` | Accessible multi-select filters for desktop and mobile |
| `app/views/resources/_active_filters.html.erb` | Applied filter chips, individual removal, and clear-all links |
| `app/views/resources/_selection_hidden_fields.html.erb` | Preserve normalized GET search state across forms and removal links |
| `app/views/resources/_taxonomy_badges.html.erb` | Explain category/tag matches on result cards |
| `app/javascript/controllers/facet_filter_controller.js` | Mobile sheet, source visibility, Escape handling, and local tag search |
| `app/controllers/admin/taxonomy_controller.rb` | Controlled taxonomy overview and usage counts |
| `app/controllers/admin/tags_controller.rb` | Create controlled tags and merge aliases through audited services |
| `app/services/taxonomy/create_tag.rb` | Validate, audit, and add a controlled tag to the runtime database allowlist |
| `app/services/taxonomy/merge_tag.rb` | Move joins/aliases, add source alias, deactivate source, and audit without deletion |
| `app/views/admin/taxonomy/index.html.erb` | Vocabulary, aliases, visibility, group, and usage review UI |
| `test/models/resource_category_test.rb` | Assignment uniqueness and associations |
| `test/models/controlled_resource_tag_test.rb` | Controlled-tag uniqueness and legacy-tag isolation |
| `test/models/tag_alias_test.rb` | Alias uniqueness and canonical ownership |
| `test/services/taxonomy/registry_test.rb` | Controlled vocabulary parsing and resolution |
| `test/services/taxonomy/validate_suggestion_test.rb` | Publication classification gate |
| `test/services/taxonomy/generate_suggestion_test.rb` | Classification lifecycle and persistence |
| `test/integrations/ai/nvidia_taxonomizer_test.rb` | Constrained NVIDIA request/response behavior |
| `test/services/taxonomy/reclassification_test.rb` | Immutable candidate, enqueue, quality, review, and publish flow |
| `test/services/search/selection_test.rb` | Array normalization, limits, and Blog/source contract |
| `test/services/search/facet_counts_test.rb` | Candidate counts under other active facets |
| `test/integration/admin_taxonomy_workflow_test.rb` | Controlled revision edit, tag creation, merge, and audits |
| `db/seed_data/taxonomy_review.json` | Deterministic 80-record human review artifact with recorded decisions |

### Existing files to modify

| File | Change |
|---|---|
| `app/models/resource.rb` | Retain legacy category/tag associations, add controlled multi-category/tag associations, delegate search indexing |
| `app/models/category.rb` | Retain legacy resources and add controlled-resource associations |
| `app/models/tag.rb` | Add governance fields, aliases, legacy/controlled associations, scopes, and validations |
| `app/models/resource_revision.rb` | Add taxonomy status/provenance and plural suggestion compatibility |
| `app/services/taxonomy/apply_revision.rb` | Replace dynamic creation with validated controlled assignment |
| `app/services/editorial/approve_and_publish.rb` | Validate taxonomy before immutable approval and audit before/after IDs |
| `app/services/ai/generate_summary.rb` | Stop treating summary generation as authoritative taxonomy publication |
| `app/integrations/ai/nvidia_summarizer.rb` | Keep summary response focused on summary/capabilities/key points |
| `app/services/search/resources_query.rb` | Consume normalized selection and implement OR-within/AND-between filtering |
| `app/controllers/resources_controller.rb` | Permit arrays, build selection/facet counts, return 400 on caps |
| `app/views/resources/index.html.erb` | Compose new search form, filter partials, results, and mobile sheet |
| `app/views/resources/_resource_card.html.erb` | Add explanatory taxonomy badges |
| `app/assets/tailwind/application.css` | Responsive/internal-scroll/sticky-action/active-chip styling |
| `app/controllers/admin/resource_revisions_controller.rb` | Permit controlled category/tag arrays |
| `app/views/admin/resource_revisions/edit.html.erb` | Replace free text with controlled multi-select fields |
| `app/views/admin/resource_revisions/show.html.erb` | Show plural suggestions and validation state |
| `app/views/admin/_navigation.html.erb` | Link to taxonomy administration |
| `config/routes.rb` | Add taxonomy overview and tag create/merge admin routes |
| `app/services/recommendations/related_resources.rb` | Score and explain shared multi-categories and tags |
| `app/views/resources/show.html.erb` | Render category/tag recommendation reasons beside each related resource |
| `app/views/layouts/application.html.erb` | Emit base canonical and `noindex, follow` for filtered listings |
| `app/services/initial_catalog/export_snapshot.rb` | Write snapshot version 2 taxonomy arrays and provenance |
| `app/services/initial_catalog/import_snapshot.rb` | Read version 1 and 2; normalize singular v1 category to an array |
| `app/services/initial_catalog/quality_report.rb` | Include taxonomy readiness in launch/release reporting |
| `lib/tasks/catalog.rake` | Add controlled taxonomy sync, enqueue, report, review export, and publish commands |
| `db/seed_data/initial_catalog.json` | Regenerate version 2 only after local quality gate passes |
| `docs/OPERATIONS.md` | Document dry-run, review, publish, rollback, and production verification |
| Existing search/editorial/recommendation/catalog/system tests | Lock backward compatibility and new contracts |

---

## Task 1: Add the Controlled Vocabulary and Additive Schema

**Files:**

- Create: `config/taxonomy.yml`
- Create: `db/migrate/20260830150000_create_controlled_taxonomy.rb`
- Create: `app/models/resource_category.rb`
- Create: `app/models/controlled_resource_tag.rb`
- Create: `app/models/tag_alias.rb`
- Create: `app/services/taxonomy/registry.rb`
- Create: `app/services/taxonomy/sync_vocabulary.rb`
- Create: `test/models/resource_category_test.rb`
- Create: `test/models/controlled_resource_tag_test.rb`
- Create: `test/models/tag_alias_test.rb`
- Create: `test/services/taxonomy/registry_test.rb`
- Modify: `app/models/resource.rb`
- Modify: `app/models/category.rb`
- Modify: `app/models/tag.rb`
- Modify: `app/models/resource_revision.rb`

- [ ] **Step 1: Write failing registry and model tests**

```ruby
# test/services/taxonomy/registry_test.rb
require "test_helper"

class Taxonomy::RegistryTest < ActiveSupport::TestCase
  setup { Taxonomy::SyncVocabulary.call }

  test "exposes exactly the fourteen approved categories in display order" do
    assert_equal 14, Taxonomy::Registry.categories.size
    assert_equal "coding-development", Taxonomy::Registry.categories.first.fetch("slug")
    assert_equal "learning-career", Taxonomy::Registry.categories.last.fetch("slug")
  end

  test "resolves aliases without inventing a tag" do
    assert_equal "ruby-on-rails", Taxonomy::Registry.resolve_tag_slug("Rails")
    assert_equal "mcp", Taxonomy::Registry.resolve_tag_slug("model-context-protocol")
    assert_nil Taxonomy::Registry.resolve_tag_slug("one-off-product-2026")
  end
end
```

```ruby
# test/models/resource_category_test.rb
require "test_helper"

class ResourceCategoryTest < ActiveSupport::TestCase
  test "does not allow a duplicate resource and category pair" do
    resource = Resource.create!(kind: :mcp, source_provider: :manual, slug: "one", canonical_url: "https://example.com/one", normalized_canonical_url: "https://example.com/one")
    category = Category.create!(slug: "coding-development", name: "コード作成・開発支援")
    ResourceCategory.create!(resource:, category:, origin: :admin)

    duplicate = ResourceCategory.new(resource:, category:, origin: :ai)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:category_id, :taken)
  end
end
```

In `controlled_resource_tag_test.rb`, create a legacy `ResourceTag` and a `ControlledResourceTag` for the same resource/tag pair, assert both can coexist, assert a second controlled pair is invalid, and assert deleting/replacing controlled assignments does not change the legacy join count.

- [ ] **Step 2: Run the focused tests and confirm the expected failure**

Run:

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/registry_test.rb test/models/resource_category_test.rb test/models/controlled_resource_tag_test.rb test/models/tag_alias_test.rb
```

Expected: constants/tables such as `Taxonomy::Registry`, `ResourceCategory`, or `TagAlias` are missing.

- [ ] **Step 3: Add the fixed categories and baseline YAML vocabulary**

Use this top-level shape and preserve the exact category list from the approved spec:

```yaml
version: taxonomy-v2
categories:
  - slug: coding-development
    name: コード作成・開発支援
    position: 10
    active: true
  - slug: design-review
    name: 設計・コードレビュー
    position: 20
    active: true
  - slug: testing-quality
    name: テスト・品質改善
    position: 30
    active: true
  - slug: debugging-observability-performance
    name: デバッグ・監視・性能改善
    position: 40
    active: true
  - slug: research-search
    name: 調査・検索
    position: 50
    active: true
  - slug: documentation-knowledge
    name: ドキュメント・ナレッジ管理
    position: 60
    active: true
  - slug: automation-integration
    name: 自動化・外部サービス連携
    position: 70
    active: true
  - slug: data-databases
    name: データベース・データ処理
    position: 80
    active: true
  - slug: infrastructure-devops
    name: インフラ・クラウド・DevOps
    position: 90
    active: true
  - slug: security-governance
    name: セキュリティ・ガバナンス
    position: 100
    active: true
  - slug: ai-llm-agents
    name: AI・LLM・エージェント開発
    position: 110
    active: true
  - slug: design-content
    name: UI/UX・コンテンツ制作
    position: 120
    active: true
  - slug: project-business-management
    name: プロジェクト・業務管理
    position: 130
    active: true
  - slug: learning-career
    name: 学習・キャリア
    position: 140
    active: true
tag_groups:
  language_framework: 言語・フレームワーク
  platform_service: サービス・プラットフォーム
  product_tool: 製品・ツール
  technique_architecture: 技術要素・アーキテクチャ
  environment_runtime: 対象環境・ランタイム
tags:
  - slug: ruby
    name: Ruby
    group: language_framework
    position: 10
    active: true
    filterable: true
    aliases: []
  - slug: ruby-on-rails
    name: Ruby on Rails
    group: language_framework
    position: 20
    active: true
    filterable: true
    aliases: [rails, rubyonrails]
```

Seed these exact canonical slugs and display names under the indicated groups. Assign positions 10, 20, 30, and so on in the displayed order within each group. Every seed row is active. Set `filterable: true` only for `ruby` and `ruby-on-rails` as the initial low-usage visibility allowlist; all other baseline tags start with `filterable: false`. The public facet shows an active tag when its public-resource usage is at least three or `filterable` is true.

```text
language_framework:
  python=Python, typescript=TypeScript, javascript=JavaScript, ruby=Ruby,
  ruby-on-rails=Ruby on Rails, go=Go, rust=Rust, java=Java, csharp=C#,
  swift=Swift, swiftui=SwiftUI, kotlin=Kotlin, react=React, nextjs=Next.js, sql=SQL

platform_service:
  github=GitHub, github-actions=GitHub Actions, aws=AWS, azure=Azure,
  cloudflare=Cloudflare, supabase=Supabase, postgresql=PostgreSQL, mysql=MySQL,
  docker=Docker, kubernetes=Kubernetes, terraform=Terraform, vercel=Vercel

product_tool:
  claude=Claude, claude-code=Claude Code, codex=Codex, cursor=Cursor,
  playwright=Playwright, puppeteer=Puppeteer, ollama=Ollama, obsidian=Obsidian,
  figma=Figma, vscode=VS Code, fastmcp=FastMCP

technique_architecture:
  mcp=MCP, agent-skills=Agent Skills, ai-agents=AI Agents, rag=RAG,
  prompt-engineering=Prompt Engineering, llm=LLM, local-llm=Local LLM,
  browser-automation=Browser Automation, web-scraping=Web Scraping,
  workflow-automation=Workflow Automation, api-integration=API Integration,
  code-review=Code Review, testing=Testing, debugging=Debugging,
  observability=Observability, performance=Performance, security=Security,
  accessibility=Accessibility, seo=SEO, ci-cd=CI/CD, authentication=Authentication,
  oauth=OAuth, tdd=TDD, knowledge-graph=Knowledge Graph,
  vector-database=Vector Database, multi-agent=Multi-Agent, automation=Automation,
  image-generation=Image Generation, video-generation=Video Generation,
  data-analysis=Data Analysis, document-processing=Document Processing

environment_runtime:
  web=Web, windows=Windows, macos=macOS, linux=Linux, ios=iOS, android=Android,
  cloud=Cloud, local-first=Local-first, self-hosted=Self-hosted
```

Seed these exact aliases:

```text
rails -> ruby-on-rails
rubyonrails -> ruby-on-rails
next-js -> nextjs
c-sharp -> csharp
postgres -> postgresql
cicd -> ci-cd
cicd-devops -> ci-cd
model-context-protocol -> mcp
mcp-server -> mcp
mcp-protocol -> mcp
ai-agent -> ai-agents
agentic-ai -> ai-agents
coding-agent -> ai-agents
coding-agents -> ai-agents
ai-coding-agent -> ai-agents
ai-coding-agents -> ai-agents
claude-ai -> claude
anthropic-claude -> claude
web-crawling -> web-scraping
test-driven-development -> tdd
performance-optimization -> performance
performance-tuning -> performance
ios-development -> ios
android-development -> android
```

Reject duplicate slugs, duplicate normalized aliases, unknown groups, or aliases that collide with another canonical slug when loading the registry.

- [ ] **Step 4: Add the additive migration**

The migration must create:

```ruby
create_table :resource_categories do |t|
  t.references :resource, null: false, foreign_key: true
  t.references :category, null: false, foreign_key: true
  t.integer :origin, null: false, default: 0
  t.timestamps
end
add_index :resource_categories, [:resource_id, :category_id], unique: true

create_table :controlled_resource_tags do |t|
  t.references :resource, null: false, foreign_key: true
  t.references :tag, null: false, foreign_key: true
  t.integer :origin, null: false, default: 0
  t.timestamps
end
add_index :controlled_resource_tags, [:resource_id, :tag_id], unique: true

create_table :tag_aliases do |t|
  t.references :tag, null: false, foreign_key: true
  t.string :name, null: false
  t.string :normalized_name, null: false
  t.timestamps
end
add_index :tag_aliases, :normalized_name, unique: true

change_table :tags, bulk: true do |t|
  t.string :vocabulary_group
  t.boolean :active, null: false, default: false
  t.boolean :filterable, null: false, default: false
  t.integer :position, null: false, default: 0
end

change_table :resource_revisions, bulk: true do |t|
  t.jsonb :suggested_category_slugs, null: false, default: []
  t.jsonb :search_keywords, null: false, default: []
  t.integer :taxonomy_status, null: false, default: 0
  t.integer :taxonomy_origin, null: false, default: 1
  t.string :taxonomy_provider
  t.string :taxonomy_model
  t.string :taxonomy_prompt_version
  t.string :taxonomy_input_sha256
  t.datetime :taxonomy_generated_at
  t.decimal :taxonomy_confidence, precision: 4, scale: 3
end
```

Add indexes for active/filterable/order lookups and taxonomy status. Do not remove or repurpose existing columns.

- [ ] **Step 5: Add models and compatibility associations**

Use these public associations:

```ruby
# app/models/resource.rb
belongs_to :category, optional: true # legacy rollback relation
has_many :resource_categories, dependent: :destroy
has_many :controlled_categories, through: :resource_categories, source: :category
has_many :resource_tags, dependent: :destroy # legacy rollback relation
has_many :tags, through: :resource_tags      # legacy rollback relation
has_many :controlled_resource_tags, dependent: :destroy
has_many :controlled_tags, through: :controlled_resource_tags, source: :tag

# app/models/category.rb
has_many :resources, dependent: :nullify # legacy rollback relation
has_many :resource_categories, dependent: :restrict_with_exception
has_many :controlled_resources, through: :resource_categories, source: :resource

# app/models/tag.rb
has_many :resource_tags, dependent: :destroy # legacy rollback relation
has_many :resources, through: :resource_tags # legacy rollback relation
has_many :controlled_resource_tags, dependent: :restrict_with_exception
has_many :controlled_resources, through: :controlled_resource_tags, source: :resource
```

`ResourceCategory`, `ControlledResourceTag`, and legacy `ResourceTag` use the same origin vocabulary: `source`, `ai`, `admin`. New taxonomy code reads/writes only `controlled_resource_tags`; legacy `resource_tags` remains untouched for rollback. `ResourceRevision` adds:

```ruby
enum :taxonomy_status, {
  not_requested: 0,
  queued: 1,
  processing: 2,
  succeeded: 3,
  failed: 4
}, prefix: true, validate: true

enum :taxonomy_origin, {
  source: 0,
  ai: 1,
  admin: 2
}, prefix: true, validate: true

def effective_suggested_category_slugs
  Array(suggested_category_slugs).presence || Array(suggested_category_slug).compact
end
```

- [ ] **Step 6: Implement registry loading and idempotent vocabulary sync**

Required interfaces:

```ruby
Taxonomy::Registry.version
Taxonomy::Registry.definition
Taxonomy::Registry.categories
Taxonomy::Registry.tags
Taxonomy::Registry.category_slugs
Taxonomy::Registry.tag_slugs
Taxonomy::Registry.resolve_tag_slug(value)
Taxonomy::Registry.prompt_payload
Taxonomy::Registry.vocabulary_fingerprint
Taxonomy::SyncVocabulary.call
```

`Registry.definition` validates YAML. Runtime `categories`, `tags`, slug resolution, prompt payload, and fingerprint read active database rows after sync so audited admin-added tags are immediately available to AI and approval. Existing uncontrolled tags receive `active: false` from the additive migration. `SyncVocabulary` upserts fixed categories plus baseline tags, aliases, flags, groups, and positions. It deactivates categories missing from YAML because categories are fixed; it does not deactivate an already active admin-created controlled tag merely because it is absent from the baseline file. It never deletes rows. Wrap the sync in one transaction.

- [ ] **Step 7: Prepare the test schema and make the focused tests pass**

Run:

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/registry_test.rb test/models/resource_category_test.rb test/models/controlled_resource_tag_test.rb test/models/tag_alias_test.rb
```

Expected: all focused tests pass and `db/schema.rb` contains the additive structures while `resources.category_id` and `resource_revisions.suggested_category_slug` remain.

- [ ] **Step 8: Commit Task 1**

```powershell
git add config/taxonomy.yml db/migrate/20260830150000_create_controlled_taxonomy.rb db/schema.rb app/models/resource.rb app/models/category.rb app/models/tag.rb app/models/resource_revision.rb app/models/resource_category.rb app/models/controlled_resource_tag.rb app/models/tag_alias.rb app/services/taxonomy/registry.rb app/services/taxonomy/sync_vocabulary.rb test/models/resource_category_test.rb test/models/controlled_resource_tag_test.rb test/models/tag_alias_test.rb test/services/taxonomy/registry_test.rb
git commit -m "feat: add controlled taxonomy schema"
```

---

## Task 2: Enforce Controlled Assignments at Approval

**Files:**

- Create: `app/services/taxonomy/validate_suggestion.rb`
- Create: `app/services/search/index_text.rb`
- Create: `test/services/taxonomy/validate_suggestion_test.rb`
- Modify: `app/services/taxonomy/apply_revision.rb`
- Modify: `app/services/editorial/approve_and_publish.rb`
- Modify: `app/models/resource.rb`
- Modify: `test/services/editorial/approve_and_publish_test.rb`
- Modify: `test/models/resource_publication_test.rb`

- [ ] **Step 1: Write failing validation and publication tests**

Cover these cases explicitly:

```ruby
test "accepts one to three categories and two to six canonical tags" do
  revision = build_revision(
    suggested_category_slugs: ["automation-integration", "research-search"],
    suggested_tag_slugs: ["ruby", "api-integration"]
  )
  assert Taxonomy::ValidateSuggestion.call(revision:).valid?
end

test "rejects unknown, duplicate, underfilled, and overfilled values" do
  revision = build_revision(
    suggested_category_slugs: ["unknown"],
    suggested_tag_slugs: ["ruby", "ruby"]
  )
  result = Taxonomy::ValidateSuggestion.call(revision:)
  assert_not result.valid?
  assert_includes result.errors, "unknown category: unknown"
  assert_includes result.errors, "duplicate tag: ruby"
end
```

Update approval tests so a revision cannot become immutable `approved` before taxonomy validation succeeds.

- [ ] **Step 2: Run the tests and verify validation is absent**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/validate_suggestion_test.rb test/services/editorial/approve_and_publish_test.rb test/models/resource_publication_test.rb
```

Expected: failures show that approval still accepts uncontrolled or missing taxonomy.

- [ ] **Step 3: Implement `Taxonomy::ValidateSuggestion`**

Return `Result = Data.define(:category_slugs, :tag_slugs, :search_keywords, :errors)` with `valid?`. Normalize only whitespace/case/registered aliases; do not parameterize unknown strings into apparently valid slugs. Enforce:

- category count 1–3;
- tag count 2–6;
- keyword count at most 30 and each normalized keyword at most 80 characters;
- no duplicates;
- all categories active and controlled;
- all tags active and controlled;
- aliases resolved before validation;
- reject `mcp` on an MCP resource and `agent-skills` on a Skill resource because those values only restate Content Type; allow both tags on Blog resources whose subject is MCP or Skills.

- [ ] **Step 4: Replace dynamic taxonomy creation**

`Taxonomy::ApplyRevision.call(revision:)` must:

1. call `ValidateSuggestion` and raise `InvalidSuggestion` with the error list if invalid;
2. load categories/tags by canonical slug from the synced DB;
3. replace all taxonomy-v2 `ResourceCategory` and `ControlledResourceTag` joins with the validated revision arrays, using `revision.taxonomy_origin` on each join;
4. leave `resource.category_id` and every legacy `ResourceTag` unchanged;
5. never call `find_or_create_by!` for categories or tags;
6. return the resource.

- [ ] **Step 5: Extract search text construction**

Required interface:

```ruby
Search::IndexText.call(resource:, revision:)
```

Build normalized text from title, author, summary, capabilities, key points, controlled-category names, controlled canonical tag names, controlled tag aliases, and revision search keywords. Change `Resource#publish!` to call this service after taxonomy joins are applied.

- [ ] **Step 6: Validate before approval and record an auditable diff**

In `Editorial::ApproveAndPublish`, take before IDs before applying taxonomy, validate before changing `review_status`, then audit:

```ruby
changeset: {
  review_status: [previous_status, revision.review_status],
  resource_id: revision.resource_id,
  controlled_category_ids: [before_controlled_category_ids, resource.controlled_category_ids.sort],
  controlled_tag_ids: [before_controlled_tag_ids, resource.controlled_tag_ids.sort]
}
```

Invalid taxonomy must leave the revision unapproved and both new/legacy resource classifications unchanged.

- [ ] **Step 7: Run focused tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/validate_suggestion_test.rb test/services/editorial/approve_and_publish_test.rb test/models/resource_publication_test.rb
```

Expected: all pass; no test creates a category/tag as a side effect of approval.

- [ ] **Step 8: Commit Task 2**

```powershell
git add app/services/taxonomy/validate_suggestion.rb app/services/taxonomy/apply_revision.rb app/services/search/index_text.rb app/services/editorial/approve_and_publish.rb app/models/resource.rb test/services/taxonomy/validate_suggestion_test.rb test/services/editorial/approve_and_publish_test.rb test/models/resource_publication_test.rb
git commit -m "feat: enforce controlled taxonomy publication"
```

---

## Task 3: Separate NVIDIA Classification from Summarization

**Files:**

- Create: `app/integrations/ai/taxonomy_suggestion.rb`
- Create: `app/integrations/ai/nvidia_taxonomizer.rb`
- Create: `app/services/taxonomy/generate_suggestion.rb`
- Create: `app/jobs/classify_revision_job.rb`
- Create: `test/integrations/ai/nvidia_taxonomizer_test.rb`
- Create: `test/services/taxonomy/generate_suggestion_test.rb`
- Modify: `app/integrations/ai/nvidia_summarizer.rb`
- Modify: `app/integrations/ai/summary.rb`
- Modify: `app/services/ai/generate_summary.rb`
- Modify: `test/integrations/ai/nvidia_summarizer_test.rb`
- Modify: `test/services/ai/generate_summary_test.rb`

- [ ] **Step 1: Write failing taxonomizer contract tests**

Define the typed result:

```ruby
Ai::TaxonomySuggestion = Data.define(
  :category_slugs,
  :tag_slugs,
  :search_keywords,
  :confidence,
  :provider,
  :model,
  :prompt_version
)
```

Test that NVIDIA receives only the revision classification basis plus `Taxonomy::Registry.prompt_payload`, and that the parser rejects prose, unknown slugs, malformed JSON, out-of-range confidence, and excess counts.

- [ ] **Step 2: Verify the focused tests fail**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb
```

Expected: taxonomizer constants are absent and summary generation still owns singular free-form classification.

- [ ] **Step 3: Implement a constrained NVIDIA request**

Use prompt version `catalog-taxonomy-v2`. The response JSON schema is:

```json
{
  "category_slugs": ["automation-integration"],
  "tag_slugs": ["ruby", "api-integration"],
  "search_keywords": ["Solid Queue"],
  "confidence": 0.92
}
```

The system instruction must state that values outside the supplied allowlists are invalid and that no explanation or Markdown is allowed. Reuse the existing NVIDIA endpoint/key/model configuration and HTTP failure conventions; do not log API keys, source bodies, or full model responses.

- [ ] **Step 4: Implement lifecycle-safe classification persistence**

`Taxonomy::GenerateSuggestion.call(revision:, taxonomizer: Ai::NvidiaTaxonomizer.new)` must:

1. atomically claim only `taxonomy_not_requested`, `taxonomy_queued`, or retryable `taxonomy_failed` revisions;
2. set processing state before the network call;
3. build `taxonomy_input_sha256` from title, excerpt, summary, capabilities, key points, and registry version;
4. persist plural categories, canonical tags, keywords, confidence, provider/model/prompt version, and generated time;
5. set `taxonomy_origin` to AI for a valid model result;
6. mark invalid suggestions failed without altering the currently published resource;
7. allow job retries without duplicate revisions or assignments.

`ClassifyRevisionJob#perform(revision_id)` loads the revision and calls this service.

- [ ] **Step 5: Remove taxonomy authority from summary generation**

Keep existing summary fields and provenance unchanged. `NvidiaSummarizer` may continue reading older cached responses during migration, but new requests and `Ai::GenerateSummary` must not create categories/tags or mark taxonomy succeeded. After a successful summary, set taxonomy queued and enqueue `ClassifyRevisionJob`.

- [ ] **Step 6: Run focused tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb
```

Expected: summary and taxonomy have independent statuses/provenance, and only controlled values are persisted.

- [ ] **Step 7: Commit Task 3**

```powershell
git add app/integrations/ai/taxonomy_suggestion.rb app/integrations/ai/nvidia_taxonomizer.rb app/integrations/ai/nvidia_summarizer.rb app/integrations/ai/summary.rb app/services/ai/generate_summary.rb app/services/taxonomy/generate_suggestion.rb app/jobs/classify_revision_job.rb test/integrations/ai/nvidia_taxonomizer_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb test/services/taxonomy/generate_suggestion_test.rb
git commit -m "feat: add constrained NVIDIA taxonomizer"
```

---

## Task 4: Build the Immutable 400-Record Reclassification Workflow

**Files:**

- Create: `app/services/taxonomy/build_reclassification_candidate.rb`
- Create: `app/services/taxonomy/enqueue_reclassification.rb`
- Create: `app/services/taxonomy/quality_report.rb`
- Create: `app/services/taxonomy/export_review_sample.rb`
- Create: `app/services/taxonomy/publish_reclassification.rb`
- Create: `test/services/taxonomy/reclassification_test.rb`
- Modify: `lib/tasks/catalog.rake`
- Modify: `app/services/initial_catalog/quality_report.rb`
- Create after classification: `db/seed_data/taxonomy_review.json`

- [ ] **Step 1: Write failing immutable-candidate and quality-gate tests**

Required behavior:

```ruby
candidate = Taxonomy::BuildReclassificationCandidate.call(resource: published_resource)

assert_equal published_resource.current_revision.ai_summary, candidate.ai_summary
assert candidate.draft?
assert candidate.summary_status_succeeded?
assert candidate.taxonomy_status_queued?
assert_equal Digest::SHA256.hexdigest("#{published_resource.current_revision.source_fingerprint}:taxonomy-v2"), candidate.source_fingerprint
assert_no_changes -> { published_resource.current_revision.reload.attributes }
```

Also test idempotent reruns, exactly 20 sample records per kind, a failed score below 90%, all invalid/low-confidence records included for manual review, explicit confirmation, and no partial publication.

- [ ] **Step 2: Confirm the tests fail before services exist**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/reclassification_test.rb test/services/initial_catalog/quality_report_test.rb
```

- [ ] **Step 3: Implement candidate creation and enqueueing**

Clone the current approved revision’s content and summary provenance. Do not copy its approval fields. Use `find_or_create_by!(resource:, source_fingerprint:)` so retries return the same candidate. Enqueue only candidates whose taxonomy state is queued or retryable failed.

Required interfaces:

```ruby
Taxonomy::BuildReclassificationCandidate.call(resource:)
Taxonomy::EnqueueReclassification.call(scope: Resource.publicly_visible)
```

- [ ] **Step 4: Implement deterministic review export**

Sort within each kind by SHA256 of `"taxonomy-v2:#{resource.id}"`, then take 20. Always append all candidates that are invalid, failed, or below the confidence threshold even when they are outside the base 80; mark these as `required_review: true`.

The JSON artifact must contain:

```json
{
  "format": "ai-dev-zukan.taxonomy-review",
  "version": 1,
  "taxonomy_version": "taxonomy-v2",
  "generated_at": "ISO8601 timestamp",
  "records_sha256": "sha256",
  "records": [
    {
      "resource_id": 1,
      "kind": "mcp",
      "title": "Example",
      "category_slugs": ["automation-integration"],
      "tag_slugs": ["mcp", "api-integration"],
      "confidence": 0.9,
      "required_review": false,
      "category_match": null,
      "tag_match": null,
      "review_note": null
    }
  ]
}
```

Reviewers set both match fields to booleans and may add a note. Quality passes only when all required records are reviewed and both category and tag accuracy are at least 90% across the 80 base samples.

- [ ] **Step 5: Implement quality and guarded publication services**

`Taxonomy::QualityReport.call(scope:, review_path:)` returns a Data object with counts and `acceptable?`. It must fail on:

- any public resource without one taxonomy-v2 candidate;
- taxonomy state other than succeeded;
- categories outside 1–3;
- tags outside 2–6;
- unknown/inactive values;
- duplicate values;
- incomplete required review;
- category or tag review accuracy below 90%.

`Taxonomy::PublishReclassification.call(reviewer:, confirmation:, review_path:)` requires admin reviewer and exact confirmation `publish-taxonomy-v2`. It validates the full report before publishing each candidate through `Editorial::ApproveAndPublish`. A preflight phase must complete before the first write so a known invalid candidate cannot cause partial publication.

- [ ] **Step 6: Add rake commands with JSON output**

```text
catalog:taxonomy:sync
catalog:taxonomy:enqueue
catalog:taxonomy:report
catalog:taxonomy:export_review
catalog:taxonomy:publish
```

`publish` reads `CONFIRM` and optional `TAXONOMY_REVIEW_PATH`, obtains the locked `.invalid` system reviewer through `InitialCatalog::ReleaseReviewer.call`, and aborts unless confirmation matches exactly. No personal administrator email is required for the catalog release task.

- [ ] **Step 7: Run focused tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/taxonomy/reclassification_test.rb test/services/initial_catalog/quality_report_test.rb
```

- [ ] **Step 8: Commit Task 4**

```powershell
git add app/services/taxonomy/build_reclassification_candidate.rb app/services/taxonomy/enqueue_reclassification.rb app/services/taxonomy/quality_report.rb app/services/taxonomy/export_review_sample.rb app/services/taxonomy/publish_reclassification.rb app/services/initial_catalog/quality_report.rb lib/tasks/catalog.rake test/services/taxonomy/reclassification_test.rb test/services/initial_catalog/quality_report_test.rb
git commit -m "feat: add guarded catalog reclassification"
```

Do not commit `db/seed_data/taxonomy_review.json` until its decisions are complete and the checksum/quality test passes.

---

## Task 5: Version the Portable Catalog Snapshot

**Files:**

- Modify: `app/services/initial_catalog/export_snapshot.rb`
- Modify: `app/services/initial_catalog/import_snapshot.rb`
- Modify: `test/services/initial_catalog/snapshot_test.rb`
- Modify after local review: `db/seed_data/initial_catalog.json`

- [ ] **Step 1: Write failing v1 compatibility and v2 round-trip tests**

Test that:

- exporter writes `version: 2`;
- v2 contains `suggested_category_slugs`, `suggested_tag_slugs`, `search_keywords`, taxonomy provenance, and a top-level controlled vocabulary block with active tags/aliases;
- v2 stores separate SHA256 values for the exact serialized records and vocabulary payload;
- importer accepts existing v1, maps a recognized `suggested_category_slug` to a one-item array, resolves recognized tag aliases, and queues taxonomy when legacy values are not controlled;
- importer accepts v2 and recreates only vocabulary rows declared in its validated vocabulary block;
- fixed categories in v2 exactly match the 14 YAML categories;
- unsupported versions, checksum changes, or revision slugs missing from the declared v2 vocabulary fail before writes.

- [ ] **Step 2: Run and confirm version expectations fail**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/initial_catalog/snapshot_test.rb
```

- [ ] **Step 3: Implement explicit version readers**

Set exporter `VERSION = 2`, importer `SUPPORTED_VERSIONS = [1, 2].freeze`, and route normalization through private `normalize_v1_revision` / `normalize_v2_revision` methods. The v2 payload contains `taxonomy.version`, fixed categories, active controlled tags, aliases, and `taxonomy_sha256`. Validate the full payload, both checksums, fixed category equality, alias uniqueness, and every assignment before starting the transaction. After validation, upsert declared controlled tags/aliases inside the same import transaction; importing a signed snapshot vocabulary is the only non-admin/non-YAML path that may create a controlled tag.

- [ ] **Step 4: Run snapshot tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/initial_catalog/snapshot_test.rb
```

- [ ] **Step 5: Commit code without regenerating production seed data yet**

```powershell
git add app/services/initial_catalog/export_snapshot.rb app/services/initial_catalog/import_snapshot.rb test/services/initial_catalog/snapshot_test.rb
git commit -m "feat: version taxonomy catalog snapshots"
```

---

## Task 6: Implement Normalized Multi-Facet Search

**Files:**

- Create: `app/services/search/selection.rb`
- Create: `test/services/search/selection_test.rb`
- Modify: `app/services/search/resources_query.rb`
- Modify: `test/services/search/resources_query_test.rb`
- Modify: `app/controllers/resources_controller.rb`
- Modify: `test/integration/public_discovery_test.rb`

- [ ] **Step 1: Write failing selection contract tests**

Required normalized interface:

```ruby
Search::Selection = Data.define(
  :query,
  :content_types,
  :sources,
  :category_slugs,
  :tag_slugs,
  :period,
  :sort
)
```

Expose `Search::Selection.build(params:)`, `#to_h`, `#to_query`, `#filtered?`, and `#without(facet, value)`. Test deduplication, registry order, unknown removal, source-without-Blog removal, and hard caps:

```ruby
MAXIMUMS = {
  content_types: 3,
  sources: 2,
  category_slugs: 14,
  tag_slugs: 20
}.freeze
```

Over-cap input raises `Search::Selection::TooManyValues` and maps to HTTP 400.

- [ ] **Step 2: Write failing OR/AND query tests**

Include named tests for:

- MCP OR Skill;
- Category A OR Category B;
- Tag Ruby OR Python;
- `(MCP OR Skill) AND (Category A OR Category B) AND (Ruby OR Python)`;
- `MCP OR (Blog AND Zenn)`;
- Blog without Source includes Zenn and Qiita;
- Source without Blog is ignored by normalization;
- multiple category/tag JOINs return each resource once;
- hidden resources remain excluded for authenticated users;
- query, period, and sort still work.

- [ ] **Step 3: Run and verify scalar implementation fails the new tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/search/selection_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
```

- [ ] **Step 4: Implement normalized filtering**

Change the query entry point to:

```ruby
Search::ResourcesQuery.call(selection:, user: nil)
```

Build kind/source conditions as one disjunction, for example:

```ruby
branches = []
branches << Resource.where(kind: :mcp) if selection.content_types.include?("mcp")
branches << Resource.where(kind: :skill) if selection.content_types.include?("skill")
if selection.content_types.include?("blog")
  blog = Resource.where(kind: [:zenn_article, :qiita_article])
  blog = blog.where(source_provider: selection.sources) if selection.sources.any?
  branches << blog
end
```

Combine branches with OR, then apply category OR through `joins(:controlled_categories)`, tag OR through `joins(:controlled_tags)`, period, query, and hidden-resource filters as AND stages. Never join legacy `:category` or `:tags` for taxonomy-v2 search. Use `.distinct` after taxonomy joins and before ordering/counting.

- [ ] **Step 5: Update controller parameter handling**

Permit:

```ruby
params.permit(:q, :period, :sort, content_types: [], sources: [], category_slugs: [], tag_slugs: [])
```

Build one normalized `@selection`, pass it to query services, and rescue only `TooManyValues` as `head :bad_request`. Do not silently truncate over-cap arrays.

- [ ] **Step 6: Run focused search tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/search/selection_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
```

- [ ] **Step 7: Commit Task 6**

```powershell
git add app/services/search/selection.rb app/services/search/resources_query.rb app/controllers/resources_controller.rb test/services/search/selection_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
git commit -m "feat: add multi-select faceted search"
```

---

## Task 7: Add Facet Counts with the Same Search Semantics

**Files:**

- Create: `app/services/search/facet_counts.rb`
- Create: `test/services/search/facet_counts_test.rb`
- Modify: `app/services/search/resources_query.rb`
- Modify: `app/controllers/resources_controller.rb`

- [ ] **Step 1: Write failing candidate-count tests**

For each facet, assert that current values from that facet are excluded while all other facets remain. Example: with MCP and Ruby selected, the count beside Python evaluates `(MCP) AND (Ruby OR Python)`, while the count beside a second category evaluates `(MCP) AND (selected categories OR candidate category) AND (Ruby)`.

- [ ] **Step 2: Run and confirm the service is missing**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/search/facet_counts_test.rb
```

- [ ] **Step 3: Share a relation-building boundary**

Extract a query method that accepts an optional excluded facet without duplicating SQL semantics:

```ruby
Search::ResourcesQuery.relation(selection:, user: nil, except: nil)
```

`FacetCounts.call(selection:, user:)` returns:

```ruby
{
  content_types: { "mcp" => 100, "skill" => 100, "blog" => 200 },
  sources: { "zenn" => 100, "qiita" => 100 },
  categories: { "automation-integration" => 42 },
  tags: { "ruby" => 18 }
}
```

Use grouped DB counts and controlled active/filterable scopes. Do not issue one query per option.

- [ ] **Step 4: Add SQL-count regression protection**

Use `ActiveSupport::Notifications` in the test to assert the index request stays within a fixed query ceiling determined from the implementation. Count only non-schema, non-transaction SQL and choose a ceiling no more than 12 for the four facet groups plus results.

- [ ] **Step 5: Run focused tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/search/facet_counts_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
```

- [ ] **Step 6: Commit Task 7**

```powershell
git add app/services/search/facet_counts.rb app/services/search/resources_query.rb app/controllers/resources_controller.rb test/services/search/facet_counts_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
git commit -m "feat: add faceted result counts"
```

---

## Task 8: Replace the Public Filter UI and Explain Matches

**Files:**

- Create: `app/views/resources/_filter_panel.html.erb`
- Create: `app/views/resources/_active_filters.html.erb`
- Create: `app/views/resources/_selection_hidden_fields.html.erb`
- Create: `app/views/resources/_taxonomy_badges.html.erb`
- Create: `app/javascript/controllers/facet_filter_controller.js`
- Modify: `app/views/resources/index.html.erb`
- Modify: `app/views/resources/_resource_card.html.erb`
- Modify: `app/assets/tailwind/application.css`
- Modify: `test/integration/public_discovery_test.rb`
- Modify: `test/system/public_catalog_test.rb`

- [ ] **Step 1: Add failing integration assertions for rendered state**

Assert that a URL with repeated array parameters renders all selected checkboxes, Active Filter chips, the matching result, preserved search/period/sort inputs, and individual/clear-all links. Assert that Blog controls Source visibility and that category/tag names appear on cards.

- [ ] **Step 2: Add failing system tests for interaction and reachability**

Use Capybara at both required viewports:

```ruby
page.current_window.resize_to(1280, 720)
assert_selector "[data-filter-actions]", visible: true

page.current_window.resize_to(390, 844)
click_on "絞り込み"
assert_selector "[role='dialog'][aria-modal='true']", visible: true
```

Test keyboard Tab/Space selection, Escape close, fixed mobile result action, tag text filtering, chip removal, clear-all, light/dark state, and 200% browser zoom where supported. Do not treat screenshot creation alone as a pass.

- [ ] **Step 3: Run and verify old single-select UI fails**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integration/public_discovery_test.rb test/system/public_catalog_test.rb
```

- [ ] **Step 4: Compose an accessible GET form**

Render Content Type as three checkbox toggle chips, Source only when Blog is selected, all 14 categories as checkboxes, and filterable tags with local text search and result counts. Each facet uses `fieldset` and `legend`; the real checkbox remains keyboard/screen-reader operable.

Use one GET form for query, facets, period, and sort. Do not duplicate unnormalized hidden values. Apply only on submit.

- [ ] **Step 5: Implement Active Filter links without losing other state**

Each chip builds a URL from `@selection.without(facet, value).to_h`. Clear-all retains only the normalized query when the user deliberately entered it; add a separate fully clear link if the existing product wording promises that behavior.

- [ ] **Step 6: Implement responsive panel behavior**

Desktop:

- reduce hero height enough to show query, count, and filter start at 1280×720;
- keep left filters in viewport with `max-height` and internal scrolling;
- keep Apply/Reset in a sticky panel footer.

Mobile:

- open a bottom sheet with `role="dialog"` and `aria-modal="true"`;
- move focus into the sheet and restore it to the opener on close;
- close on Escape/backdrop;
- lock background scroll;
- keep selection count and result action visible at the bottom;
- allow the filter content above it to scroll.

- [ ] **Step 7: Explain why each result matched**

`_taxonomy_badges.html.erb` shows up to two categories and three tags. Sort currently selected matching values first, then controlled position/name, and show `+n` for the remainder. Use accessible text such as `一致カテゴリ`/`一致タグ`; do not rely on color alone.

- [ ] **Step 8: Run focused UI tests and inspect generated CSS**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integration/public_discovery_test.rb test/system/public_catalog_test.rb
docker compose run --rm web bin/rails tailwindcss:build
```

Expected: tests pass and Tailwind build completes without unknown utility errors.

- [ ] **Step 9: Commit Task 8**

```powershell
git add app/views/resources/index.html.erb app/views/resources/_resource_card.html.erb app/views/resources/_filter_panel.html.erb app/views/resources/_active_filters.html.erb app/views/resources/_selection_hidden_fields.html.erb app/views/resources/_taxonomy_badges.html.erb app/javascript/controllers/facet_filter_controller.js app/assets/tailwind/application.css app/assets/builds/tailwind.css test/integration/public_discovery_test.rb test/system/public_catalog_test.rb
git commit -m "feat: redesign public filter experience"
```

---

## Task 9: Replace Admin Free Text with Controlled Multi-Select and Audited Tag Governance

**Files:**

- Create: `app/controllers/admin/taxonomy_controller.rb`
- Create: `app/controllers/admin/tags_controller.rb`
- Create: `app/services/taxonomy/create_tag.rb`
- Create: `app/services/taxonomy/merge_tag.rb`
- Create: `app/views/admin/taxonomy/index.html.erb`
- Create: `test/integration/admin_taxonomy_workflow_test.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/resource_revisions_controller.rb`
- Modify: `app/views/admin/resource_revisions/edit.html.erb`
- Modify: `app/views/admin/resource_revisions/show.html.erb`
- Modify: `app/views/admin/_navigation.html.erb`
- Modify: `test/integration/admin_resource_workflow_test.rb`

- [ ] **Step 1: Write failing admin workflow tests**

Test that an admin can select 1–3 categories and 2–6 tags from controlled lists, cannot submit an unknown slug, sees validation errors without losing selections, and can approve a valid manual or imported candidate. Test that non-admin users receive the existing access response.

For tag governance, test create, alias display, merge, join movement, alias movement, source deactivation, destination preservation, and audit before/after IDs.

- [ ] **Step 2: Run and confirm current free-text behavior fails**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integration/admin_resource_workflow_test.rb test/integration/admin_taxonomy_workflow_test.rb
```

- [ ] **Step 3: Replace revision parameters and fields**

Permit:

```ruby
params.require(:resource_revision).permit(
  :title,
  :author_name,
  :ai_summary,
  capabilities: [],
  key_points: [],
  suggested_category_slugs: [],
  suggested_tag_slugs: [],
  search_keywords: []
)
```

Render category/tag checkboxes from `Taxonomy::Registry`/active DB rows. Do not render or accept free-text slug creation. Show validation state and AI confidence/provenance on the review page. When an admin changes either taxonomy array, set `taxonomy_origin` to admin while preserving the original AI provenance fields.

- [ ] **Step 4: Add taxonomy overview and tag governance services**

The overview shows all 14 categories, controlled tags, group, aliases, active/filterable state, and usage counts.

`Taxonomy::CreateTag.call(attributes:, actor:, request_id:)` validates unique canonical slug/name, approved group, aliases, active/filterable state, and audit creation. The row becomes part of the active database-backed runtime allowlist immediately. Snapshot version 2 must export these controlled vocabulary rows so a clean environment can reproduce admin-added tags without requiring a source-code edit.

`Taxonomy::MergeTag.call(source:, destination:, actor:, request_id:)` must in one transaction:

1. move or deduplicate `controlled_resource_tags` while leaving legacy `resource_tags` untouched;
2. move non-conflicting aliases;
3. add the source name/slug as destination aliases when available;
4. deactivate and hide source;
5. never delete either tag;
6. write an audit log with source/destination and moved resource IDs.

- [ ] **Step 5: Add routes and navigation**

```ruby
namespace :admin do
  get "taxonomy", to: "taxonomy#index", as: :taxonomy
  resources :tags, only: :create do
    post :merge, on: :member
  end
end
```

- [ ] **Step 6: Run focused admin tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/integration/admin_resource_workflow_test.rb test/integration/admin_taxonomy_workflow_test.rb
```

- [ ] **Step 7: Commit Task 9**

```powershell
git add config/routes.rb app/controllers/admin/taxonomy_controller.rb app/controllers/admin/tags_controller.rb app/controllers/admin/resource_revisions_controller.rb app/services/taxonomy/create_tag.rb app/services/taxonomy/merge_tag.rb app/views/admin/taxonomy/index.html.erb app/views/admin/resource_revisions/edit.html.erb app/views/admin/resource_revisions/show.html.erb app/views/admin/_navigation.html.erb test/integration/admin_resource_workflow_test.rb test/integration/admin_taxonomy_workflow_test.rb
git commit -m "feat: add controlled taxonomy administration"
```

---

## Task 10: Update Recommendations and Filtered-Listing SEO

**Files:**

- Modify: `app/services/recommendations/related_resources.rb`
- Modify: `test/services/recommendations/related_resources_test.rb`
- Modify: `app/views/resources/show.html.erb`
- Modify: `app/controllers/resources_controller.rb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `test/integration/seo_discovery_test.rb`

- [ ] **Step 1: Write failing recommendation and SEO tests**

Recommendation tests must prove that multiple shared controlled categories and controlled tags affect score and produce separate reasons. Legacy `category_id` or legacy `resource_tags` alone must not create a taxonomy match.

SEO tests must prove:

- filtered/search listing responses emit `noindex, follow`;
- filtered listing canonical points to the unfiltered resource index;
- unfiltered listing remains indexable;
- detail canonicals, sitemap, and structured data remain unchanged.

- [ ] **Step 2: Run and verify the old single-category behavior fails**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/recommendations/related_resources_test.rb test/integration/seo_discovery_test.rb
```

- [ ] **Step 3: Score shared multi-taxonomy**

Return recommendation entries with explicit reason payloads, for example:

```ruby
{
  resource: candidate,
  score: 8,
  reasons: {
    categories: ["自動化・外部サービス連携"],
    tags: ["Ruby", "API連携"]
  }
}
```

Keep popularity/recency tie-breakers deterministic and exclude the current/hidden resources as before.

- [ ] **Step 4: Emit filtered-listing robots and canonical metadata**

Drive the decision from `@selection.filtered?`, not raw params, so unknown/ignored values do not create SEO variants. Canonical ordering comes from normalized `Selection`; canonical for every valid filtered listing points to `resources_url` without facets.

- [ ] **Step 5: Run focused tests**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/recommendations/related_resources_test.rb test/integration/seo_discovery_test.rb
```

- [ ] **Step 6: Commit Task 10**

```powershell
git add app/services/recommendations/related_resources.rb app/views/resources/show.html.erb app/controllers/resources_controller.rb app/views/layouts/application.html.erb test/services/recommendations/related_resources_test.rb test/integration/seo_discovery_test.rb
git commit -m "feat: use controlled taxonomy in discovery"
```

---

## Task 11: Execute the Local Reclassification, Review 80 Samples, and Regenerate Artifacts

**Files:**

- Modify: `db/seed_data/taxonomy_review.json`
- Modify: `db/seed_data/initial_catalog.json`
- Modify: `docs/OPERATIONS.md`
- Modify tests only if the local execution exposes a genuine missing contract; do not weaken quality thresholds.

- [ ] **Step 1: Prepare development data and sync controlled vocabulary**

```powershell
docker compose run --rm web bin/rails db:prepare
docker compose run --rm web bin/rails catalog:taxonomy:sync
```

Expected: 14 active categories, only YAML-defined controlled tags/aliases active for taxonomy-v2, no legacy deletion.

- [ ] **Step 2: Create and enqueue taxonomy-v2 candidates**

```powershell
docker compose run --rm web bin/rails catalog:taxonomy:enqueue
docker compose up -d web worker
docker compose logs --tail 200 worker
```

Expected: one taxonomy-v2 candidate per public resource, jobs progress to succeeded or explicit failed state, existing current revisions remain approved/current.

- [ ] **Step 3: Export and complete the human review artifact**

```powershell
docker compose run --rm web bin/rails catalog:taxonomy:export_review TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
```

Review exactly 20 base samples from MCP, Skill, Zenn, and Qiita plus every required-review record. Set both boolean match fields and add concrete notes for mismatches. Do not mark ambiguous classifications correct to reach the threshold.

- [ ] **Step 4: Run the quality report and iterate on vocabulary/prompt only if it fails**

```powershell
docker compose run --rm web bin/rails catalog:taxonomy:report TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
```

Expected pass conditions: 400 candidates; 100 per kind; all taxonomy succeeded; 1–3 categories; 2–6 tags; zero unknown/duplicate values; all required review complete; category accuracy at least 90%; tag accuracy at least 90%.

If the report fails, change the smallest defensible YAML definition, alias, or classification prompt, bump the taxonomy prompt version, rebuild affected candidates, and repeat Steps 2–4. Do not edit individual AI results merely to satisfy the metric; manual admin corrections must remain auditable.

- [ ] **Step 5: Publish in development with explicit local confirmation**

```powershell
docker compose run --rm web bin/rails catalog:taxonomy:publish CONFIRM=publish-taxonomy-v2 TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
```

The task uses the locked `.invalid` release reviewer and therefore does not need a personal administrator email. Expected: 400 public resources now point to approved taxonomy-v2 revisions while prior approved revisions remain present.

- [ ] **Step 6: Export the v2 initial catalog and verify checksum**

```powershell
docker compose run --rm web bin/rails catalog:snapshot:export INITIAL_CATALOG_SNAPSHOT=db/seed_data/initial_catalog.json BOOTSTRAP_PER_KIND=100
docker compose run --rm -e RAILS_ENV=test web bin/rails test test/services/initial_catalog/snapshot_test.rb
```

- [ ] **Step 7: Document operator and rollback commands**

Update `docs/OPERATIONS.md` with the exact sync/enqueue/report/export-review/publish commands, environment variables, expected JSON keys, failure handling, and rollback sequence. Rollback switches application reads back to legacy `category_id`/existing tag relations through a revert deployment; it does not delete taxonomy-v2 rows.

- [ ] **Step 8: Commit reviewed artifacts**

```powershell
git add db/seed_data/taxonomy_review.json db/seed_data/initial_catalog.json docs/OPERATIONS.md config/taxonomy.yml
git commit -m "data: publish reviewed taxonomy v2 catalog"
```

---

## Task 12: Full Verification and Production Dry-Run Gate

**Files:**

- Modify only when a failing check reveals a real defect in an already planned file.
- Do not deploy or mutate production in this task.

- [ ] **Step 1: Run the complete automated suite**

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test
docker compose run --rm web bundle exec rubocop
docker compose run --rm web bundle exec brakeman --no-pager
docker compose run --rm web bundle exec bundler-audit check --update
docker compose run --rm web bin/rails tailwindcss:build
```

Expected: every command exits 0. Fix defects and rerun the smallest affected check before repeating the full gate.

- [ ] **Step 2: Run browser verification against the local app**

Verify at 1280×720, 390×844, light, dark, keyboard-only, and 200% zoom:

1. MCP and Skill multi-select returns their OR union.
2. MCP + Blog + Zenn retains MCP and restricts only the Blog branch to Zenn.
3. Two categories use OR.
4. Ruby + Python tags use OR.
5. Content Type + Category + Tag use AND between facets.
6. Active Filter chips remove one condition without losing others.
7. Cards visibly explain matching categories/tags.
8. Desktop Apply and mobile Result actions remain reachable.
9. Admin revision review uses controlled multi-select and can publish a valid manual candidate.
10. Unknown and over-cap URLs behave according to the contract.

Capture screenshots under `.chatgpt/` for review evidence but keep that directory untracked.

- [ ] **Step 3: Verify local database invariants with one read-only runner command**

```powershell
docker compose run --rm web bin/rails runner 'scope = Resource.publicly_visible; puts({total: scope.count, kinds: scope.group(:kind).count, category_range: scope.joins(:resource_categories).group("resources.id").count.values.minmax, tag_range: scope.joins(:controlled_resource_tags).group("resources.id").count.values.minmax, missing_categories: scope.where.missing(:resource_categories).count, missing_tags: scope.where.missing(:controlled_resource_tags).count}.to_json)'
```

Expected: total 400; four kinds each 100; category range within 1–3; tag range within 2–6; missing counts 0. Also run model/service checks for inactive or uncontrolled assigned values and duplicate joins.

- [ ] **Step 4: Review the complete branch diff and commit hygiene**

```powershell
git status --short
git diff --check main...HEAD
git log --oneline --decorate -12
```

Expected: no accidental `.env`, API keys, `.chatgpt/`, temporary output, or unrelated workspace changes are staged/committed.

- [ ] **Step 5: Prepare the production dry-run report**

The report presented to the user must list:

- exact production target: Supabase project/connection role and Render service name, without secrets;
- migration file and additive tables/columns;
- public target count: MCP 100, Skill 100, Zenn 100, Qiita 100;
- taxonomy-v2 candidate counts and quality percentages;
- number of current revisions that will switch;
- exact commands that will run;
- expected maintenance/availability impact;
- rollback deployment/legacy-data path;
- post-deploy checks for `/up`, logs, counts, representative search URLs, 1280×720, and 390×844;
- explicit statement that production has not yet been changed.

- [ ] **Step 6: Stop for separate production approval**

Do not run the production migration, catalog publication, GitHub push, or Render deployment until the user explicitly approves the production dry-run report. After approval, execute the documented sequence, verify production DB/log/browser evidence, and report yes/no against every production completion criterion.
