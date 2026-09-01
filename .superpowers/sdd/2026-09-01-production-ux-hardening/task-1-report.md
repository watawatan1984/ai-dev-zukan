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

## Final review fix wave

### RED

Behavior coverage was added before the final production changes:

- The Turbo before-cache system assertion verifies that the mobile opener is disabled again while cached, after the controller has reset transient state.
- Forward Tab from the final visible sheet control and Shift+Tab from the initial heading are asserted against the sheet boundary and explicitly reject the backdrop.
- A delayed real browser network request exposes aria-busy, disabled controls, and progress text; a second requestSubmit attempt is made while the first request is in flight and the request count is asserted to remain one.
- Definition-list tests require three dt and three dd elements.
- Query-only and facet-only zero-result tests require only the distinct full-reset action; the existing combined query-plus-facet test continues to require all three recovery choices.
- A deliberately long title is used to assert the source CTA precedes the detail header.

After correcting the system test's JavaScript execution helper and progress-label expectation, the pre-fix RED runs were:

~~~text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
14 runs, 151 assertions, 3 failures, 0 errors, 0 skips
~~~

Failures were the missing dt/dd semantics, the source CTA still following the detail header, and the duplicate query-only recovery action.

~~~text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test:system test/system/public_catalog_test.rb
12 runs, 76 assertions, 2 failures, 0 errors, 0 skips
~~~

Failures were the opener not being disabled after turbo:before-cache and the focus trap wrapping to the backdrop. The newly added delayed-submit behavior passed against the existing implementation and was retained as a regression contract.

### GREEN

After the minimum fixes and image rebuild:

~~~text
docker compose build web
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test test/integration/public_discovery_test.rb
14 runs, 168 assertions, 0 failures, 0 errors, 0 skips

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test:system test/system/public_catalog_test.rb
12 runs, 79 assertions, 0 failures, 0 errors, 0 skips
~~~

### Required verification

~~~text
docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails test
182 runs, 1100 assertions, 0 failures, 0 errors, 0 skips

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bundle exec rubocop
182 files inspected, no offenses detected

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bundle exec brakeman --no-pager
Errors: 0
Security Warnings: 0

docker run --rm --network ux-audit-fixes_default -e RAILS_ENV=test -e DATABASE_HOST=db -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=postgres ux-audit-fixes-web bin/rails tailwindcss:build
Done in 652ms

git diff --check
passed
~~~

### Changes and self-review

- resetTransientState disables the opener; connect remains the sole readiness transition that re-enables it after Stimulus reconnects.
- Focusable discovery is scoped to .filter-sheet and explicitly includes the initial heading, so the backdrop cannot enter the Tab sequence and both boundary directions remain inside the visible sheet.
- The source CTA is placed immediately before .detail-header, keeping it ahead of long titles while retaining the later source card.
- resource-definitions now uses valid dt/dd pairs with compact styling.
- Zero-result recovery actions are gated by one shared has_facet_filters condition, eliminating duplicate actions for query-only and facet-only states while preserving all three for combined states.
- The delayed network test uses Selenium Chromium network throttling and a real form submission; no dependency, route, schema, production Dockerfile, search semantics, scoring, taxonomy, or data changes were introduced.
- Changed files in this wave: app/assets/tailwind/application.css, app/javascript/controllers/facet_filter_controller.js, app/views/resources/_filter_panel.html.erb, app/views/resources/index.html.erb, app/views/resources/show.html.erb, test/integration/public_discovery_test.rb, and test/system/public_catalog_test.rb.
- The pre-existing untracked docs/superpowers/plans/2026-09-01-production-ux-hardening.md remains untouched.

Remaining concerns are unchanged: the Render 502 is outside this task, and the existing Rack future frozen-string warning remains pre-existing.
