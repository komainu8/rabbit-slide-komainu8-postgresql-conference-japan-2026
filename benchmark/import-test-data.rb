#!/usr/bin/env ruby

file = File.expand_path(ARGV.fetch(0, "search_test_evaluated.csv"))

databases = [
  ["pgvector_db", "vector_test_db"],
  ["pgroonga_db", "pgroonga_test_db"]
]

create_table_sql = <<~SQL
DROP TABLE IF EXISTS search_test_evaluated;

CREATE TABLE search_test_evaluated (
  id              integer PRIMARY KEY,
  category        text,
  subcategory     text,
  query           text,
  target_document text,
  expected_match  boolean,
  result_label    text,
  judgment_reason text
);
SQL

databases.each do |container, database|
  puts "Importing to #{container}/#{database}..."

  system(
    "podman", "exec", container,
    "psql", "-U", "postgres", "-d", database,
    "-c", create_table_sql
  ) || abort("Failed to create table")

  container_file = "/tmp/search_test_evaluated.csv"

  system(
    "podman", "cp",
    file,
    "#{container}:#{container_file}"
  ) || abort("Failed to copy CSV")

  sql = <<~SQL
COPY search_test_evaluated
FROM '#{container_file}'
WITH (FORMAT csv, HEADER true);
  SQL

  system(
    "podman", "exec", container,
    "psql", "-U", "postgres", "-d", database,
    "-c", sql
  ) || abort("Failed to import CSV")

  # Create Index
  index_sql =
    if container == "pgroonga_db"
      <<~SQL
        CREATE INDEX IF NOT EXISTS pgroonga_semantic_index
          ON search_test_evaluated
          USING pgroonga (target_document pgroonga_text_semantic_search_ops_v2)
           WITH (plugins = 'language_model/knn',
                 model = 'hf:///Qwen/Qwen3-Embedding-8B-GGUF');
      SQL
#    elsif container == "pgvector_db"
#      <<~SQL
#        CREATE INDEX search_test_evaluated_embedding_hnsw_idx
#          ON search_test_evaluated
#          USING hnsw (embedding vector_cosine_ops);
#      SQL
    end

  if index_sql
    system(
      "podman", "exec", container,
      "psql", "-U", "postgres", "-d", database,
      "-c", index_sql
    ) || abort("Failed to create index")
  end

  system(
    "podman", "exec", container,
    "rm", container_file
  )

  puts "Done: #{container}/#{database}"
end
