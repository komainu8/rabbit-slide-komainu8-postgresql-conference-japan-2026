# frozen_string_literal: true

namespace :full_text_search do
  namespace :pgvector do
    namespace :index do
      desc "Create or update pgvector embeddings and the binary HNSW index for Redmine issue search targets"
      task create: :environment do
        unless Redmine::Database.postgresql?
          abort "pgvector backend requires PostgreSQL."
        end

        connection = ActiveRecord::Base.connection
        unless connection.select_value(
          "SELECT to_regprocedure('pgroonga_language_model_vectorize(cstring,text)') IS NOT NULL"
        )
          abort "pgroonga_language_model_vectorize() is unavailable. Check PGroonga version."
        end

        vector_version = connection.select_value(<<~SQL).to_s
          SELECT extversion FROM pg_extension WHERE extname = 'vector'
        SQL
        if vector_version.empty?
          abort "pgvector extension is not installed in this database."
        end
        if Gem::Version.new(vector_version) < Gem::Version.new("0.8.0")
          abort "pgvector 0.8.0 or later is required (installed: #{vector_version})."
        end
        unless connection.select_value(
          "SELECT to_regprocedure('binary_quantize(vector)') IS NOT NULL"
        )
          abort "pgvector binary_quantize(vector) is unavailable. Check pgvector version."
        end

        fts_settings = Setting.plugin_full_text_search
        model_name = ENV["MODEL"].presence || fts_settings.semantic_model
        passage_prefix = fts_settings.semantic_passage_prefix.to_s
        model_sql = connection.quote(model_name)
        prefix_sql = connection.quote(passage_prefix)

        dimensions = connection.select_value(<<~SQL).to_i
          SELECT cardinality(
            pgroonga_language_model_vectorize(
              #{model_sql},
              #{connection.quote(passage_prefix + "pgvector dimension check")}
            )
          )
        SQL
        unless dimensions == FtsPgvector::EMBEDDING_DIMENSIONS
          abort "Embedding dimension mismatch: expected #{FtsPgvector::EMBEDDING_DIMENSIONS}, got #{dimensions}."
        end

        connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{FtsPgvector::TABLE_NAME} (
            target_id bigint PRIMARY KEY,
            content_hash text NOT NULL,
            embedding vector(#{FtsPgvector::EMBEDDING_DIMENSIONS}) NOT NULL,
            updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        SQL

        issue_type_id = FullTextSearch::Type.issue.id
        content_hash_sql =
          "md5(#{model_sql} || chr(31) || #{prefix_sql} || chr(31) || target.content)"

        puts "Generating pgvector embeddings with model: #{model_name}"
        connection.execute(<<~SQL)
          INSERT INTO #{FtsPgvector::TABLE_NAME}
            (target_id, content_hash, embedding, updated_at)
          SELECT
            target.id,
            #{content_hash_sql},
            pgroonga_language_model_vectorize(
              #{model_sql},
              #{prefix_sql} || target.content
            )::vector(#{FtsPgvector::EMBEDDING_DIMENSIONS}),
            CURRENT_TIMESTAMP
          FROM fts_targets AS target
          WHERE target.source_type_id = #{Integer(issue_type_id)}
            AND target.content <> ''
            AND NOT EXISTS (
              SELECT 1
              FROM #{FtsPgvector::TABLE_NAME} AS existing
              WHERE existing.target_id = target.id
                AND existing.content_hash = #{content_hash_sql}
            )
          ON CONFLICT (target_id)
          DO UPDATE SET
            content_hash = EXCLUDED.content_hash,
            embedding = EXCLUDED.embedding,
            updated_at = CURRENT_TIMESTAMP
        SQL

        connection.execute(<<~SQL)
          DELETE FROM #{FtsPgvector::TABLE_NAME} AS embedding
          WHERE NOT EXISTS (
            SELECT 1
            FROM fts_targets AS target
            WHERE target.id = embedding.target_id
              AND target.source_type_id = #{Integer(issue_type_id)}
              AND target.content <> ''
          )
        SQL

        connection.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS #{FtsPgvector::HNSW_INDEX_NAME}
          ON #{FtsPgvector::TABLE_NAME}
          USING hnsw (
            (binary_quantize(embedding)::bit(#{FtsPgvector::EMBEDDING_DIMENSIONS})) bit_hamming_ops
          )
          WITH (m = 16, ef_construction = 64)
        SQL
        connection.execute("ANALYZE #{FtsPgvector::TABLE_NAME}")

        count = connection.select_value(
          "SELECT COUNT(*) FROM #{FtsPgvector::TABLE_NAME}"
        )
        puts "pgvector embeddings: #{count}"
        puts "HNSW index: #{FtsPgvector::HNSW_INDEX_NAME}"
        puts "Done. Missing or changed issue embeddings were updated and the HNSW index is present."
      end
    end
  end
end
