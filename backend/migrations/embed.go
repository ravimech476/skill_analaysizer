// Package migrations embeds the ordered *.up.sql files applied by database.Migrate.
package migrations

import "embed"

//go:embed *.up.sql
var FS embed.FS
