FROM postgres:18

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    ca-certificates \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://packages.groonga.org/debian/groonga-apt-source-latest-$(lsb_release --codename --short).deb \
    && apt-get install -y ./groonga-apt-source-latest-*.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-18-pgdg-pgroonga \
        groonga-tokenizer-mecab \
        groonga-plugin-language-model \
    && rm -rf /var/lib/apt/lists/* groonga-apt-source-latest-*.deb

RUN echo "CREATE EXTENSION IF NOT EXISTS pgroonga;" > /docker-entrypoint-initdb.d/10_pgroonga.sql
