#!/usr/bin/env ruby

file = File.expand_path(ARGV.fetch(0, "search_test_evaluated.csv"))

databases = [
  ["postgresql_db", "postgresql_test_db"],
  ["pgvector_db", "vector_test_db"],
  ["pgroonga_db", "pgroonga_test_db"]
]

container_file = "/tmp/search_test_evaluated.csv"
embedding_model = "hf:///Qwen/Qwen3-Embedding-8B-GGUF"

# Execute SQL in a container.
def execute_sql(container, database, sql)
  system(
    "podman", "exec", container,
    "psql", "-U", "postgres", "-d", database,
    "-v", "ON_ERROR_STOP=1",
    "-c", sql
  ) || abort("Failed to execute SQL: #{container}/#{database}")
end

# Create a table for each database.
def create_table(container, database)
  create_table_sql =
    if container == "pgvector_db"
      <<~SQL
        DROP TABLE IF EXISTS search_test_evaluated;

        CREATE TABLE search_test_evaluated (
          id              integer PRIMARY KEY,
          target_document text,
          embedding       vector(4096)
        );
      SQL
    else
      <<~SQL
        DROP TABLE IF EXISTS search_test_evaluated;

        CREATE TABLE search_test_evaluated (
          id              integer PRIMARY KEY,
          target_document text
        );
      SQL
    end

  execute_sql(container, database, create_table_sql)
end

# Copy the CSV file into a container.
def copy_csv(file, container, container_file)
  system(
    "podman", "cp",
    file,
    "#{container}:#{container_file}"
  ) || abort("Failed to copy CSV to #{container}")
end

# Import CSV data into PostgreSQL and PGroonga.
def import_csv(container, database, container_file)
  import_sql = <<~SQL
    COPY search_test_evaluated (id, target_document)
    FROM '#{container_file}'
    WITH (FORMAT csv, HEADER true);
  SQL

  execute_sql(container, database, import_sql)
end

# Import CSV data and generate embeddings for pgvector only.
def import_pgvector_data(container, database, container_file, embedding_model)
  import_sql = <<~SQL
    BEGIN;

    CREATE TEMP TABLE import_source (
      id              integer,
      target_document text
    );

    COPY import_source (id, target_document)
    FROM '#{container_file}'
    WITH (FORMAT csv, HEADER true);

    INSERT INTO search_test_evaluated (
      id,
      target_document,
      embedding
    )
    SELECT
      id,
      target_document,
      pgroonga_language_model_vectorize(
        '#{embedding_model}',
        target_document
      )
    FROM import_source;

    COMMIT;
  SQL

  execute_sql(container, database, import_sql)
end

# Create the appropriate index for each database.
def create_index(container, database, embedding_model)
  index_sql =
    case container
    when "postgresql_db"
      <<~SQL
        CREATE INDEX IF NOT EXISTS postgresql_index
          ON search_test_evaluated
          USING gin (target_document);
      SQL
    when "pgroonga_db"
      <<~SQL
        CREATE INDEX IF NOT EXISTS pgroonga_semantic_index
          ON search_test_evaluated
          USING pgroonga (
            target_document pgroonga_text_semantic_search_ops_v2
          )
          WITH (
            plugins = 'language_model/knn',
            model = '#{embedding_model}'
          );
      SQL
    when "pgvector_db"
      <<~SQL
        CREATE INDEX IF NOT EXISTS embedding_hnsw_idx
          ON search_test_evaluated
          USING hnsw (embedding vector_cosine_ops);
      SQL
    end

  execute_sql(container, database, index_sql) if index_sql
end

# Remove the temporary CSV file from the container.
def cleanup_csv(container, container_file)
  system(
    "podman", "exec", container,
    "rm", "-f", container_file
  )
end

# Main process.
databases.each do |container, database|
  puts "Importing to #{container}/#{database}..."

  create_table(container, database)

  copy_csv(file, container, container_file)

  if container == "pgvector_db"
    import_pgvector_data(
      container,
      database,
      container_file,
      embedding_model
    )
  else
    import_csv(container, database, container_file)
  end

  create_index(container, database, embedding_model)

  cleanup_csv(container, container_file)

  puts "Done: #{container}/#{database}"
end
