# Development

## 必要環境

- Docker Desktop
- Git

ホストOSへのRuby、PostgreSQL、Node.jsのインストールは不要。

プロジェクト直下の`env`は任意のローカル機密ファイルとしてDocker Composeが読み込む。Gitでは除外される。NVIDIA設定は標準名`NVIDIA_API_KEY` / `NVIDIA_NIM_MODEL`を優先し、未定義の場合は`NVIDIA_API_KEY1` / `NVIDIA_AI_MODEL1`を主設定として利用する。番号2以降は自動ローテーションせず、Renderへ登録するキーは明示的に1本を選ぶ。

初期データは`bin/rails catalog:bootstrap`で4種類各100件のSourceImportJobを投入し、外部取得とNVIDIA要約をSolid Queueで処理する。要約モデルは`NVIDIA_NIM_MODEL`で明示し、各Revisionには実際に使ったモデル名が保存される。検証済み400件は`catalog:snapshot:export`で移送用Artifactにし、Renderの初回デプロイhookからNeonへ投入する。

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
