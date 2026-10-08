#!/usr/bin/env ruby

require 'csv'

file = File.expand_path(ARGV.fetch(0, "search_test_evaluated.csv"))

databases = [
  ["pgvector_db", "vector_test_db"],
  ["pgroonga_db", "pgroonga_test_db"]
]

sql = <<~SQL

SQL

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
