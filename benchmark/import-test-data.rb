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

  system(
    "podman", "exec", container,
    "rm", container_file
  )

  puts "Done: #{container}/#{database}"
end
