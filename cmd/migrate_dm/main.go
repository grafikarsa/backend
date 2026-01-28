package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/grafikarsa/backend/internal/config"
	_ "github.com/lib/pq"
)

func main() {
	log.Println("Starting DM Migration...")

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to database
	connStr := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		cfg.Database.Host, cfg.Database.Port, cfg.Database.User, cfg.Database.Password, cfg.Database.Name, cfg.Database.SSLMode,
	)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}
	log.Println("Connected to database successfully.")

	// Read SQL file
	// Assuming running from backend root, so path is docs/db/dm_tables.sql
	// Or we can try to find it relative to executable

	// Let's try absolute path first or relative to typical run location
	basePath, _ := os.Getwd()
	sqlPath := filepath.Join(basePath, "docs", "db", "dm_tables.sql")

	log.Printf("Reading migration file from: %s", sqlPath)
	content, err := os.ReadFile(sqlPath)
	if err != nil {
		// Try fallback relative path if running from cmd subfolder
		sqlPath = filepath.Join(basePath, "..", "..", "docs", "db", "dm_tables.sql")
		log.Printf("Retrying with path: %s", sqlPath)
		content, err = os.ReadFile(sqlPath)
		if err != nil {
			log.Fatalf("Failed to read SQL file: %v", err)
		}
	}

	// Execute SQL
	log.Println("Executing migration script...")
	_, err = db.Exec(string(content))
	if err != nil {
		log.Fatalf("Failed to execute migration: %v", err)
	}

	log.Println("DM Migration completed successfully!")
}
