#!/bin/sh
# Restore a backup into the running compose stack (run from the deploy/ folder on the server):
#   ./restore.sh backups/db-20260921-0230.dump [backups/uploads-20260921-0230.tar.gz]
# The API is stopped while restoring and started again afterwards. THIS REPLACES CURRENT DATA.
set -eu

DUMP="${1:?usage: restore.sh <db-dump> [uploads-archive]}"
UPLOADS="${2:-}"
[ -f "$DUMP" ] || { echo "no such file: $DUMP" >&2; exit 1; }

printf 'This replaces the live database%s. Type "restore" to continue: ' "${UPLOADS:+ and uploaded files}"
read -r answer
[ "$answer" = "restore" ] || { echo "cancelled"; exit 1; }

docker compose stop api web
docker compose exec -T db pg_restore --clean --if-exists --no-owner -U skills -d skills_analyzer <"$DUMP"
if [ -n "$UPLOADS" ]; then
	docker compose run --rm --no-deps -v "$(pwd)/$(dirname "$UPLOADS"):/in:ro" --entrypoint sh api \
		-c "find /app/storage -mindepth 1 -delete && tar -xzf /in/$(basename "$UPLOADS") -C /app/storage"
fi
docker compose start api web
echo "restored $DUMP${UPLOADS:+ and $UPLOADS}"
