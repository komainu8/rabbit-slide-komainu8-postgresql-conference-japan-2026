# Full Text Search pgvector backend

`clear-code/redmine_full_text_search` に pgvector の検索バックエンドを追加する Redmine 7 向けプラグインです。

## 検索方式

- 既存の `redmine_full_text_search` と PGroonga の検索機能は変更しません。
- Full Text Search の検索画面で「セマンティック検索」を有効にしたとき、管理設定で選んだバックエンドを使用します。
- `pgvector` を選択した場合、Redmine のチケットを検索対象にします。
- 埋め込み生成には PGroonga の `pgroonga_language_model_vectorize()` を使います。Full Text Search プラグインに設定したモデル名と passage/query prefix を使用します。
- 対象ベクトルは Qwen3-Embedding-8B の 4096 次元です。元の 4096 次元ベクトルは `vector(4096)` として保持します。
- 近似候補検索には、`binary_quantize()` で生成した 4096 bit のビット列に対する HNSW インデックスを使用します。候補抽出はハミング距離で行います。
- 抽出した候補は、保存している元の 4096 次元ベクトルのコサイン距離で再ランキングします。したがって、候補抽出は近似検索、最終順位付けは元ベクトルによるコサイン距離です。

## 前提

- Redmine 7.x
- PostgreSQL
- `redmine_full_text_search` がインストール済み
- PGroonga 4.0.5 以降（`pgroonga_language_model_vectorize()` が必要）
- pgvector 0.8.0 以降（バイナリ量子化、HNSW、反復インデックススキャンを使用）
- Full Text Search プラグインにモデル名が設定済み
- PostgreSQL コンテナからモデルファイルを読み取れること

## インストール

1. このディレクトリを `redmine/plugins/full_text_search_pgvector` に配置します。
2. Redmine イメージを再ビルドします。
3. Redmine を再起動します。
4. Redmine の「管理」→「プラグイン」→「Full Text Search: pgvector backend」→「設定」を開きます。
5. 「セマンティック検索エンジン」を `pgvector` にします。
6. Full Text Search プラグイン側でも「セマンティック検索」を有効にします。

このバージョンでは、プラグイン初期化時に `SearchController` へ検索切り替えパッチを直接適用します。さらに Rails の `to_prepare` でも再適用するため、今回発生した「設定は pgvector なのに PGroonga の検索処理が呼ばれる」問題を避けます。

## 埋め込みと HNSW インデックスの作成・更新

Full Text Search の既存データ同期を先に実施したあと、Redmine コンテナで実行します。

```bash
RAILS_ENV=production bundle exec rake full_text_search:pgvector:index:create
```

Podman Compose 環境ではホスト側から次のように実行します。

```bash
podman compose exec -T redmine \
  env RAILS_ENV=production \
  bundle exec rake full_text_search:pgvector:index:create
```

このタスクは次の処理を行います。

1. `fts_targets` のチケットデータから、未作成または本文が変更された埋め込みを生成します。
2. 不要になったチケットの埋め込みを削除します。
3. 4096 bit のバイナリ量子化表現に対する HNSW インデックスを作成します（既に存在する場合は再利用します）。
4. テーブルを `ANALYZE` します。

チケットの追加・更新後は Full Text Search 側の同期を行い、このタスクを再実行してください。既存の埋め込みは本文・モデル名・passage prefix が変わっていなければ再生成しません。

モデル名を一時的に上書きしたい場合は `MODEL=...` を指定できます。通常は Full Text Search プラグインの `semantic_model` 設定を使います。

## 検索時の動作

検索時には次の順序で処理します。

1. 検索クエリーを `pgroonga_language_model_vectorize()` で 4096 次元ベクトルに変換します。
2. バイナリ量子化したクエリーベクトルと HNSW インデックスを使い、ハミング距離で候補チケットを取得します。
3. 候補を元の 4096 次元ベクトルのコサイン距離で再ランキングします。
4. 再ランキング後の結果を Redmine の検索結果として返します。

候補数は検索ページの limit/offset に応じて増やし、最低 100 件を候補にします。検索条件（閲覧権限、プロジェクト、ステータス、タグなど）は候補検索時に適用します。HNSW の反復インデックススキャンを有効にし、条件によって候補が不足することを抑制します。

HNSW は近似近傍検索なので、全件を厳密に比較する検索と結果が異なる場合があります。候補検索にハミング距離を使うため、最終的なコサイン距離の順位が完全に再現される保証はありません。

## 動作確認

埋め込み件数と次元数を確認します。

```bash
podman compose exec postgres \
  psql -U redmine -d redmine \
  -c "SELECT COUNT(*) FROM fts_target_pgvector_embeddings;"

podman compose exec postgres \
  psql -U redmine -d redmine \
  -c "SELECT vector_dims(embedding), COUNT(*) FROM fts_target_pgvector_embeddings GROUP BY vector_dims(embedding);"
```

HNSW インデックスを確認します。

```bash
podman compose exec postgres \
  psql -U redmine -d redmine \
  -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'fts_target_pgvector_embeddings';"
```

HNSW インデックスの利用可否は、実際の検索 SQL に対して `EXPLAIN (ANALYZE, BUFFERS)` で確認してください。データ件数が少ない場合、PostgreSQL のプランナーが逐次スキャンを選び、HNSW インデックスを使わないことがあります。今回の検証データのように数十件程度では、近似検索の速度差や検索結果の差がほとんど現れず、実質的に全件が候補に入る場合があります。

## 制限

- Redmine のチケット (`Issue`) のみ検索します。Wiki、添付ファイル、ニュース、メッセージ、変更履歴などは対象外です。
- 「タイトルのみ検索」オプションは、独立したタイトルベクトルを持たないため反映しません。
- 元のベクトルは 4096 次元で保持します。HNSW の候補インデックスは 4096 bit のバイナリ量子化表現です。
- `pgroonga_language_model_vectorize()` は PGroonga の実験的機能です。
- ベクトル生成は CPU・メモリーを使用します。チケットを大量に同期する場合は時間とメモリーに注意してください。

## アンインストール

プラグインディレクトリを削除し、必要に応じて次のテーブルを削除します。

```sql
DROP TABLE IF EXISTS fts_target_pgvector_embeddings;
```

このテーブル以外の Redmine / Full Text Search / PGroonga のデータは削除しません。
