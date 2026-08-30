# 0001: MVP foundation decisions

Status: accepted

## Decision

- 採用・副業案件向けRailsポートフォリオを主目的、実運用を従目的にする。
- サービス表示名は「AI開発図鑑」、リポジトリ名は`ai-dev-zukan`とする。
- Rails SSR/Hotwireの単一アプリにし、Next.js/Vercel/Redis/UpstashはMVPに入れない。
- 外部データはResource、内容の候補版はResourceRevisionへ分離し、管理者承認前は公開しない。
- 承認済みRevisionは不変にし、承認されたカテゴリ・タグだけを公開Resourceへ反映する。
- 人気度は媒体別の対数正規化スコアで並び替え、カードには取得元のスター・いいね実数を表示する。
- NVIDIAのモデルは`NVIDIA_NIM_MODEL`で外部設定し、リポジトリでは固定しない。
- Render Freeの制約に合わせ、Solid QueueをPumaから監督し、GASで10:00–20:59 JSTに10分間隔の署名付きtickを送る。
- メールはSMTPではなくResend HTTPS API、画像はCloudflare R2を使う。DBのNeon採用は`0003-supabase-single-database.md`でSupabaseへ置き換えた。
- Render停止中のrobots全拒否を避けるため、`/robots.txt`だけはCloudflare Workerから返す。

## Consequences

- 無料構成でも外部Workerなしで運用証拠を残せる一方、WebとジョブがCPU・メモリを共有する。
- 自動取込の即時公開はできないが、誤要約や出典変更を管理者が止められる。
- 高度な意味検索より、説明可能な検索順位・共通タグ推薦を優先する。
