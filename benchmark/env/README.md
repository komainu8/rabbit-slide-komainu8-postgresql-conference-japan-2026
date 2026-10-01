podman compose up --build -d 

podman exec -it pgvector_db psql -U postgres -d vector_test_db -c "SELECT version();" -c "\dx"
                                                      version                                                       
--------------------------------------------------------------------------------------------------------------------
 PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

                                      List of installed extensions
  Name   | Version | Default version |   Schema   |                     Description                      
---------+---------+-----------------+------------+------------------------------------------------------
 plpgsql | 1.0     | 1.0             | pg_catalog | PL/pgSQL procedural language
 vector  | 0.8.6   | 0.8.6           | public     | vector data type and ivfflat and hnsw access methods
(2 rows)


podman exec -it pgroonga_db psql -U postgres -d pgroonga_test_db -c "SELECT version();" -c "\dx"
                                                      version                                                       
--------------------------------------------------------------------------------------------------------------------
 PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

                                                    List of installed extensions
   Name   | Version | Default version |   Schema   |                                  Description                                   
----------+---------+-----------------+------------+--------------------------------------------------------------------------------
 pgroonga | 4.0.9   | 4.0.9           | public     | Super fast and all languages supported full text search index based on Groonga
 plpgsql  | 1.0     | 1.0             | pg_catalog | PL/pgSQL procedural language
(2 rows)

podman compose down
