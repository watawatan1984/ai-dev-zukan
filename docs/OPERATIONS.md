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

## 主要な運用確認

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails test
docker compose run --rm web bin/rubocop
docker compose run --rm web bin/brakeman --no-pager
docker compose run --rm web bin/bundler-audit check --update
```

本番では`/up`、管理ダッシュボードのImportRun、ScheduledExecution、Solid Queue失敗ジョブ、Render logsを確認する。
