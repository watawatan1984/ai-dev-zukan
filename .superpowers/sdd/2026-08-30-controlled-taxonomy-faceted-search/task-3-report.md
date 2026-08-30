# Task 3 Report: Separate NVIDIA Classification from Summarization

## Status

Complete.

## Files Changed

- `app/integrations/ai/taxonomy_suggestion.rb` - added typed taxonomy classification result.
- `app/integrations/ai/nvidia_taxonomizer.rb` - added constrained NVIDIA taxonomy classifier using the existing endpoint/key/model conventions.
- `app/services/taxonomy/generate_suggestion.rb` - added lifecycle-safe taxonomy persistence and validation boundary.
- `app/jobs/classify_revision_job.rb` - added retryable classification job.
- `app/integrations/ai/nvidia_summarizer.rb` - removed taxonomy fields from new summary prompts and result construction.
- `app/integrations/ai/summary.rb` - removed summary-owned taxonomy fields from the typed summary result.
- `app/services/ai/generate_summary.rb` - stopped writing taxonomy suggestions during summarization; now queues classification after successful summary persistence.
- `test/integrations/ai/nvidia_taxonomizer_test.rb` - added constrained request and parser rejection coverage.
- `test/services/taxonomy/generate_suggestion_test.rb` - added lifecycle, validation, failure, and idempotent claim coverage.
- `test/integrations/ai/nvidia_summarizer_test.rb` - updated summary contract coverage to exclude taxonomy authority.
- `test/services/ai/generate_summary_test.rb` - updated summary persistence coverage to queue taxonomy classification without writing suggestions.

## RED Evidence

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb
```

Result:

```text
15 runs, 27 assertions, 1 failures, 8 errors, 0 skips
```

Expected failures/errors were captured for missing `Ai::TaxonomySuggestion`, missing `Ai::NvidiaTaxonomizer`, and summary prompts still requesting `suggested_category_slug` / `suggested_tag_slugs`.

Ledgered warnings:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
/usr/bin/env: 'ruby\r': No such file or directory
```

## GREEN Evidence

Focused command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb
```

Focused result:

```text
15 runs, 103 assertions, 0 failures, 0 errors, 0 skips
```

Full Rails command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
```

Full Rails result:

```text
94 runs, 485 assertions, 0 failures, 0 errors, 0 skips
```

Style command:

```powershell
docker compose run --rm -e RAILS_ENV=test web bundle exec rubocop
```

Style result:

```text
162 files inspected, no offenses detected
```

Whitespace command:

```powershell
git diff --check
```

Whitespace result: no whitespace errors. Git emitted expected CRLF conversion notices for existing files.

## Lifecycle And Concurrency Behavior

- `Taxonomy::GenerateSuggestion` atomically claims only `taxonomy_not_requested`, `taxonomy_queued`, or retryable `taxonomy_failed` revisions by moving them to `taxonomy_processing`.
- The network call runs only after the processing state and taxonomy input SHA are stored.
- Already succeeded or currently processing revisions are no-ops, which keeps retries and concurrent duplicate jobs idempotent.
- Valid classifier output is revalidated through `Taxonomy::ValidateSuggestion` before persistence.
- Invalid classifier output marks only the candidate revision failed and does not mutate the currently published resource or resource taxonomy assignments.
- Classification persistence updates plural category slugs, canonical tag slugs, normalized search keywords, confidence, provider, model, prompt version, origin, generated timestamp, and status.

## Self-Review

- No API keys, source bodies, or full model responses are logged.
- NVIDIA configuration and HTTP timeout/failure conventions match the existing summarizer.
- Summary generation remains independent: new summary prompts do not request taxonomy fields, `Ai::Summary` no longer carries taxonomy suggestions, and `Ai::GenerateSummary` no longer writes suggestion columns.
- Legacy revision columns and admin/editorial flows were preserved.
- No dependencies were added.

## Concerns

- The Docker Rails command continues to emit the known CRLF shebang warning before tests run.
- Taxonomy assignment to published resources remains governed by the existing approval path; this task only persists validated suggestions on revisions.

## Fix Round 1

### Status

Complete.

### Findings Addressed

- `Ai::NvidiaTaxonomizer` now requires `category_slugs`, `tag_slugs`, and `search_keywords` to be present JSON arrays before normalization. Scalar, missing, and malformed values raise `Ai::NvidiaTaxonomizer::ProviderError`.
- `Taxonomy::GenerateSuggestion` no longer claims approved revisions and failure persistence is constrained to non-approved revisions, so a late provider error cannot mark an approved revision failed.

### Covering Tests

- `test/integrations/ai/nvidia_taxonomizer_test.rb` - added scalar `category_slugs`, scalar `tag_slugs`, scalar `search_keywords`, and missing `search_keywords` regression coverage.
- `test/services/taxonomy/generate_suggestion_test.rb` - added approved claimable revision no-op coverage and late-approval provider-error coverage.

### RED Evidence

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb
```

Result:

```text
9 runs, 57 assertions, 1 failures, 1 errors, 0 skips
```

Failure/error captured:

```text
Ai::NvidiaTaxonomizer::ProviderError expected but nothing was raised.
RuntimeError: approved revisions must not be classified
```

Ledgered warnings:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
/usr/bin/env: 'ruby\r': No such file or directory
```

### GREEN Evidence

Affected taxonomy command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb
```

Affected taxonomy result:

```text
9 runs, 66 assertions, 0 failures, 0 errors, 0 skips
```

Late-approval service command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/taxonomy/generate_suggestion_test.rb
```

Late-approval service result:

```text
5 runs, 38 assertions, 0 failures, 0 errors, 0 skips
```

Task 3 focused command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/integrations/ai/nvidia_taxonomizer_test.rb test/services/taxonomy/generate_suggestion_test.rb test/integrations/ai/nvidia_summarizer_test.rb test/services/ai/generate_summary_test.rb
```

Task 3 focused result:

```text
18 runs, 118 assertions, 0 failures, 0 errors, 0 skips
```

Full Rails command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
```

Full Rails result:

```text
97 runs, 500 assertions, 0 failures, 0 errors, 0 skips
```

Style command:

```powershell
docker compose run --rm -e RAILS_ENV=test web bundle exec rubocop
```

Style result:

```text
162 files inspected, no offenses detected
```

Whitespace command:

```powershell
git diff --check
```

Whitespace result: no whitespace errors. Git emitted expected CRLF conversion notices for changed files.

### Self-Review

- The classifier parser no longer uses `Array(...)` as a coercion boundary for model-owned fields.
- The service claim path and late failure path both exclude approved revisions at the database update boundary.
- No dependencies, schema changes, public taxonomy vocabulary changes, logging changes, or summary authority changes were introduced.
