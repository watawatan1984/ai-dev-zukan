# 0002: 初期カタログを4種類各100件で構成する

- Status: Accepted
- Date: 2026-08-30

## Decision

初期公開候補としてMCP、Skills、Zenn、Qiitaを各100件収集し、各Resourceの最新RevisionをNVIDIA NIMで日本語要約する。公開前品質ゲートでは、種類ごとの有効Resource数・要約済み数・レビュー待ち数が100以上、空要約0、非日本語要約0、180文字超過0であることを要求する。

GitHubは公式Repository Searchを利用し、MCPは名称がサーバー実装を示すもの、Skillsは名称または説明に`skill` / `SKILL.md`が明示されたものへ限定する。Qiitaは公式API、Zennは公式トレンド・トピックRSSを利用する。重複は外部IDと正規化URLで排除する。

AI要約だけでは公開せず、管理者による明示的な一括承認時も品質ゲートを再実行し、Resourceごとの最新Revisionだけを監査ログ付きで公開する。

## Rationale

GitHub topicだけではMCPクライアント、SDK、汎用アプリが混在した。検索件数より紹介対象の正確さを優先し、選定集合に含まれない未公開候補は削除せずアーカイブする。NVIDIAの一時的なHTTPエラーや不完全JSONに備え、要約は再実行可能にし、実際のモデル名・プロンプト版・入力ハッシュをRevisionへ保持する。

## Verification

開発DBで4種類各100件の有効Resourceと最新AI要約を確認した。品質ゲートは合格し、空要約・非日本語要約・180文字超過・重複URLはいずれも0件だった。公開数は管理者承認前のため0件を維持する。
