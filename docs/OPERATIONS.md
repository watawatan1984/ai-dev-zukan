# Operations

## Render / Neon

`render.yaml`からDocker Web Serviceを作成し、`.env.example`に列挙した値をRender Dashboardへ登録する。公開ホストはRenderが自動発行する`RENDER_EXTERNAL_HOSTNAME`を`APP_HOST`へ割り当てるため、初期公開では`*.onrender.com`をそのまま利用できる。`DATABASE_URL`はアプリ用、`QUEUE_DATABASE_URL`はSolid Queue用の別データベースを指す。同じNeon Project内でもデータベースを分け、Railsの`db:prepare`で両方を準備する。

NVIDIAはRenderへ`NVIDIA_API_KEY`と`NVIDIA_NIM_MODEL`を1組だけ登録する。ローカル`env`の番号付き候補を自動ローテーションする設計にはせず、モデル変更はRender環境変数の差し替えと管理画面上の要約結果確認を経て行う。

Render Freeは15分間受信トラフィックがないと停止し、SMTPポートも利用できない。このためJST 10:00–20:59はGASから10分間隔でHTTPS tickを送り、確認・解除メールはResend HTTPS APIで配信する。

Render Freeは停止中の`/robots.txt`へ自動的に`Disallow: /`を返し、そのリクエストでは起動しない。`onrender.com`を使う初期公開ではRailsの動的robotsを利用し、Cloudflare Routeは設定しない。独自ドメインへ移行後、`ops/cloudflare/seo-edge-worker`をdeployし、`<APP_HOST>/robots.txt`の完全一致Routeだけを割り当てる。

## GASスリープ対策

1. Apps Scriptへ`ops/gas/scheduler.gs`を貼り付ける。
2. Script Propertiesに次を登録する。
   - `SCHEDULER_TICK_URL`: `https://<APP_HOST>/internal/scheduler_tick`
   - `GAS_SCHEDULER_SECRET`: Renderの同名環境変数と同じ十分に長い乱数
3. `installSchedulerTrigger`を一度実行する。
4. Apps Scriptのタイムゾーンを`Asia/Tokyo`にする。

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

### Render / Neonへの初期投入

`render.yaml`の`initialDeployHook`が初回の正常デプロイ後に`bin/rails db:prepare catalog:snapshot:import`を一度だけ実行する。空のNeonでも先にprimary/queue schemaを準備するため、ローカルDBへ固定されたDocker Composeコマンドに依存せず、同梱した`db/seed_data/initial_catalog.json`を冪等投入できる。形式、種類別件数、SHA-256が一致しなければ全体をtransactionで中止する。

投入された400件はすべて`review_pending`かつ`unpublished`であり、初回デプロイだけで自動公開されることはない。管理者はWeb管理画面で出典と要約を確認して個別公開するか、品質レポートと管理画面のサンプルを確認した後、以下のtaskを本番環境で明示実行して各100件を監査ログ付きで公開する。

```powershell
ADMIN_EMAIL=admin@example.com CONFIRM=publish bin/rails catalog:bootstrap:publish
```

ローカル検証では同じtaskの前に`docker compose run --rm -e ... web`を付ける。本番一括公開はRender/Neonの資格情報を持つ実行環境だけで行い、品質ゲートと管理者権限を再検証する。

## 主要な運用確認

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test
docker compose run --rm web bin/rubocop
docker compose run --rm web bin/brakeman --no-pager
docker compose run --rm web bin/bundler-audit check --update
```

本番では`/up`、管理ダッシュボードのImportRun、ScheduledExecution、Solid Queue失敗ジョブ、Render logsを確認する。
