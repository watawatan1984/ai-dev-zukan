# 0003: Supabaseの単一PostgreSQLへアプリとSolid Queueを統合する

- Status: Accepted
- Date: 2026-08-30
- Supersedes: `0001-foundation.md`のNeon採用部分

## Decision

本番DBをNeonからSupabase PostgreSQLへ変更する。RailsはSupabase Session Poolerの`5432`へ`sslmode=require`で接続し、Transaction Poolerは使わない。Supabaseの1つのDBへアプリテーブルとSolid Queueテーブルを通常マイグレーションで作成し、`QUEUE_DATABASE_URL`と専用queue DBを廃止する。

GASはJST 10:00–20:59に10分間隔でRenderの署名付きScheduler endpointを呼ぶ。Railsは取込処理の冪等判定前に`SELECT 1`を実行し、GASはレスポンスのDB到達性を検証する。GASには設定診断、手動疎通、トリガーの冪等登録、対象トリガーだけの削除を用意する。

## Rationale

Supabase FreeではProject数と運用を増やさず、1つのPostgreSQLへ集約する方がポートフォリオ運用の理解と復旧が容易である。Solid Queue公式のsingle database構成に従い、Queue schemaを通常マイグレーションへ移す。

Supabase Freeは利用が少ないProjectを停止する可能性がある。継続クエリは停止リスクを下げるが保証ではなく、確実な非停止が必要な場合はProプランを選ぶ。

## Verification

- production database configが`primary`だけであること。
- primary DBにSolid Queueテーブルが存在すること。
- 署名付きtickが`database.status=reachable`を返すこと。
- GASサブツールをNodeの隔離runtimeで検証すること。
- Supabase実DBへマイグレーションと初期400件を投入し、件数と品質ゲートを確認すること。
