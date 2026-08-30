# 0005 Google OAuth一般公開と法務ページ

- 日付: 2026-08-30
- 状態: 採用

## 決定

Google OAuthを外部ユーザーへ一般公開するため、公開ホームページにプライバシーポリシーと利用規約を追加する。OAuthのブランディングにはRenderの本番URLを使用し、Googleログインの資格情報はRenderの環境変数だけに保存する。

## 理由

Google Auth Platformの公開要件を満たし、ユーザーが取得情報、外部サービス、AI要約の位置づけを事前に確認できるようにするため。Client Secretはリポジトリへ保存しない。

## 運用上の注意

- Google Cloudの有料アカウント化は行わない。
- 認証スコープは基本プロフィールとメールアドレスに限定する。
- OAuth Client Secretは画面やログへ出力せず、RenderのSecret環境変数で管理する。
