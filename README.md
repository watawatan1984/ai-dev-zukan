# AI開発図鑑

MCP・Skills・技術記事を、出典付きAI要約から探せる日本語のAI開発者向けライブラリーです。

## 実装済み

- 出典付きAI要約を表示する公開検索・詳細画面
- 種類、カテゴリ、タグ、人気、新着、全文検索
- メール確認付き認証、Google OAuth、ブックマーク、非表示
- 管理者の手動追加、自動取込候補、編集、承認公開、監査ログ
- GitHub MCP/Skills、Qiita API、Zenn RSSの非同期取込
- NVIDIA NIMのモデル差し替え可能な要約Adapter
- Solid Queue、取込実績、GAS署名付き10分監視
- ライト／ダーク／システムテーマ、SSR、canonical、JSON-LD、sitemap

## Stack

- Ruby 3.4 / Rails 8.1
- Hotwire, Stimulus, Tailwind CSS
- PostgreSQL / Solid Queue
- Render / Neon / Cloudflare R2
- Devise / Google OAuth
- NVIDIA NIM
- Resend HTTPS API

## Documentation

- [PRD](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Operations](docs/OPERATIONS.md)

## Local development

```powershell
docker compose build web
docker compose run --rm web bin/rails db:prepare
docker compose up web
```

See `docs/DEVELOPMENT.md` for tests and quality checks.
