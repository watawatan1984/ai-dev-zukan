# Operations

## Render / Supabase

`render.yaml`からDocker Web Serviceを作成し、`.env.example`に列挙した値をRender Dashboardへ登録する。公開ホストはRenderが自動発行する`RENDER_EXTERNAL_HOSTNAME`を`APP_HOST`へ割り当てるため、初期公開では`*.onrender.com`をそのまま利用できる。

`DATABASE_URL`にはSupabase DashboardのConnectから取得したSession Pooler接続文字列を登録する。ポートは`5432`、末尾は`sslmode=require`とし、Transaction Poolerの`6543`はRailsの主接続に使わない。パスワード内の予約文字はURLエンコードする。アプリとSolid Queueは同じDBを使い、`db:prepare`で通常マイグレーションとして両方のテーブルを準備する。

今回の切替は公開前であり、移送すべき本番queue jobは存在しない。稼働済み環境を将来同じ構成へ切り替える場合は、先に新規enqueueを停止し、旧queue DBの`ready`、`scheduled`、`claimed`を0件まで処理する。`failed`を原因確認して必要な業務jobだけ再投入できる状態にしてから、新DBへ`db:prepare`を実行し、`DATABASE_URL`を切り替える。Solid Queueの内部行をDB間で直接コピーせず、未完了の業務jobは切替後にアプリのtaskから再投入する。切替に失敗した場合は旧`DATABASE_URL`と`QUEUE_DATABASE_URL`を復元し、旧構成のdeployへ戻す。

NVIDIAはRenderへ`NVIDIA_API_KEY`と`NVIDIA_NIM_MODEL`を1組だけ登録する。ローカル`env`の番号付き候補は検証用で、アプリは`NVIDIA_API_KEY` / `NVIDIA_NIM_MODEL`を優先し、未設定時のみ`NVIDIA_API_KEY1` / `NVIDIA_AI_MODEL1`へフォールバックする。モデル変更はRender環境変数の差し替えと管理画面上の要約・分類結果確認を経て行う。

Render Freeは15分間受信トラフィックがないと停止し、SMTPポートも利用できない。このためJST 10:00–20:59はGASから10分間隔でHTTPS tickを送り、確認・解除メールはResend HTTPS APIで配信する。各署名付きtickはRailsで`SELECT 1`を実行し、レスポンスの`database.status=reachable`をGASが確認する。

Supabase FreeはDB利用が少ない期間が続くと停止対象になる。GASによる継続クエリは停止リスクを下げるが、Freeプランで非停止を保証するものではない。停止後はSupabase Dashboardから手動でResumeする。

Render Freeは停止中の`/robots.txt`へ自動的に`Disallow: /`を返し、そのリクエストでは起動しない。`onrender.com`を使う初期公開ではRailsの動的robotsを利用し、Cloudflare Routeは設定しない。独自ドメインへ移行後、`ops/cloudflare/seo-edge-worker`をdeployし、`<APP_HOST>/robots.txt`の完全一致Routeだけを割り当てる。

## GASスリープ対策

1. `ops/gas`で`clasp create --type standalone --title "AI Dev Zukan Keepalive" --rootDir .`を実行し、`clasp push`で`appsscript.json`と`scheduler.gs`を同期する。既存Projectでは`.clasp.json`を復元して`clasp push`だけを行う。
2. Script Propertiesに次を登録する。
   - `SCHEDULER_TICK_URL`: `https://<APP_HOST>/internal/scheduler_tick`
   - `GAS_SCHEDULER_SECRET`: Renderの同名環境変数と同じ十分に長い乱数
3. `installSchedulerTrigger`を一度実行する。
4. Apps Scriptのタイムゾーンを`Asia/Tokyo`にする。

GASサブツール:

- `schedulerDiagnostics()`: URL・秘密値そのものを出さず、設定有無、時間帯、間隔、トリガー数を返す。
- `testSchedulerConnection()`: 時間帯に関係なく署名付きtickを1回送り、RenderとSupabaseの疎通を確認する。
- `installSchedulerTrigger()`: 既存の同名トリガーを整理し、10分間隔を1件だけ登録する。
- `uninstallSchedulerTriggers()`: `schedulerTick`のトリガーだけを削除し、他のGASトリガーは保持する。

Railsはtimestampと空bodyをHMAC-SHA256で検証し、5分を超えるリプレイを拒否する。同一時間帯への複数tickは`ScheduledExecution`の一意制約により`already_enqueued`になる。

## データ取込

1時間ごとの`CatalogRefreshJob`が`github_mcp`、`github_skill`、`zenn`、`qiita`を個別ジョブへ分割する。各実行は`ImportRun`へ取得件数、新規候補数、変更なし件数、失敗理由を記録する。

候補はAI要約後も自動公開されない。管理者が出典抜粋とAI要約を確認し、必要なら編集してから「承認して公開」を実行する。

### 初期カタログ400件の収集

GitHubとQiitaの読み取りトークン、NVIDIA設定を登録してから次を一度実行する。これはSourceImportJobを4件投入し、外部取得とNVIDIA要約はすべてSolid Queueで処理する。Webプロセス内の独自Threadや同期AI呼び出しは使わない。

```powershell
docker compose run --rm -e BOOTSTRAP_PER_KIND=100 web bin/rails catalog:bootstrap
```

Solid Queueの処理完了後に`bin/rails catalog:bootstrap:report`を実行する。失敗または未処理のAI要約は`bin/rails catalog:bootstrap:retry_summaries`で再投入でき、外部取得からやり直す必要はない。

180文字超過または日本語でない要約がある場合は`bin/rails catalog:bootstrap:repair`を実行し、続けて`bin/rails catalog:bootstrap:retry_summaries`で再要約する。

GitHubはMCPとSkillsをスター順に各100件、Qiitaは`QIITA_IMPORT_QUERY`、Zennはトレンドと複数の公式トピックRSSから各100件を取得する。GitHub README取得数は`GITHUB_README_FETCH_LIMIT`で抑え、それ以外はリポジトリ説明・言語・topicsを要約根拠にする。

GitHub選定条件を変更した既存DBでは、`catalog:bootstrap:curate_mcp`と`catalog:bootstrap:curate_skill`を実行する。現在の選定100件に含まれない未公開候補を削除せずアーカイブし、以前アーカイブした候補が再選定された場合は未公開へ戻す。

品質ゲート合格後、次のコマンドで要約済み400件をチェックサム付きの移送用Artifactへ書き出す。このファイルにはAPIキーを含めず、公開前の出典情報・要約・生成条件だけを保存する。

```powershell
docker compose run --rm web bin/rails catalog:snapshot:export
```

### Render / Supabaseへの初期投入と既存公開環境の更新

`render.yaml`の`initialDeployHook`が初回の正常デプロイ後に`bin/rails db:prepare catalog:snapshot:import catalog:bootstrap:release`を一度だけ実行する。空のSupabaseでもアプリとSolid Queueのテーブルを同じDBへ準備するため、ローカルDBへ固定されたDocker Composeコマンドに依存せず、同梱した`db/seed_data/initial_catalog.json`を冪等投入できる。形式、種類別件数、`records_sha256`、`taxonomy_sha256`が一致しなければ全体をtransactionで中止する。

snapshot import単体では400件を`review_pending`かつ`unpublished`で投入する。version 2 snapshot は、各recordの`revision.suggested_category_slugs`、`revision.suggested_tag_slugs`、`revision.search_keywords`、`revision.taxonomy_status`、`revision.taxonomy_origin`、`revision.taxonomy_provider`、`revision.taxonomy_model`、`revision.taxonomy_prompt_version`、`revision.taxonomy_input_sha256`、`revision.taxonomy_generated_at`、`revision.taxonomy_confidence`と、トップレベルの`taxonomy` / `taxonomy_sha256`を含む。今回承認された初回公開ではBlueprintに`INITIAL_CATALOG_RELEASE=publish`を固定し、同じ初回hookのrelease taskが品質ゲートを再検証する。release taskは`release-bot@ai-dev-zukan.invalid`のログイン不能なlocked system adminを冪等作成し、各100件を監査ログ付きで公開する。

既存のRender Freeデプロイですでに各kind 100件が公開済みの場合、`catalog:bootstrap:release`は初回公開用のためcurrent revisionを切り替えない。この場合はRender Shellで手作業実行せず、ローカル環境からSupabaseのSession Pooler `DATABASE_URL`を一時的に指定して、チェックサム済みsnapshotを既存公開リソースへ適用する。

```powershell
$env:DATABASE_URL="<Supabase Session Pooler URL with sslmode=require>"
$env:RAILS_ENV="production"
$env:INITIAL_CATALOG_SNAPSHOT="db/seed_data/initial_catalog.json"
$env:BOOTSTRAP_PER_KIND="100"
$env:INITIAL_CATALOG_SNAPSHOT_RELEASE="release-existing-catalog-snapshot"
bundle exec rails db:prepare catalog:snapshot:release_existing
```

`catalog:snapshot:release_existing`は、snapshotのtarget・kind別件数・`records_sha256`・`taxonomy_sha256`を検証し、同じtransaction内でimportと400件のcurrent revision切替を実行する。対象はsnapshotの`kind`、`provider`、`external_uid`、正規化URL、`source_fingerprint`が完全一致する既存公開リソースだけで、候補revisionはtaxonomy succeededかつcontrolled validation validでなければならない。確認文字列は初回公開の`INITIAL_CATALOG_RELEASE=publish`とは別の`INITIAL_CATALOG_SNAPSHOT_RELEASE=release-existing-catalog-snapshot`を使う。

成功後に同じtaskを再実行した場合は、current revisionがすでにsnapshot revisionを指していることとkind別100件を再検証し、`switched_count: 0`のno-opになる。失敗時はtransactionによりcurrent revisionの部分切替を残さない。旧approved revision、`resources.category_id`、legacy `resource_tags`はrollback用に保持し、削除しない。

空の環境で初回hookを使わずに手動で初回公開する場合だけ、品質レポートと管理画面のサンプルを確認した後、以下のtaskを本番環境で明示実行する。既存公開済み環境のsnapshot更新には使わない。

```powershell
ADMIN_EMAIL=release-bot@ai-dev-zukan.invalid CONFIRM=publish bin/rails catalog:bootstrap:publish
```

ローカル検証では同じtaskの前に`docker compose run --rm -e ... web`を付ける。本番一括公開はRender/Supabaseの資格情報を持つ実行環境だけで行い、品質ゲートと管理者権限を再検証する。

### Controlled taxonomy v2再分類

公開済み400件の分類を更新する場合は、既存のapproved revisionを直接編集しない。taxonomy-v2候補revisionを作り、AI分類、レビューartifact、品質ゲート、明示publishの順で進める。

ローカルDocker/WindowsではCRLF shebang警告を避けるため、`bin/rails`ではなく`ruby bin/rails`で実行する。

```powershell
docker compose run --rm web ruby bin/rails catalog:taxonomy:sync
docker compose run --rm web ruby bin/rails catalog:taxonomy:enqueue
docker compose run --rm web ruby bin/rails runner "fingerprints=Resource.publicly_visible.includes(:current_revision).map { |resource| Digest::SHA256.hexdigest([resource.current_revision.source_fingerprint, 'taxonomy-v2'].join(':')) }; File.write('tmp/taxonomy_candidate_ids.txt', ResourceRevision.where(source_fingerprint: fingerprints).order(:id).pluck(:id).join(','))"
docker compose run --rm -e NVIDIA_API_KEY -e NVIDIA_NIM_MODEL web ruby bin/rails runner "ids=File.read('tmp/taxonomy_candidate_ids.txt').split(',').map(&:to_i); ResourceRevision.where(id: ids, taxonomy_status: [:queued, :failed]).order(:id).find_each { |revision| revision.update!(taxonomy_status: :queued) if revision.taxonomy_status_failed?; ClassifyRevisionJob.perform_now(revision.id) }"
docker compose run --rm web ruby bin/rails catalog:taxonomy:export_review TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
docker compose run --rm web ruby bin/rails catalog:taxonomy:report TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
docker compose run --rm -e CONFIRM=publish-taxonomy-v2 web ruby bin/rails catalog:taxonomy:publish TAXONOMY_REVIEW_PATH=db/seed_data/taxonomy_review.json
docker compose run --rm web ruby bin/rails catalog:snapshot:export INITIAL_CATALOG_SNAPSHOT=db/seed_data/initial_catalog.json BOOTSTRAP_PER_KIND=100
```

AI分類runnerは`catalog:taxonomy:enqueue`直後に作成されたtaxonomy-v2候補fingerprintからIDセットを固定し、そのIDだけを処理する。`ResourceRevision.where(review_status: :draft, taxonomy_status: ...)`のような全体条件では、管理画面で作成した無関係なdraftやfailed candidateを巻き込むため使用しない。retryも同じIDセット内の`queued`/`failed`だけに限定する。

`taxonomy_review.json`の必須キーは`format`、`version`、`taxonomy_version`、`generated_at`、`records_sha256`、`records`。各recordは`resource_id`、`kind`、`title`、`category_slugs`、`tag_slugs`、`confidence`、`required_review`、`category_match`、`tag_match`、`review_note`を持つ。`category_match`と`tag_match`は必ず真偽値にする。低信頼度、失敗、検証不能な候補は`required_review: true`になり、全件レビュー必須。

品質ゲートはpublish前の候補に対して実行する。各kind 100件、全候補`succeeded`、カテゴリ1-3件、タグ2-6件、未知・重複値0件、required review完了、カテゴリ精度90%以上、タグ精度90%以上を要求する。publish後はcurrent revisionがtaxonomy-v2へ切り替わるため、同じreport taskではなく、400件のcurrent revisionがapprovedかつ`taxonomy_prompt_version`を持つこと、旧approved revisionが保持されていることをDB集計で確認する。NVIDIAがHTTP 503、message content欠落、途中で切れたJSON、許可リスト外の値を返した場合は、該当revisionだけ`queued`へ戻して再実行する。複数回同じ意味の分類ミスが再現する場合だけ、`config/taxonomy.yml`または`Ai::NvidiaTaxonomizer::PROMPT_VERSION`を伴うプロンプトを変更し、個別AI結果を手編集して品質を偽装しない。

rollbackは削除ではなく読み取り経路のrevertで行う。アプリをtaxonomy-v2適用前のrevisionへ戻すdeployを行い、`resources.category_id`と既存`resource_tags`を読む状態へ戻す。`resource_revisions`、`resource_categories`、`controlled_resource_tags`、`tags`、`tag_aliases`のtaxonomy-v2行は監査・再試行用に保持し、削除しない。

## 主要な運用確認

```powershell
docker compose run --rm -e RAILS_ENV=test web ruby bin/rails test
docker compose run --rm web bundle exec rubocop
docker compose run --rm web bundle exec brakeman --no-pager
docker compose run --rm web bundle exec bundler-audit check --update
```

本番では`/up`、管理ダッシュボードのImportRun、ScheduledExecution、Solid Queue失敗ジョブ、Render logsを確認する。
