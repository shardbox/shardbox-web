web: env SENTRY_DSN_VAR=SENTRY_DSN_WEB KEMAL_ENV=production bin/app --port $PORT
worker: env SENTRY_DSN_VAR=SENTRY_DSN_WORKER bin/worker loop
import: env SENRTY_DSN_VAR=SENTRY_DSN_WORKER bin/worker import_catalog
release: dbmate --no-dump-schema --migrations-dir lib/shardbox-core/db/migrations up
