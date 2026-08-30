# 0004: 初回公開は公開GitHub・Render標準ドメイン・400件公開で行う

- Status: Accepted
- Date: 2026-08-30

## Decision

GitHubリポジトリは公開し、`main`のCI成功をRenderデプロイの前提にする。初回公開はRenderの標準ドメインを使用し、MCP、Skills、Zenn、Qiitaを各100件、合計400件公開する。

公開操作の監査主体には、外部ログイン不能な予約済み`.invalid`ドメインのsystem adminを使う。実在する管理者メールアドレスは初回公開では作成しない。

## Rationale

ポートフォリオの主目的に対し、コード、CI、運用設計、初期データを採用担当者が確認できる公開証拠を優先する。実在メールを管理者IDへ流用せず、公開操作と人間のログインを分離することで監査ログの意味を明確にする。

## Constraints

- Render標準ドメインはメール送信ドメインとして所有・検証できない。
- Resendによる任意の登録者宛メール確認には、別途所有ドメインのDNS検証が必要である。
- Google OAuthはGoogle Cloudの利用規約同意とOAuthクライアント発行が完了するまで本番で有効化できない。
- Cloudflare R2のS3資格情報は対象bucketだけにObject Read & Writeを付与する。

## Verification

- GitHubリポジトリがPublicで、`main`のCIが成功していること。
- Renderの公開URLで`/up`、一覧、検索、ライト/ダーク切替、詳細、SEO出力を確認すること。
- 公開件数が種類ごとに100件、合計400件であること。
- 公開操作の監査ログが400件あり、system adminへ紐づくこと。
- R2、Supabase、GASの本番疎通結果を機密値なしで記録すること。

## Open Questions

- メール確認付き登録を初回公開に含める場合、どの所有ドメインをResendで検証するか。
