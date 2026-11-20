# frozen_string_literal: true

module FtsPgvector
  module SearchControllerPatch
    private

    def searcher
      if @search_request&.semantic? && FtsPgvector.pgvector_backend?
        FtsPgvector::Searcher.new(@search_request)
      else
        super
      end
    end
  end
end
