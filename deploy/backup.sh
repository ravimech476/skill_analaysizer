#!/bin/sh
# Backups for the compose stack. Runs inside the "backup" container (postgres image).
#   backup.sh once   take one backup now
#   backup.sh loop   take one every day at $BACKUP_AT (HH:MM, container TZ) and prune old ones
# Each backup is two files in /backups:
#   db-YYYYMMDD-HHMM.dump        pg_dump custom format (restore with restore.sh)
#   uploads-YYYYMMDD-HHMM.tar.gz  the uploaded files volume
set -eu

KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"

backup_once() {
	stamp=$(date +%Y%m%d-%H%M)
	tmp="/backups/.db-$stamp.dump.part"
	pg_dump --format=custom --no-owner --file="$tmp"
	mv "$tmp" "/backups/db-$stamp.dump"
	tar -czf "/backups/.uploads-$stamp.part" -C /uploads . && mv "/backups/.uploads-$stamp.part" "/backups/uploads-$stamp.tar.gz"
	find /backups -maxdepth 1 \( -name 'db-*.dump' -o -name 'uploads-*.tar.gz' \) -mtime +"$KEEP_DAYS" -delete
	echo "$(date -Iseconds) backup done: db-$stamp.dump, uploads-$stamp.tar.gz"
}

case "${1:-once}" in
once)
	backup_once
	;;
loop)
	at="${BACKUP_AT:-02:30}"
	echo "backups every day at $at, keeping $KEEP_DAYS days"
	while true; do
		now=$(date +%s)
		next=$(date -d "$(date +%Y-%m-%d) $at" +%s 2>/dev/null || date -D '%Y-%m-%d %H:%M' -d "$(date +%Y-%m-%d) $at" +%s)
		[ "$next" -le "$now" ] && next=$((next + 86400))
		sleep $((next - now))
		backup_once || echo "$(date -Iseconds) BACKUP FAILED" >&2
	done
	;;
*)
	echo "usage: backup.sh once|loop" >&2
	exit 2
	;;
esac
