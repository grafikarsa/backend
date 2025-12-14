package handler

import (
	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/dto"
	"github.com/grafikarsa/backend/internal/middleware"
	"github.com/grafikarsa/backend/internal/repository"
)

type NotificationHandler struct {
	repo *repository.NotificationRepository
}

func NewNotificationHandler(repo *repository.NotificationRepository) *NotificationHandler {
	return &NotificationHandler{repo: repo}
}

// List - GET /notifications
func (h *NotificationHandler) List(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "Unauthorized"))
	}

	page := c.QueryInt("page", 1)
	limit := c.QueryInt("limit", 20)
	unreadOnly := c.QueryBool("unread_only", false)

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 50 {
		limit = 20
	}

	notifications, total, err := h.repo.FindByUserID(*userID, unreadOnly, page, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("FETCH_FAILED", "Gagal mengambil notifikasi"))
	}

	unreadCount, _ := h.repo.CountUnread(*userID)

	var responses []dto.NotificationResponse
	for _, n := range notifications {
		responses = append(responses, dto.NotificationResponse{
			ID:        n.ID.String(),
			Type:      string(n.Type),
			Title:     n.Title,
			Message:   n.Message,
			Data:      n.Data,
			IsRead:    n.IsRead,
			ReadAt:    n.ReadAt,
			CreatedAt: n.CreatedAt,
		})
	}

	totalPages := (int(total) + limit - 1) / limit

	return c.JSON(fiber.Map{
		"success": true,
		"data":    responses,
		"meta": dto.NotificationListMeta{
			Page:        page,
			Limit:       limit,
			Total:       total,
			TotalPages:  totalPages,
			UnreadCount: unreadCount,
		},
	})
}

// Count - GET /notifications/count
func (h *NotificationHandler) Count(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "Unauthorized"))
	}

	count, err := h.repo.CountUnread(*userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("FETCH_FAILED", "Gagal mengambil jumlah notifikasi"))
	}

	return c.JSON(dto.SuccessResponse(dto.NotificationCountResponse{UnreadCount: count}, ""))
}

// MarkAsRead - PATCH /notifications/:id/read
func (h *NotificationHandler) MarkAsRead(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "Unauthorized"))
	}

	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("INVALID_ID", "ID tidak valid"))
	}

	// Check ownership
	notification, err := h.repo.FindByID(id)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(dto.ErrorResponse("NOT_FOUND", "Notifikasi tidak ditemukan"))
	}
	if notification.UserID != *userID {
		return c.Status(fiber.StatusForbidden).JSON(dto.ErrorResponse("FORBIDDEN", "Tidak memiliki akses"))
	}

	if err := h.repo.MarkAsRead(id); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("UPDATE_FAILED", "Gagal mengupdate notifikasi"))
	}

	return c.JSON(dto.SuccessResponse(nil, "Notifikasi ditandai sudah dibaca"))
}

// MarkAllAsRead - POST /notifications/read-all
func (h *NotificationHandler) MarkAllAsRead(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "Unauthorized"))
	}

	if err := h.repo.MarkAllAsRead(*userID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("UPDATE_FAILED", "Gagal mengupdate notifikasi"))
	}

	return c.JSON(dto.SuccessResponse(nil, "Semua notifikasi ditandai sudah dibaca"))
}

// Delete - DELETE /notifications/:id
func (h *NotificationHandler) Delete(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "Unauthorized"))
	}

	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(dto.ErrorResponse("INVALID_ID", "ID tidak valid"))
	}

	// Check ownership
	notification, err := h.repo.FindByID(id)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(dto.ErrorResponse("NOT_FOUND", "Notifikasi tidak ditemukan"))
	}
	if notification.UserID != *userID {
		return c.Status(fiber.StatusForbidden).JSON(dto.ErrorResponse("FORBIDDEN", "Tidak memiliki akses"))
	}

	if err := h.repo.Delete(id); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("DELETE_FAILED", "Gagal menghapus notifikasi"))
	}

	return c.JSON(dto.SuccessResponse(nil, "Notifikasi berhasil dihapus"))
}
