# frozen_string_literal: true

require "cgi"

module FtsPgvector
  TABLE_NAME = "fts_target_pgvector_embeddings" unless const_defined?(:TABLE_NAME)
  EMBEDDING_DIMENSIONS = 4096 unless const_defined?(:EMBEDDING_DIMENSIONS)
  HNSW_INDEX_NAME = "fts_target_pgvector_embeddings_binary_hnsw_idx" unless const_defined?(:HNSW_INDEX_NAME)

  # Retrieve more approximate candidates than the requested page, then rerank
  # those candidates with the original full-precision cosine distance.
  CANDIDATE_MULTIPLIER = 10 unless const_defined?(:CANDIDATE_MULTIPLIER)
  MIN_CANDIDATES = 100 unless const_defined?(:MIN_CANDIDATES)
  MAX_EF_SEARCH = 1000 unless const_defined?(:MAX_EF_SEARCH)

  def self.pgvector_backend?
    Setting.plugin_full_text_search_pgvector["semantic_backend"] == "pgvector"
  end

  def self.install_search_controller_patch!
    return false unless defined?(SearchController)
    return false unless defined?(FullTextSearch::SemanticSearcher)
    return false unless defined?(FtsPgvector::SearchControllerPatch)

    unless SearchController.ancestors.include?(FtsPgvector::SearchControllerPatch)
      SearchController.prepend(FtsPgvector::SearchControllerPatch)
    end
    true
  end

  class ResultSet
    include Enumerable

    attr_reader :records, :total_n_hits, :elapsed_time

    def initialize(records:, total_n_hits:, elapsed_time:)
      @records = records
      @total_n_hits = total_n_hits
      @elapsed_time = elapsed_time
    end

    def n_hits
      total_n_hits
    end

    def each(&block)
      records.each(&block)
    end

    def tag_drilldowns
      []
    end

    def source_drilldown(type)
      type.to_s == "issues" ? total_n_hits : 0
    end
  end

  class Searcher
    def initialize(request)
      @request = request
    end

    def search
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return empty_result(started_at) if @request.query.blank?
      return empty_result(started_at) unless @request.target_search_types.include?("issues")
      return empty_result(started_at) if @request.attachments_only?

      connection = ActiveRecord::Base.connection
      model_name = Setting.plugin_full_text_search.semantic_model
      query_prefix = Setting.plugin_full_text_search.semantic_query_prefix.to_s
      query_text = query_prefix + @request.query
      vector_literal = connection.select_value(<<~SQL)
        SELECT pgroonga_language_model_vectorize(
          #{connection.quote(model_name)},
          #{connection.quote(query_text)}
        )::vector(#{EMBEDDING_DIMENSIONS})::text
      SQL

      scope = FullTextSearch::Target.issues
        .joins("INNER JOIN #{TABLE_NAME} ON #{TABLE_NAME}.target_id = fts_targets.id")
        .where(source_id: Issue.visible.select(:id))
        .where(project_id: @request.target_project_ids)

      if @request.open_issues?
        closed_status_ids = IssueStatus.where(is_closed: true).select(:id)
        scope = scope.where.not(
          source_id: Issue.where(status_id: closed_status_ids).select(:id)
        )
      end

      if @request.tags.present?
        tag_ids = @request.tags.map { |tag_id| Integer(tag_id, 10) }
        scope = scope.where(
          "fts_targets.tag_ids && ARRAY[?]::integer[]",
          tag_ids
        )
      end

      total_n_hits = scope.count
      return empty_result(started_at) if total_n_hits.zero?

      limit = [@request.limit.to_i, 1].max
      offset = [@request.offset.to_i, 0].max
      candidate_limit = [((limit + offset) * CANDIDATE_MULTIPLIER), MIN_CANDIDATES].max
      candidate_limit = [candidate_limit, total_n_hits].min
      ef_search = [[candidate_limit, 100].max, MAX_EF_SEARCH].min

      vector_sql = "#{connection.quote(vector_literal)}::vector(#{EMBEDDING_DIMENSIONS})"
      binary_query_sql = "binary_quantize(#{vector_sql})::bit(#{EMBEDDING_DIMENSIONS})"
      binary_distance_expression =
        "binary_quantize(#{TABLE_NAME}.embedding)::bit(#{EMBEDDING_DIMENSIONS}) <~> #{binary_query_sql}"
      cosine_distance_expression = "#{TABLE_NAME}.embedding <=> #{vector_sql}"

      # HNSW filtering is applied while scanning the approximate index. Enable
      # iterative scans so visibility/project/status/tag filters can continue
      # scanning until enough eligible candidates are found.
      records = connection.transaction(requires_new: true) do
        connection.execute("SET LOCAL enable_seqscan = off")
        connection.execute("SET LOCAL hnsw.ef_search = #{ef_search}")
        connection.execute("SET LOCAL hnsw.iterative_scan = 'strict_order'")

        candidate_ids = scope
          .reorder(Arel.sql("#{binary_distance_expression} ASC"))
          .limit(candidate_limit)
          .pluck("fts_targets.id")

        next [] if candidate_ids.empty?

        selected_scope = scope
          .where("fts_targets.id IN (?)", candidate_ids)
          .select(
            "fts_targets.*",
            "(1.0 - (#{cosine_distance_expression})) AS pgvector_similarity"
          )

        case @request.order_target
        when "last_modified_time", "date"
          direction = @request.order_type == "asc" ? "ASC" : "DESC"
          selected_scope = selected_scope.reorder(
            Arel.sql("fts_targets.last_modified_at #{direction}")
          )
        when "registered_time"
          direction = @request.order_type == "asc" ? "ASC" : "DESC"
          selected_scope = selected_scope.reorder(
            Arel.sql("fts_targets.registered_at #{direction}")
          )
        else
          # Re-rank approximate candidates with the original cosine distance.
          # Lower cosine distance means a more similar vector.
          selected_scope = selected_scope.reorder(
            Arel.sql("#{cosine_distance_expression} ASC")
          )
        end

        selected_scope.limit(limit).offset(offset).to_a
      end

      records.each do |record|
        record._score = record.read_attribute("pgvector_similarity").to_f
        record.highlighted_title = CGI.escapeHTML(record.title.to_s).html_safe
        snippet = CGI.escapeHTML(record.content.to_s.truncate(255)).html_safe
        record.content_snippets = [snippet]
      end

      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      ResultSet.new(
        records: records,
        total_n_hits: total_n_hits,
        elapsed_time: elapsed_time
      )
    end

    private

    def empty_result(started_at)
      elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      ResultSet.new(records: [], total_n_hits: 0, elapsed_time: elapsed_time)
    end
  end
end
