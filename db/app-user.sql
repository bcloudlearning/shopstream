CREATE ROLE shopstream_app LOGIN PASSWORD :'app_password';

GRANT CONNECT ON DATABASE shopstream TO shopstream_app;
GRANT USAGE ON SCHEMA public TO shopstream_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO shopstream_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO shopstream_app;
