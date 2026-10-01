FROM postgres:18

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-18-pgvector \
    && rm -rf /var/lib/apt/lists/*

RUN echo "CREATE EXTENSION IF NOT EXISTS vector;" > /docker-entrypoint-initdb.d/10_vector.sql
