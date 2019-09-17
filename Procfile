web: env SENTRY_DSN=$SENTRY_DSN_WEB KEMAL_ENV=production bin/app --port $PORT
worker: env SENTRY_DSN=$SENTRY_DSN_WORKER bin/worker loop
import: env SENRTY_DSN=$SENTRY_DSN_WORKER bin/worker import_catalog https://github.com/shardbox/catalog.git
