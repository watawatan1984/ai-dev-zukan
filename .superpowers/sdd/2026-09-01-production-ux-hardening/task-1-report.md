# Task 1 report — complete public discovery flow hardening

## Result

Implemented the approved Task 1 UX hardening on `codex/ux-audit-fixes`. No production deploy, push, merge, migration, schema, route, taxonomy, search semantics, scoring, or data changes were made.

## TDD evidence

Behavior tests were added before the production changes.

### RED

Command:

```text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
```

Important output:

```text
13 runs, 96 assertions, 5 failures, 0 errors, 0 skips
```

The failures were the missing search/help copy, zero-result recovery actions, registration benefit, safe return path, Japanese dates/provider popularity, and early source CTA contracts.

### GREEN

After the minimum implementation slices, the final focused integration run was:

```text
docker compose build web
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
```

Output:

```text
12 runs, 139 assertions, 0 failures, 0 errors, 0 skips
```

The final system behavior run was:

```text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test:system test/system/public_catalog_test.rb
```

Output:

```text
10 runs, 65 assertions, 0 failures, 0 errors, 0 skips
```

The brief's literal `bin/rails test:system TEST=test/system/public_catalog_test.rb` form is rejected by this Rails runner as an invalid test file argument; the equivalent path argument above passes.

## Verification

- `docker compose build web`: passed. `Dockerfile.dev` now installs Chromium and Chromium Driver and builds the Tailwind development asset in the image.
- Image-only `bin/rails db:prepare`: passed against the existing `db` service.
- Focused integration: 12 runs, 139 assertions, 0 failures.
- `public_catalog` system test: 10 runs, 65 assertions, 0 failures.
- Full Rails suite: 180 runs, 1071 assertions, 0 failures, 0 errors, 0 skips. Existing Rack frozen-string warnings remain.
- `bundle exec rubocop`: 182 files inspected, no offenses.
- `bundle exec brakeman -q`: 0 errors, 0 security warnings.
- `bin/rails tailwindcss:build`: passed.
- `git diff --check`: passed.

## Changed files

- `Dockerfile.dev`
- `app/assets/tailwind/application.css`
- `app/controllers/resources_controller.rb`
- `app/helpers/application_helper.rb`
- `app/javascript/controllers/facet_filter_controller.js`
- `app/views/layouts/application.html.erb`
- `app/views/resources/_active_filters.html.erb`
- `app/views/resources/_filter_panel.html.erb`
- `app/views/resources/_resource_card.html.erb`
- `app/views/resources/index.html.erb`
- `app/views/resources/show.html.erb`
- `config/locales/ja.yml`
- `test/application_system_test_case.rb`
- `test/integration/public_discovery_test.rb`
- `test/system/public_catalog_test.rb`

## Self-review

- Mobile filter behavior is exercised through Chromium: readiness, dialog semantics, focus restoration, inert background, focus trapping, Escape/backdrop close, submit state, duplicate-submit guard, Turbo result focus, and direct filtered URL focus suppression.
- Return paths are URI-parsed and restricted to same-origin `/resources` paths; unsafe, protocol-relative, malformed, and non-resource values fall back to `/resources`. Detail canonical metadata remains unchanged.
- Copy and labels explain OR/AND semantics, facet count meaning, resource definitions, accessible active-chip removal, zero-result recovery, registration benefit, Japanese dates, provider-specific popularity, and source CTAs.
- Chromium `--no-sandbox` is configured only for the test system driver because the image-only test container runs as root; the production Dockerfile is untouched.
- The existing untracked `docs/superpowers/plans/2026-09-01-production-ux-hardening.md` was preserved and is not part of this task's commit.

## Remaining concerns

- The intermittent Render 502 is not claimed fixed, per the ledger ruling; production diagnosis remains separate.
- The existing Rack future frozen-string warning predates this task.

## Fix round 1 — review findings

### RED

Before the review fixes, the covering behavior tests were extended to assert the three missing contracts:

- The mobile dialog test asserts real catalog descendants (`.hero` and `.results-panel`) become inert while the sheet is open, then asserts the `facet-filter:interaction` session flag is removed during `turbo:before-cache`.
- The return-path integration test rejects `/resources/other` and `/resources/../../admin` in addition to the existing unsafe values.

Commands and important output:

```text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
12 runs, 142 assertions, 1 failure, 0 errors, 0 skips
```

The failure was the newly covered `/resources/...` return path being accepted.

```text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test:system test/system/public_catalog_test.rb
10 runs, 62 assertions, 1 failure, 0 errors, 0 skips
```

The failure was the newly covered `.hero.inert` assertion; the existing header assertion alone had passed.

### GREEN

After the minimum fixes and development-image rebuild:

```text
docker compose build web
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
12 runs, 145 assertions, 0 failures, 0 errors, 0 skips

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test:system test/system/public_catalog_test.rb
10 runs, 68 assertions, 0 failures, 0 errors, 0 skips
```

Additional verification after the fix:

```text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bundle exec rubocop app/helpers/application_helper.rb
1 file inspected, no offenses detected

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bundle exec brakeman --no-pager
Errors: 0
Security Warnings: 0

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test
180 runs, 1077 assertions, 0 failures, 0 errors, 0 skips
```

### Changes and self-review

- `setBackgroundInert` now directly marks every non-dialog catalog descendant inert, while excluding the dialog and all of its descendants; closing the sheet clears those states. The dialog itself is not inert.
- `resetTransientState` removes `facet-filter:interaction`, so both `turbo:before-cache` and `disconnect` clear the session flag. The module-scoped submit marker preserves intentional post-filter Turbo result focus without leaving session storage stale.
- `safe_return_path` now accepts only the exact `/resources` index path, retaining optional query and fragment components through URI parsing; detail-like, traversal-shaped, malformed, external, and protocol-relative values fall back to `/resources`.
- No unrelated files were reverted. The pre-existing untracked plan remains untouched.

Fix-round residual concerns are unchanged: the Render 502 remains outside this task, and Rack's future frozen-string warning remains pre-existing.
