// Command migrate applies schema migrations and seeds the first admin.
//
//	go run ./cmd/migrate up          apply pending migrations + create admin if none
//	go run ./cmd/migrate status      list migrations and whether each is applied
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"sort"

	"skills-analyzer/internal/config"
	"skills-analyzer/internal/database"
	"skills-analyzer/internal/seed"
)

func main() {
	if err := run(); err != nil {
		slog.Error("migrate failed", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cmd := "up"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx := context.Background()
	db, err := database.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()

	switch cmd {
	case "up":
		if err := database.Migrate(ctx, db); err != nil {
			return err
		}
		if err := seed.EnsureAdmin(ctx, db, cfg); err != nil {
			return err
		}
		fmt.Println("migrations up to date")
	case "status":
		status, err := database.MigrationStatus(ctx, db)
		if err != nil {
			return err
		}
		versions := make([]string, 0, len(status))
		for v := range status {
			versions = append(versions, v)
		}
		sort.Strings(versions)
		for _, v := range versions {
			mark := "pending"
			if status[v] {
				mark = "applied"
			}
			fmt.Printf("%-8s %s\n", mark, v)
		}
	default:
		return fmt.Errorf("unknown command %q (use: up | status)", cmd)
	}
	return nil
}
