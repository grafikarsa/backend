package handler

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/dto"
	"github.com/grafikarsa/backend/internal/middleware"
	"github.com/grafikarsa/backend/internal/repository"
	"github.com/grafikarsa/backend/internal/storage"
)

type UploadHandler struct {
	minioClient    *storage.MinIOClient
	userRepo       *repository.UserRepository
	portfolioRepo  *repository.PortfolioRepository
	pendingUploads map[string]*PendingUpload
}

type PendingUpload struct {
	ID          string
	UserID      uuid.UUID
	UploadType  string
	ObjectKey   string
	PortfolioID *uuid.UUID
	BlockID     *uuid.UUID
	ExpiresAt   time.Time
	Confirmed   bool
}

var uploadLimits = map[string]int64{
	"avatar":          2 * 1024 * 1024,  // 2MB
	"banner":          10 * 1024 * 1024, // 10MB (increased for GIF support)
	"thumbnail":       5 * 1024 * 1024,  // 5MB
	"portfolio_image": 10 * 1024 * 1024, // 10MB
	"document":        20 * 1024 * 1024, // 20MB for PDF, DOC, PPT files
}

var allowedTypes = map[string][]string{
	"avatar":          {"image/jpeg", "image/png", "image/webp"},
	"banner":          {"image/jpeg", "image/png", "image/webp", "image/gif"},
	"thumbnail":       {"image/jpeg", "image/png", "image/webp"},
	"portfolio_image": {"image/jpeg", "image/png", "image/webp", "image/gif"},
	"document": {
		"application/pdf",
		"application/msword",
		"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
		"application/vnd.ms-powerpoint",
		"application/vnd.openxmlformats-officedocument.presentationml.presentation",
	},
}

func NewUploadHandler(minioClient *storage.MinIOClient, userRepo *repository.UserRepository, portfolioRepo *repository.PortfolioRepository) *UploadHandler {
	return &UploadHandler{
		minioClient:    minioClient,
		userRepo:       userRepo,
		portfolioRepo:  portfolioRepo,
		pendingUploads: make(map[string]*PendingUpload),
	}
}

func (h *UploadHandler) Presign(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "User tidak terautentikasi"))
	}

	var req dto.PresignRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "Request body tidak valid"))
	}

	// Validate upload type
	maxSize, ok := uploadLimits[req.UploadType]
	if !ok {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "Upload type tidak valid"))
	}

	// Validate file size
	if req.FileSize > maxSize {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("FILE_TOO_LARGE", "Ukuran file melebihi batas maksimal",
			dto.ErrorDetail{Field: "file_size", Message: fmt.Sprintf("Ukuran file %s maksimal %dMB", req.UploadType, maxSize/(1024*1024))},
		))
	}

	// Validate content type
	allowed := allowedTypes[req.UploadType]
	isAllowed := false
	for _, t := range allowed {
		if t == req.ContentType {
			isAllowed = true
			break
		}
	}
	if !isAllowed {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("INVALID_CONTENT_TYPE", "Tipe file tidak diizinkan",
			dto.ErrorDetail{Field: "content_type", Message: fmt.Sprintf("Tipe file yang diizinkan: %s", strings.Join(allowed, ", "))},
		))
	}

	// Validate portfolio ownership for thumbnail/portfolio_image/document
	if req.UploadType == "thumbnail" || req.UploadType == "portfolio_image" || req.UploadType == "document" {
		if req.PortfolioID == nil {
			return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "portfolio_id wajib diisi"))
		}
		portfolio, err := h.portfolioRepo.FindByID(*req.PortfolioID)
		if err != nil {
			return c.Status(fiber.StatusNotFound).JSON(dto.ErrorResponse("PORTFOLIO_NOT_FOUND", "Portfolio tidak ditemukan"))
		}
		if portfolio.UserID != *userID && middleware.GetUserRole(c) != "admin" {
			return c.Status(fiber.StatusForbidden).JSON(dto.ErrorResponse("FORBIDDEN", "Anda tidak memiliki akses untuk upload ke portfolio ini"))
		}
	}

	// Generate object key
	ext := filepath.Ext(req.Filename)
	fileID := uuid.New().String()
	var objectKey string

	switch req.UploadType {
	case "avatar":
		objectKey = fmt.Sprintf("avatars/%s/%s%s", userID.String(), fileID, ext)
	case "banner":
		objectKey = fmt.Sprintf("banners/%s/%s%s", userID.String(), fileID, ext)
	case "thumbnail":
		objectKey = fmt.Sprintf("thumbnails/%s/%s%s", req.PortfolioID.String(), fileID, ext)
	case "portfolio_image":
		objectKey = fmt.Sprintf("portfolio-images/%s/%s%s", req.PortfolioID.String(), fileID, ext)
	case "document":
		objectKey = fmt.Sprintf("documents/%s/%s%s", req.PortfolioID.String(), fileID, ext)
	}

	// Generate presigned URL
	presignedURL, err := h.minioClient.GetPresignedPutURL(objectKey, req.ContentType, 15*time.Minute)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal generate presigned URL"))
	}

	// Store pending upload
	uploadID := uuid.New().String()
	h.pendingUploads[uploadID] = &PendingUpload{
		ID:          uploadID,
		UserID:      *userID,
		UploadType:  req.UploadType,
		ObjectKey:   objectKey,
		PortfolioID: req.PortfolioID,
		BlockID:     req.BlockID,
		ExpiresAt:   time.Now().Add(15 * time.Minute),
		Confirmed:   false,
	}

	return c.JSON(dto.SuccessResponse(dto.PresignResponse{
		UploadID:     uploadID,
		PresignedURL: presignedURL,
		ObjectKey:    objectKey,
		ExpiresIn:    900,
		Method:       "PUT",
		Headers:      map[string]string{"Content-Type": req.ContentType},
	}, ""))
}

func (h *UploadHandler) Confirm(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "User tidak terautentikasi"))
	}

	var req dto.ConfirmUploadRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "Request body tidak valid"))
	}

	// Find pending upload
	pending, ok := h.pendingUploads[req.UploadID]
	if !ok || pending.ExpiresAt.Before(time.Now()) {
		return c.Status(fiber.StatusNotFound).JSON(dto.ErrorResponse("UPLOAD_NOT_FOUND", "Upload tidak ditemukan atau sudah expired"))
	}

	if pending.Confirmed {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("UPLOAD_ALREADY_CONFIRMED", "Upload ini sudah dikonfirmasi sebelumnya"))
	}

	if pending.UserID != *userID {
		return c.Status(fiber.StatusForbidden).JSON(dto.ErrorResponse("FORBIDDEN", "Anda tidak memiliki akses"))
	}

	// Verify object exists in MinIO
	exists, err := h.minioClient.ObjectExists(pending.ObjectKey)
	if err != nil || !exists {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("OBJECT_NOT_FOUND", "File tidak ditemukan di storage. Pastikan upload ke MinIO berhasil."))
	}

	// Get public URL
	publicURL := h.minioClient.GetPublicURL(pending.ObjectKey)

	// Update database based on upload type
	switch pending.UploadType {
	case "avatar":
		user, _ := h.userRepo.FindByID(*userID)
		user.AvatarURL = &publicURL
		h.userRepo.Update(user)
	case "banner":
		user, _ := h.userRepo.FindByID(*userID)
		user.BannerURL = &publicURL
		h.userRepo.Update(user)
	case "thumbnail":
		portfolio, _ := h.portfolioRepo.FindByID(*pending.PortfolioID)
		portfolio.ThumbnailURL = &publicURL
		h.portfolioRepo.Update(portfolio)
	}

	pending.Confirmed = true

	response := dto.ConfirmUploadResponse{
		Type:      pending.UploadType,
		URL:       publicURL,
		ObjectKey: pending.ObjectKey,
	}
	if pending.PortfolioID != nil {
		response.PortfolioID = pending.PortfolioID
	}
	if pending.BlockID != nil {
		response.BlockID = pending.BlockID
	}

	messages := map[string]string{
		"avatar":          "Avatar berhasil diperbarui",
		"banner":          "Banner berhasil diperbarui",
		"thumbnail":       "Thumbnail portfolio berhasil diperbarui",
		"portfolio_image": "Gambar berhasil diupload",
	}

	return c.JSON(dto.SuccessResponse(response, messages[pending.UploadType]))
}

func (h *UploadHandler) Delete(c *fiber.Ctx) error {
	objectKey := c.Params("*")
	if objectKey == "" {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "Object key tidak valid"))
	}

	if err := h.minioClient.DeleteObject(objectKey); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal menghapus file"))
	}

	return c.JSON(dto.SuccessResponse(nil, "File berhasil dihapus"))
}

func (h *UploadHandler) PresignView(c *fiber.Ctx) error {
	objectKey := c.Query("object_key")
	if objectKey == "" {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("VALIDATION_ERROR", "Object key wajib diisi"))
	}

	url, err := h.minioClient.GetPresignedGetURL(objectKey, 1*time.Hour)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal generate presigned URL"))
	}

	return c.JSON(dto.SuccessResponse(map[string]interface{}{
		"url":        url,
		"expires_in": 3600,
	}, ""))
}
