# Task 2 Report: Controlled Taxonomy Approval Boundary

## Status

Complete.

Implemented approval-time controlled taxonomy validation/application, controlled search text extraction, invalid-taxonomy rollback behavior, and audit diffs for controlled category/tag IDs.

## Files Changed

- `app/services/taxonomy/validate_suggestion.rb` - added validator with canonical category/tag validation, registered tag alias resolution, count/duplicate checks, keyword bounds, and content-type tag rejection.
- `app/services/taxonomy/apply_revision.rb` - replaced dynamic legacy category/tag creation with atomic controlled `ResourceCategory` and `ControlledResourceTag` replacement.
- `app/services/search/index_text.rb` - added controlled taxonomy-aware search text builder.
- `app/services/editorial/approve_and_publish.rb` - validates taxonomy before approval, preserves rollback on invalid taxonomy, and records controlled ID diffs.
- `app/models/resource.rb` - delegates publish-time search text construction to `Search::IndexText`.
- `test/services/taxonomy/validate_suggestion_test.rb` - added validator coverage for valid ranges, unknowns, duplicates, alias resolution, no unknown parameterization, content-type restatement, and keyword bounds.
- `test/services/editorial/approve_and_publish_test.rb` - updated approval coverage for controlled joins/audit diff and invalid-taxonomy no-op behavior.
- `test/models/resource_publication_test.rb` - updated publication search text coverage for controlled categories/tags, aliases, capabilities, key points, and keywords.
- `test/services/initial_catalog/publish_test.rb` - aligned full-suite publication fixtures with the new approval precondition by seeding/providing controlled taxonomy.

## RED

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/taxonomy/validate_suggestion_test.rb test/services/editorial/approve_and_publish_test.rb test/models/resource_publication_test.rb
```

Output:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
/usr/bin/env: 'ruby\r': No such file or directory
/usr/bin/env: use -[v]S to pass options in shebang lines
Running 13 tests in a single process (parallelization threshold is 50)
Run options: --seed 8145

# Running:

.F

Failure:
Editorial::ApproveAndPublishTest#test_admin_approval_publishes_the_revision_and_records_an_audit_log [test/services/editorial/approve_and_publish_test.rb:37]:
Expected ResourceTag collection to be empty.

E

Error:
Editorial::ApproveAndPublishTest#test_invalid_taxonomy_cannot_become_approved_or_change_publication_state:
NameError: uninitialized constant Taxonomy::ApplyRevision::InvalidSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_resolves_tag_aliases_before_validation:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_rejects_unknown,_duplicate,_underfilled,_and_overfilled_values:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_rejects_content_type_tags_that_only_restate_mcp_or_skill_resources:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_accepts_one_to_three_categories_and_two_to_six_canonical_tags:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_normalizes_and_bounds_search_keywords:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

E

Error:
Taxonomy::ValidateSuggestionTest#test_allows_mcp_and_agent_skills_tags_on_blog_resources:
NameError: uninitialized constant Taxonomy::ValidateSuggestion

.F

Failure:
ResourcePublicationTest#test_approved_revision_becomes_the_current_published_revision [test/models/resource_publication_test.rb:63]:
Expected "example skill a rails testing skill." to include "generates tests".

Finished in 6.718759s, 1.9349 runs/s, 5.5070 assertions/s.
13 runs, 37 assertions, 2 failures, 7 errors, 0 skips
```

## GREEN

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test test/services/taxonomy/validate_suggestion_test.rb test/services/editorial/approve_and_publish_test.rb test/models/resource_publication_test.rb
```

Output:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
/usr/bin/env: 'ruby\r': No such file or directory
/usr/bin/env: use -[v]S to pass options in shebang lines
Running 14 tests in a single process (parallelization threshold is 50)
Run options: --seed 25993

# Running:

..............

Finished in 7.953279s, 1.7603 runs/s, 12.1962 assertions/s.
14 runs, 97 assertions, 0 failures, 0 errors, 0 skips
```

## Full Suite

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
```

Output:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
tailwindcss v4.3.3
Done in 2s
/usr/bin/env: 'ruby\r': No such file or directory
/usr/bin/env: use -[v]S to pass options in shebang lines
Running 84 tests in parallel using 6 processes
Run options: --seed 64474

# Running:

..........................................
... Rack literal string frozen warnings ...
..........................................

Finished in 6.612040s, 12.7041 runs/s, 61.5544 assertions/s.
84 runs, 407 assertions, 0 failures, 0 errors, 0 skips
```

## Additional Verification

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rubocop
```

Output:

```text
bin/rubocop:1: warning: shebang line ending with \r may cause problems
Inspecting 156 files
............................................................................................................................................................
156 files inspected, no offenses detected
```

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails zeitwerk:check
```

Output:

```text
bin/rails:1: warning: shebang line ending with \r may cause problems
Hold on, I am eager loading the application.
All is good!
```

Command:

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
```

Output:

```text
bin/brakeman:1: warning: shebang line ending with \r may cause problems
Errors: 0
Security Warnings: 0
No warnings found
```

Command:

```powershell
git diff --check
```

Output:

```text
warning: in the working copy of 'app/models/resource.rb', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'app/services/editorial/approve_and_publish.rb', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'app/services/taxonomy/apply_revision.rb', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'test/models/resource_publication_test.rb', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'test/services/editorial/approve_and_publish_test.rb', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'test/services/initial_catalog/publish_test.rb', LF will be replaced by CRLF the next time Git touches it
```

Command:

```powershell
rg "find_or_create_by!|Category\.create!|Tag\.create!|find_or_initialize_by" app/services/taxonomy app/services/editorial app/models/resource.rb app/services/search -n
```

Output:

```text
app/services/editorial\create_manual_candidate.rb:21:        revision = resource.revisions.find_or_create_by!(source_fingerprint: source_fingerprint) do |candidate|
app/services/editorial\create_manual_candidate.rb:41:      Resource.find_or_initialize_by(
app/services/taxonomy\sync_vocabulary.rb:24:        category = Category.find_or_initialize_by(slug: category_attributes.fetch("slug"))
app/services/taxonomy\sync_vocabulary.rb:37:        tag = Tag.find_or_initialize_by(slug: tag_attributes.fetch("slug"))
app/services/taxonomy\sync_vocabulary.rb:53:        tag.tag_aliases.find_or_initialize_by(normalized_name: normalized_name).update!(name: alias_name)
```

No forbidden category/tag creation remains in validation, approval, application, model publish, or search indexing. Category/tag initialization remains in `Taxonomy::SyncVocabulary`, the existing controlled vocabulary sync path.

## Self Review

- Approval validates before any `review_status` mutation, so invalid taxonomy leaves the revision review state, resource publication/current revision, legacy category/tags, controlled joins, and search text unchanged.
- `Taxonomy::ApplyRevision` validates again at the application boundary and replaces controlled category/tag joins inside a transaction using `revision.taxonomy_origin`.
- Legacy `resources.category_id` and `resource_tags` are no longer written by application/approval.
- `Search::IndexText` includes title, author, summary, capabilities, key points, controlled category names, controlled canonical tag names, controlled tag aliases, and revision search keywords.
- Unknown tag/category inputs are not dynamically created. Unknown tag display text such as `Ruby on Rails` is not parameterized into `ruby-on-rails` unless it is registered as an alias.

## Concerns

- The known Windows CRLF binstub warnings and Rack frozen-string warnings still appear during Docker commands, matching the task's allowed warning context.
- `test/services/initial_catalog/publish_test.rb` was not in the initial file list, but the full suite failed until its old fixture revisions were given valid controlled taxonomy. This is test-data alignment with the new approval contract, not a production-path expansion.
