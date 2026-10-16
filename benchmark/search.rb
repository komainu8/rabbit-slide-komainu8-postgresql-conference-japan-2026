#!/usr/bin/env ruby

require 'csv'

file = File.expand_path(ARGV.fetch(0, "search_test_evaluated.csv"))

databases = [
  ["postgresql_db", "postgresql_test_db"],
  ["pgvector_db", "vector_test_db"],
  ["pgroonga_db", "pgroonga_test_db"]
]

keywords = [
  "りんご レシピ",
  "葛飾北斎 代表作",
  "スマホ ケース"
]
search_sql = ""

databases.each do |container, database|

  keywords.each do |keyword|
    if container == "postgresql_db"
      words = keyword.split
      search_sql = <<~SQL
SELECT *
FROM search_test_evaluated
WHERE target_document like "%#{words[0]}%"
  AND target_document like "%#{words[1]}%";
      SQL
    elsif container == "pgroonga_db"
      search_sql = <<~SQL
SELECT *, pgroonga_score(tableoid, ctid) AS score
FROM search_test_evaluated
WHERE target_document &@* pgroonga_condition('#{keyword}');
      SQL
    elsif container == "pgvector_db"
      search_sql = <<~SQL
SELECT *, (embedding <#> query_embedding.query) * -1 AS inner_product
FROM search_test_evaluated
     (
       SELECT CAST(pgroonga_language_model_vectorize(
                   'hf:///Qwen/Qwen3-Embedding-8B-GGUF',
                   '#{keyword}') AS vector) AS query
     ) query_embedding
ORDER BY inner_product DESC;
      SQL
    end
    system(
      "podman", "exec", container,
      "psql", "-U", "postgres", "-d", database,
      "-c", search_sql
    ) || abort("Failed to search")
  end
end

databases.each do |container, database|
  CSV.foreach(file, headers: true) do |row|
    query = row["query"].gsub("'", "''")

    search_sql = <<~SQL
    SELECT *, pgroonga_score(tableoid, ctid) AS score
    FROM search_test_evaluated
    WHERE target_document &@* pgroonga_condition('#{query}');
  SQL

    p search_sql

    if container == "pgroonga_db"
      system(
        "podman", "exec", container,
        "psql", "-U", "postgres", "-d", database,
        "-c", search_sql
      ) || abort("Failed to search")
    end
  end
end
