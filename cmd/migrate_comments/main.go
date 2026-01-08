package main

import (
	"log"

	"github.com/grafikarsa/backend/internal/config"
	"github.com/grafikarsa/backend/internal/database"
)

func main() {
	log.Println("Starting migration for Comments feature...")

	// 1. Load Configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("❌ Failed to load config: %v", err)
	}

	// 2. Connect to Database
	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("❌ Failed to connect to database: %v", err)
	}
	log.Println("✅ Database connected successfully")

	// 3. Define Migration Steps
	steps := []struct {
		Name string
		SQL  string
	}{
		{
			Name: "Add 'new_comment' to notification_type enum",
			SQL:  "ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'new_comment';",
		},
		{
			Name: "Add 'reply_comment' to notification_type enum",
			SQL:  "ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'reply_comment';",
		},
		{
			Name: "Create 'comments' table",
			SQL: `CREATE TABLE IF NOT EXISTS comments (
				id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
				portfolio_id UUID NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
				user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
				parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
				content TEXT NOT NULL,
				is_edited BOOLEAN DEFAULT false,
				created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
				updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
				deleted_at TIMESTAMPTZ
			);`,
		},
		{
			Name: "Create index idx_comments_portfolio_id",
			SQL:  "CREATE INDEX IF NOT EXISTS idx_comments_portfolio_id ON comments(portfolio_id);",
		},
		{
			Name: "Create index idx_comments_user_id",
			SQL:  "CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);",
		},
		{
			Name: "Create index idx_comments_parent_id",
			SQL:  "CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON comments(parent_id);",
		},
		{
			Name: "Create index idx_comments_created_at",
			SQL:  "CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at);",
		},
		{
			Name: "Create trigger trg_comments_updated_at",
			SQL: `DO $$
			BEGIN
				IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_comments_updated_at') THEN
					CREATE TRIGGER trg_comments_updated_at 
						BEFORE UPDATE ON comments 
						FOR EACH ROW 
						EXECUTE FUNCTION update_updated_at();
				END IF;
			END $$;`,
		},
	}

	// 4. Execute Steps
	hasError := false
	for _, step := range steps {
		log.Printf("Executing: %s...", step.Name)
		if err := db.Exec(step.SQL).Error; err != nil {
			// Special handling for enum types in older Postgres versions that don't support IF NOT EXISTS
			// If error contains "already exists", we can consider it a success or warning
			// But for now, just log it.
			log.Printf("❌ FAILED: %v", err)
			hasError = true
		} else {
			log.Println("✅ SUCCESS")
		}
	}

	if hasError {
		log.Println("\n⚠️  Migration finished with errors. Please check the logs above.")
	} else {
		log.Println("\n🎉 Migration completed successfully!")
	}
}
