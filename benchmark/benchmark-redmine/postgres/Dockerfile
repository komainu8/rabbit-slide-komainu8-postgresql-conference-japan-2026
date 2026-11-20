FROM docker.io/groonga/pgroonga:4.1.0-debian-18

ARG PG_MAJOR=18
ARG PGVECTOR_VERSION=0.8.7

# Build pgvector on top of the official PGroonga PostgreSQL 18 image.
# The PGroonga image already includes groonga-plugin-language-model.
RUN set -eux; \
    apt-get update; \
    apt-mark hold locales; \
    apt-get install -y --no-install-recommends \
      build-essential \
      postgresql-server-dev-${PG_MAJOR} \
      wget; \
    wget -O /tmp/pgvector.tar.gz \
      "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz"; \
    mkdir -p /tmp/pgvector; \
    tar -xzf /tmp/pgvector.tar.gz \
      -C /tmp/pgvector \
      --strip-components=1; \
    cd /tmp/pgvector; \
    make clean; \
    make OPTFLAGS=""; \
    make install; \
    mkdir -p /usr/share/doc/pgvector; \
    cp LICENSE README.md /usr/share/doc/pgvector/; \
    cd /; \
    rm -rf /tmp/pgvector /tmp/pgvector.tar.gz; \
    apt-get remove -y build-essential postgresql-server-dev-${PG_MAJOR} wget; \
    apt-get autoremove -y; \
    apt-mark unhold locales; \
    rm -rf /var/lib/apt/lists/*
