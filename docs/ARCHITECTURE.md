# Architecture

## システム構成

RailsのSSRモノリスを中心にする。ブラウザーと管理者はCloudflare経由でRender上のRailsへ接続し、永続データはNeon PostgreSQL、プロジェクト所有画像はCloudflare R2へ保存する。外部取得とAI要約はSolid Queueで非同期実行する。

## 主要Module

- `Editorial`: Resourceの版作成、レビュー、公開を扱う深いModule
- `Ingestion`: 外部Snapshotの重複排除とRevision作成を扱う深いModule
- `Sources`: GitHub、Qiita、Zennの外部Adapterが満たすSeam
- `Ai`: NVIDIA実装とテスト用Adapterが満たすSeam
- `Search`: 公開Resourceの検索と順位付けを扱うQuery Module
- `Recommendations`: 種類、カテゴリ、共通タグから説明可能な候補を返すModule
- `Scheduler`: GASの署名を検証し、時間単位の取込処理を冪等に投入するModule

コントローラーとジョブは同じModuleのInterfaceを呼ぶ。HTTPクライアントやAIクライアントをコントローラーから直接呼ばない。

## ResourceとRevision

`Resource`は外部コンテンツの恒久的な識別子で、`ResourceRevision`は公開候補となる内容の版である。公開画面は`Resource.current_revision`だけを参照する。新しい外部Snapshotは新しいRevisionになり、管理者承認まで公開版を変更しない。

## 外部コンテンツ方針

Qiitaは公式API、ZennはRSS、GitHubは公式REST APIを利用する。記事本文とREADME全文は永続化しない。DBには上限付き出典抜粋、AI要約、出典URL、生成条件だけを保存する。

## デプロイ制約

Render Freeの停止を前提に、ジョブは短く、再実行可能かつ冪等にする。Solid Queueは単一Web Service内で低並列に実行する。GASはJST 10:00–20:59に10分間隔で署名付きScheduler tickを送り、同一時刻枠・同一タスクの一意制約で取込を1時間に1回だけ投入する。メールはRender Freeで遮断されるSMTPではなくResend HTTPS APIを使う。
