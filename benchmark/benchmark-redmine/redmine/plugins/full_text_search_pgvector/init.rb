# frozen_string_literal: true

Redmine::Plugin.register :full_text_search_pgvector do
  name "Full Text Search: pgvector backend"
  author "OpenAI"
  description "Adds an approximate pgvector backend to clear-code/redmine_full_text_search."
  version "0.2.0"
  requires_redmine version_or_higher: "7.0.0"
  settings partial: "settings/full_text_search_pgvector",
           default: { "semantic_backend" => "pgroonga" }
end

plugin_directory = File.dirname(File.absolute_path(__FILE__))
require_dependency File.join(plugin_directory, "lib/fts_pgvector/searcher")
require_dependency File.join(plugin_directory, "lib/fts_pgvector/search_controller_patch")

# Install the patch immediately, after redmine_full_text_search has defined
# SearchController and its own ControllerSearchIndex hook. The previous
# to_prepare-only implementation was not reliably applied in the production
# startup sequence used by this plugin combination.
FtsPgvector.install_search_controller_patch!

# Keep the patch installed after Rails reloads in development environments.
Rails.application.config.to_prepare do
  FtsPgvector.install_search_controller_patch!
end
