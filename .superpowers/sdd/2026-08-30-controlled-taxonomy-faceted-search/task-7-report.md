## Task 7 Report: Facet Counts with Shared Search Semantics

Commit: `feat: add faceted result counts`

### RED

Initial command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb
```

Result: `5 runs, 0 assertions, 0 failures, 5 errors, 0 skips`

Expected failure:

- `Search::FacetCounts` was undefined.

Additional regression RED:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb -n test_source_counts_keep_non-blog_content_while_restricting_only_the_blog_branch
```

Result: `1 runs, 1 assertions, 1 failures, 0 errors, 0 skips`

Expected failure:

- Content Type count for selected Blog+Source included Qiita in the Blog candidate count when only Zenn was selected.

### GREEN

Focused command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
```

Result: `21 runs, 52 assertions, 0 failures, 0 errors, 0 skips`

Full suite:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
```

Result: `142 runs, 737 assertions, 0 failures, 0 errors, 0 skips`

### SQL Ceiling

Measured index SQL count for an index request with Content Type, Source, Category, and Tag selected: `12`.

The integration regression counts non-cached SQL and excludes only `SCHEMA` and `TRANSACTION` payloads:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integration/public_discovery_test.rb -n test_index_search_uses_a_bounded_number_of_SQL_queries_with_facet_counts
```

Result: `1 runs, 3 assertions, 0 failures, 0 errors, 0 skips`

### Lint and Diff Checks

```powershell
docker compose run --rm web bundle exec rubocop app/services/search/facet_counts.rb app/services/search/resources_query.rb app/controllers/resources_controller.rb app/services/taxonomy/registry.rb test/services/search/facet_counts_test.rb test/integration/public_discovery_test.rb
```

Result: `6 files inspected, no offenses detected`

```powershell
git diff --check
```

Result: exit 0, no whitespace errors.

Known pre-existing environment warnings observed during Docker Rails commands:

- `bin/rails:1: warning: shebang line ending with \r may cause problems`
- `/usr/bin/env: 'ruby\r': No such file or directory`
- Rack frozen string warnings in the full suite.

### Changed Files

- `app/services/search/facet_counts.rb`
- `app/services/search/resources_query.rb`
- `app/controllers/resources_controller.rb`
- `app/services/taxonomy/registry.rb`
- `test/services/search/facet_counts_test.rb`
- `test/integration/public_discovery_test.rb`

### Implemented Behavior

- Added `Search::FacetCounts.call(selection:, user:, result_count: nil)`.
- Added `Search::ResourcesQuery.relation(selection:, user: nil, except: nil)` so facet counts reuse the same hidden, query, period, sort, Content Type, Source, Category, and Tag semantics.
- Candidate counts exclude only the counted facet and preserve all other facets.
- Same-facet candidates use the current selected values OR the candidate value.
- Content Type, Source, Category, and Tag counts are each calculated with grouped database queries, not per-option count loops.
- Source counts preserve non-Blog branches while restricting only the Blog branch to Zenn or Qiita.
- Tag candidates are visible when active and either forced filterable or used at least three times.
- `ResourcesController#index` now exposes `@facet_counts` and uses the same visible tag set as the count service.
- `Taxonomy::Registry.category_slugs` now reads the fixed 14 category slugs from `config/taxonomy.yml`, avoiding a DB query during public selection normalization.

### Assumptions and Risks

- Tag usage visibility is counted from controlled tag assignments. The current implementation does not delete or mutate legacy tag joins.
- `result_count` is optional for service callers, but the controller passes the already-measured result count to avoid a duplicate count query.
- No production deploy, GitHub push, or external mutation was performed.

## Fix Round 1

Commit: `fix: scope public facet visibility`

### Findings Addressed

- Public tag visibility threshold now counts distinct resources only from `Resource.publicly_visible`. Unpublished resources, resources with no `current_revision_id`, and archived resources do not make a tag visible. The `filterable: true` override remains in place.
- `Taxonomy::Registry.category_slugs` now returns only active category slugs from the taxonomy definition, so inactive definition entries normalize away and do not narrow public search. This remains YAML-backed and does not add a DB query to the index request.

### RED

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb
```

Result: `7 runs, 25 assertions, 2 failures, 0 errors, 0 skips`

Expected failures:

- A tag with three non-public assignments was incorrectly present in facet tags.
- An inactive taxonomy-definition category slug was incorrectly accepted by `Search::Selection`.

### GREEN

Facet count focused:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb
```

Result: `7 runs, 25 assertions, 0 failures, 0 errors, 0 skips`

Task 7 focused:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/search/facet_counts_test.rb test/services/search/resources_query_test.rb test/integration/public_discovery_test.rb
```

Result: `23 runs, 58 assertions, 0 failures, 0 errors, 0 skips`

Full suite:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
```

Result: `144 runs, 743 assertions, 0 failures, 0 errors, 0 skips`

SQL ceiling:

```powershell
docker compose run --rm -e RAILS_ENV=test -e PRINT_SQL_COUNT=1 web ruby bin/rails test test/integration/public_discovery_test.rb -n test_index_search_uses_a_bounded_number_of_SQL_queries_with_facet_counts
```

Result: measured index SQL count `12`; test result `1 runs, 3 assertions, 0 failures, 0 errors, 0 skips`.

### Lint and Diff Checks

```powershell
docker compose run --rm web bundle exec rubocop app/services/search/facet_counts.rb app/services/taxonomy/registry.rb test/services/search/facet_counts_test.rb test/integration/public_discovery_test.rb
```

Result: `4 files inspected, no offenses detected`

```powershell
docker compose run --rm web bundle exec rubocop
```

Result: `172 files inspected, no offenses detected`

```powershell
git diff --check
```

Result: exit 0, no whitespace errors.
