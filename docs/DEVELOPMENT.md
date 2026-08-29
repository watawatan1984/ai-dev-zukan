# Development

## 必要環境

- Docker Desktop
- Git

ホストOSへのRuby、PostgreSQL、Node.jsのインストールは不要。

## 起動

```powershell
docker compose build web
docker compose run --rm web bin/rails db:prepare
docker compose up web
```

`http://localhost:3000`を開く。

## テスト

```powershell
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test
```

## 品質確認

```powershell
docker compose run --rm web bin/rubocop
docker compose run --rm web bin/brakeman --no-pager
docker compose run --rm web bin/bundler-audit check --update
```

テストは公開Interfaceの振る舞いを検証し、内部クラスの呼出回数やprivateメソッドを検証しない。外部HTTPと時刻だけをAdapterで置き換える。
