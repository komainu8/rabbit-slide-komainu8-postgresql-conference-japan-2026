FROM docker.io/library/redmine:7.0.3

ARG FULL_TEXT_SEARCH_PLUGIN_REF=master

USER root
WORKDIR /usr/src/redmine

# Install Git only while building the custom Redmine image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Install the full-text-search plugin.
RUN git clone --depth 1 --branch "${FULL_TEXT_SEARCH_PLUGIN_REF}" \
    https://github.com/clear-code/redmine_full_text_search.git \
    plugins/full_text_search

COPY plugins/full_text_search_pgvector plugins/full_text_search_pgvector

# Add the build platform to Gemfile.lock and install gems as the Redmine user.
RUN gosu redmine bundle lock --add-platform "$(ruby -e 'puts Gem::Platform.local')" \
    && gosu redmine bundle install
