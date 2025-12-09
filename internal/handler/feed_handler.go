package handler

import (
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/grafikarsa/backend/internal/dto"
	"github.com/grafikarsa/backend/internal/middleware"
	"github.com/grafikarsa/backend/internal/repository"
)

type FeedHandler struct {
	portfolioRepo *repository.PortfolioRepository
	followRepo    *repository.FollowRepository
}

func NewFeedHandler(portfolioRepo *repository.PortfolioRepository, followRepo *repository.FollowRepository) *FeedHandler {
	return &FeedHandler{
		portfolioRepo: portfolioRepo,
		followRepo:    followRepo,
	}
}

func (h *FeedHandler) GetFeed(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	if userID == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(dto.ErrorResponse("UNAUTHORIZED", "User tidak terautentikasi"))
	}

	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "20"))

	portfolios, total, err := h.portfolioRepo.GetFeed(*userID, page, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal mengambil feed"))
	}

	var result []dto.PortfolioListDTO
	for _, p := range portfolios {
		likeCount, _ := h.portfolioRepo.GetLikeCount(p.ID)
		isLiked, _ := h.portfolioRepo.IsLiked(*userID, p.ID)

		pDTO := dto.PortfolioListDTO{
			ID:           p.ID,
			Judul:        p.Judul,
			Slug:         p.Slug,
			ThumbnailURL: p.ThumbnailURL,
			PublishedAt:  p.PublishedAt,
			LikeCount:    likeCount,
			IsLiked:      isLiked,
		}

		if p.User != nil {
			var kelasNama *string
			if p.User.Kelas != nil {
				kelasNama = &p.User.Kelas.Nama
			}
			pDTO.User = &dto.PortfolioUserDTO{
				ID:        p.User.ID,
				Username:  p.User.Username,
				Nama:      p.User.Nama,
				AvatarURL: p.User.AvatarURL,
				Role:      string(p.User.Role),
				KelasNama: kelasNama,
			}
		}

		for _, t := range p.Tags {
			pDTO.Tags = append(pDTO.Tags, dto.TagDTO{ID: t.ID, Nama: t.Nama})
		}

		result = append(result, pDTO)
	}

	totalPages := int(total) / limit
	if int(total)%limit > 0 {
		totalPages++
	}

	return c.JSON(dto.SuccessWithMeta(result, &dto.Meta{
		CurrentPage: page,
		PerPage:     limit,
		TotalPages:  totalPages,
		TotalCount:  total,
	}))
}
