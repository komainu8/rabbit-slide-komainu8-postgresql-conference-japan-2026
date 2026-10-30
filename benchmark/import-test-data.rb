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







# Copy the CSV file into a container.
def copy_csv(file, container, container_file)
  system(
    "podman", "cp",
    file,
    "#{container}:#{container_file}"
  ) || abort("Failed to copy CSV to #{container}")
end

def import_csv_to_synonym_dictionary(container, database, container_file)
  import_sql = <<~SQL
    COPY synonym_dictionary (dictionary_id,
                             source_form,
                             canonical_form,
                             source_normalized,
                             canonical_normalized,
                             category,
                             case_id)
    FROM '#{container_file}'
    WITH (FORMAT csv, HEADER true);
  SQL

  execute_sql(container, database, import_sql)
end

def import_csv_to_documents(container, database, container_file)
  import_sql = <<~SQL
  COPY public.documents (document_id,
                         case_id,
                         entity_id,
                         category,
                         document_role,
                         title,
                         body,
                         target_document)
  FROM '#{container_file}' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
  SQL

  execute_sql(container, database, import_sql)
end

def create_function_for_documents_search(container, database)
  create_function =
    <<~SQL
-- NFKC、小文字化、空白統一、辞書置換を行う。
CREATE OR REPLACE FUNCTION public.normalize_for_keyword_search(input_text text)
RETURNS text
LANGUAGE plpgsql
STABLE
STRICT
AS $function$
DECLARE
  result_text text := regexp_replace(
    lower(normalize(input_text, NFKC)),
    '[[:space:]]+', ' ', 'g'
  );
  item record;
BEGIN
  FOR item IN
    SELECT source_normalized, canonical_normalized
    FROM public.synonym_dictionary
    ORDER BY char_length(source_normalized) DESC
  LOOP
    -- EV / AI などの英数字は単語境界で置換する。
    IF item.source_normalized ~ '^[a-z0-9]+$' THEN
      result_text := regexp_replace(
        result_text,
        '(^|[^a-z0-9])(' || item.source_normalized || ')([^a-z0-9]|$)',
        E'\\1' || item.canonical_normalized || E'\\3',
        'g'
      );
    ELSE
      result_text := replace(
        result_text,
        item.source_normalized,
        item.canonical_normalized
      );
    END IF;
  END LOOP;

  RETURN regexp_replace(result_text, '[[:space:]]+', ' ', 'g');
END
$function$;
SQL
  execute_sql(container, database, create_function)
end

def create_index_to_documents(container, database)
  index_sql = <<~SQL
CREATE EXTENSION IF NOT EXISTS pg_trgm;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS normalized_target_document text;

UPDATE public.documents
SET normalized_target_document =
  public.normalize_for_keyword_search(target_document);

CREATE INDEX IF NOT EXISTS documents_normalized_target_document_trgm_idx
  ON public.documents
  USING GIN (normalized_target_document gin_trgm_ops);

ANALYZE public.documents;
SQL
    execute_sql(container, database, index_sql)
end

def create_index_to_synonym_dictionary(container, database)
  index_sql =
    <<~SQL
CREATE UNIQUE INDEX IF NOT EXISTS synonym_dictionary_source_normalized_idx
                               ON public.synonym_dictionary (source_normalized);
SQL
#    case container
#    when "postgresql_db"
#      <<~SQL
#        CREATE INDEX IF NOT EXISTS postgresql_index
#          ON search_test_evaluated
#          USING gin (target_document);
#      SQL
#    when "pgroonga_db"
#      <<~SQL
#        CREATE INDEX IF NOT EXISTS pgroonga_semantic_index
#          ON search_test_evaluated
#          USING pgroonga (
#            target_document pgroonga_text_semantic_search_ops_v2
#          )
#          WITH (
#            plugins = 'language_model/knn',
#            model = '#{embedding_model}'
#          );
#      SQL
#    when "pgvector_db"
#      <<~SQL
#        CREATE INDEX IF NOT EXISTS embedding_hnsw_idx
#          ON search_test_evaluated
#          USING hnsw (embedding vector_cosine_ops);
#      SQL
#    end
  execute_sql(container, database, index_sql) if index_sql
end

def cleanup_csv(container, container_file)
  system(
    "podman", "exec", container,
    "rm", "-f", container_file
  )
end

def create_synonym_table(container, database)
  create_synonym_sql =
    <<~SQL
CREATE TABLE IF NOT EXISTS public.synonym_dictionary (
  dictionary_id        text PRIMARY KEY,
  source_form          text NOT NULL,
  canonical_form       text NOT NULL,
  source_normalized    text NOT NULL,
  canonical_normalized text NOT NULL,
  category             text NOT NULL,
  case_id              text NOT NULL
);
SQL
  execute_sql(container, database, create_synonym_sql)

  file = File.expand_path("synonym_dictionary.csv")
  container_file = "/tmp/synonym_dictionary.csv"
  copy_csv(file, container, container_file)
  import_csv_to_synonym_dictionary(container, database, container_file)
  cleanup_csv(container, container_file)

  create_index_to_synonym_dictionary(container, database);
end

def create_documents_table(container, database)
  create_documents_sql =
    <<~SQL
CREATE TABLE IF NOT EXISTS public.documents (
  document_id    text PRIMARY KEY,
  case_id        text NOT NULL,
  entity_id      text NOT NULL,
  category       text NOT NULL,
  document_role  text NOT NULL,
  title          text NOT NULL,
  body           text NOT NULL,
  target_document text NOT NULL
);
SQL
  execute_sql(container, database, create_documents_sql)

  file = File.expand_path("documents.csv")
  container_file = "/tmp/documents.csv"
  copy_csv(file, container, container_file)
  import_csv_to_documents(container, database, container_file)
  cleanup_csv(container, container_file)

  create_function_for_documents_search(container, database)
  create_index_to_documents(container, database)
end

# Main process.
databases.each do |container, database|
  puts "Importing to #{container}/#{database}..."

  create_synonym_table(container, database)
  create_documents_table(container, database)
#  create_table(container, database)
#
#  copy_csv(file, container, container_file)
#
#  if container == "pgvector_db"
#    import_pgvector_data(
#      container,
#      database,
#      container_file,
#      embedding_model
#    )
#  else
#    import_csv(container, database, container_file)
#  end
#
#  create_index(container, database, embedding_model)

#  cleanup_csv(container, container_file)

  puts "Done: #{container}/#{database}"
end
