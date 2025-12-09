package main

import (
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/grafikarsa/backend/internal/auth"
	"github.com/grafikarsa/backend/internal/config"
	"github.com/grafikarsa/backend/internal/database"
	"github.com/grafikarsa/backend/internal/handler"
	"github.com/grafikarsa/backend/internal/middleware"
	"github.com/grafikarsa/backend/internal/repository"
	"github.com/grafikarsa/backend/internal/storage"
)

func main() {
	// Load config
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to database
	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Initialize MinIO client
	minioClient, err := storage.NewMinIOClient(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to MinIO: %v", err)
	}

	// Initialize JWT service
	jwtService := auth.NewJWTService(cfg)

	// Initialize repositories
	userRepo := repository.NewUserRepository(db)
	authRepo := repository.NewAuthRepository(db)
	portfolioRepo := repository.NewPortfolioRepository(db)
	followRepo := repository.NewFollowRepository(db)
	adminRepo := repository.NewAdminRepository(db)

	// Initialize handlers
	authHandler := handler.NewAuthHandler(userRepo, authRepo, jwtService)
	userHandler := handler.NewUserHandler(userRepo, followRepo)
	profileHandler := handler.NewProfileHandler(userRepo)
	portfolioHandler := handler.NewPortfolioHandler(portfolioRepo, userRepo)
	contentBlockHandler := handler.NewContentBlockHandler(portfolioRepo)
	adminHandler := handler.NewAdminHandler(adminRepo, userRepo, portfolioRepo)
	uploadHandler := handler.NewUploadHandler(minioClient, userRepo, portfolioRepo)
	tagHandler := handler.NewTagHandler(adminRepo)
	publicHandler := handler.NewPublicHandler(adminRepo)
	feedHandler := handler.NewFeedHandler(portfolioRepo, followRepo)
	searchHandler := handler.NewSearchHandler(userRepo, portfolioRepo)

	// Initialize auth middleware
	authMiddleware := middleware.NewAuthMiddleware(jwtService, db)

	// Create Fiber app
	app := fiber.New(fiber.Config{
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			return c.Status(code).JSON(fiber.Map{
				"success": false,
				"error": fiber.Map{
					"code":    "INTERNAL_ERROR",
					"message": err.Error(),
				},
			})
		},
	})

	// Middleware
	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(cors.New(cors.Config{
		AllowOrigins:     strings.Join(cfg.CORS.Origins, ","),
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Accept,Authorization",
		AllowCredentials: true,
	}))

	// API v1 routes
	api := app.Group("/api/v1")

	// Health check
	api.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok"})
	})

	// Auth routes
	authRoutes := api.Group("/auth")
	authRoutes.Post("/login", authHandler.Login)
	authRoutes.Post("/refresh", authHandler.Refresh)
	authRoutes.Post("/logout", authMiddleware.Required(), authHandler.Logout)
	authRoutes.Post("/logout-all", authMiddleware.Required(), authHandler.LogoutAll)
	authRoutes.Get("/sessions", authMiddleware.Required(), authHandler.GetSessions)
	authRoutes.Delete("/sessions/:session_id", authMiddleware.Required(), authHandler.DeleteSession)

	// User routes
	userRoutes := api.Group("/users")
	userRoutes.Get("/", authMiddleware.Optional(), userHandler.List)
	userRoutes.Get("/:username", authMiddleware.Optional(), userHandler.GetByUsername)
	userRoutes.Get("/:username/followers", authMiddleware.Optional(), userHandler.GetFollowers)
	userRoutes.Get("/:username/following", authMiddleware.Optional(), userHandler.GetFollowing)
	userRoutes.Post("/:username/follow", authMiddleware.Required(), userHandler.Follow)
	userRoutes.Delete("/:username/follow", authMiddleware.Required(), userHandler.Unfollow)

	// Profile routes (me)
	api.Get("/me", authMiddleware.Required(), profileHandler.GetMe)
	api.Patch("/me", authMiddleware.Required(), profileHandler.UpdateMe)
	api.Patch("/me/password", authMiddleware.Required(), profileHandler.UpdatePassword)
	api.Put("/me/social-links", authMiddleware.Required(), profileHandler.UpdateSocialLinks)
	api.Get("/me/check-username", authMiddleware.Required(), profileHandler.CheckUsername)
	api.Get("/me/portfolios", authMiddleware.Required(), portfolioHandler.GetMyPortfolios)

	// Portfolio routes
	portfolioRoutes := api.Group("/portfolios")
	portfolioRoutes.Get("/", authMiddleware.Optional(), portfolioHandler.List)
	portfolioRoutes.Post("/", authMiddleware.Required(), portfolioHandler.Create)
	portfolioRoutes.Get("/:slug", authMiddleware.Optional(), portfolioHandler.GetBySlug)
	portfolioRoutes.Get("/id/:id", authMiddleware.Required(), portfolioHandler.GetByID)
	portfolioRoutes.Patch("/:id", authMiddleware.Required(), portfolioHandler.Update)
	portfolioRoutes.Delete("/:id", authMiddleware.Required(), portfolioHandler.Delete)
	portfolioRoutes.Post("/:id/submit", authMiddleware.Required(), portfolioHandler.Submit)
	portfolioRoutes.Post("/:id/archive", authMiddleware.Required(), portfolioHandler.Archive)
	portfolioRoutes.Post("/:id/unarchive", authMiddleware.Required(), portfolioHandler.Unarchive)
	portfolioRoutes.Post("/:id/like", authMiddleware.Required(), portfolioHandler.Like)
	portfolioRoutes.Delete("/:id/like", authMiddleware.Required(), portfolioHandler.Unlike)

	// Content block routes
	portfolioRoutes.Post("/:portfolio_id/blocks", authMiddleware.Required(), contentBlockHandler.Create)
	portfolioRoutes.Patch("/:portfolio_id/blocks/:block_id", authMiddleware.Required(), contentBlockHandler.Update)
	portfolioRoutes.Put("/:portfolio_id/blocks/reorder", authMiddleware.Required(), contentBlockHandler.Reorder)
	portfolioRoutes.Delete("/:portfolio_id/blocks/:block_id", authMiddleware.Required(), contentBlockHandler.Delete)

	// Tags routes (public)
	api.Get("/tags", tagHandler.List)

	// Public routes
	api.Get("/jurusan", publicHandler.ListJurusan)
	api.Get("/kelas", publicHandler.ListKelas)

	// Feed route
	api.Get("/feed", authMiddleware.Required(), feedHandler.GetFeed)

	// Search routes
	searchRoutes := api.Group("/search")
	searchRoutes.Get("/users", authMiddleware.Optional(), searchHandler.SearchUsers)
	searchRoutes.Get("/portfolios", authMiddleware.Optional(), searchHandler.SearchPortfolios)

	// Upload routes
	uploadRoutes := api.Group("/uploads")
	uploadRoutes.Post("/presign", authMiddleware.Required(), uploadHandler.Presign)
	uploadRoutes.Post("/confirm", authMiddleware.Required(), uploadHandler.Confirm)
	uploadRoutes.Delete("/*", authMiddleware.Required(), uploadHandler.Delete)
	uploadRoutes.Get("/presign-view", authMiddleware.Required(), uploadHandler.PresignView)

	// Admin routes
	adminRoutes := api.Group("/admin", authMiddleware.Required(), authMiddleware.AdminOnly())

	// Admin - Jurusan
	adminRoutes.Get("/jurusan", adminHandler.ListJurusan)
	adminRoutes.Post("/jurusan", adminHandler.CreateJurusan)
	adminRoutes.Patch("/jurusan/:id", adminHandler.UpdateJurusan)
	adminRoutes.Delete("/jurusan/:id", adminHandler.DeleteJurusan)

	// Admin - Tahun Ajaran
	adminRoutes.Get("/tahun-ajaran", adminHandler.ListTahunAjaran)
	adminRoutes.Post("/tahun-ajaran", adminHandler.CreateTahunAjaran)
	adminRoutes.Patch("/tahun-ajaran/:id", adminHandler.UpdateTahunAjaran)
	adminRoutes.Delete("/tahun-ajaran/:id", adminHandler.DeleteTahunAjaran)

	// Admin - Kelas
	adminRoutes.Get("/kelas", adminHandler.ListKelas)
	adminRoutes.Post("/kelas", adminHandler.CreateKelas)
	adminRoutes.Patch("/kelas/:id", adminHandler.UpdateKelas)
	adminRoutes.Delete("/kelas/:id", adminHandler.DeleteKelas)
	adminRoutes.Get("/kelas/:id/students", adminHandler.GetKelasStudents)

	// Admin - Tags
	adminRoutes.Get("/tags", adminHandler.ListTags)
	adminRoutes.Post("/tags", adminHandler.CreateTag)
	adminRoutes.Patch("/tags/:id", adminHandler.UpdateTag)
	adminRoutes.Delete("/tags/:id", adminHandler.DeleteTag)

	// Admin - Users
	adminRoutes.Get("/users", adminHandler.ListUsers)
	adminRoutes.Post("/users", adminHandler.CreateUser)
	adminRoutes.Get("/users/:id", adminHandler.GetUser)
	adminRoutes.Patch("/users/:id", adminHandler.UpdateUser)
	adminRoutes.Patch("/users/:id/password", adminHandler.ResetUserPassword)
	adminRoutes.Delete("/users/:id", adminHandler.DeleteUser)
	adminRoutes.Post("/users/:id/deactivate", adminHandler.DeactivateUser)
	adminRoutes.Post("/users/:id/activate", adminHandler.ActivateUser)

	// Admin - Portfolios
	adminRoutes.Get("/portfolios", adminHandler.ListAllPortfolios)
	adminRoutes.Get("/portfolios/pending", adminHandler.ListPendingPortfolios)
	adminRoutes.Get("/portfolios/:id", adminHandler.GetPortfolio)
	adminRoutes.Patch("/portfolios/:id", adminHandler.UpdatePortfolio)
	adminRoutes.Delete("/portfolios/:id", adminHandler.DeletePortfolio)
	adminRoutes.Post("/portfolios/:id/approve", adminHandler.ApprovePortfolio)
	adminRoutes.Post("/portfolios/:id/reject", adminHandler.RejectPortfolio)

	// Admin - Dashboard
	adminRoutes.Get("/dashboard/stats", adminHandler.GetDashboardStats)

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-quit
		log.Println("Gracefully shutting down...")
		_ = app.Shutdown()
	}()

	// Start server
	port := cfg.App.Port
	if port == "" {
		port = "8080"
	}
	log.Printf("Server starting on port %s", port)
	if err := app.Listen(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
