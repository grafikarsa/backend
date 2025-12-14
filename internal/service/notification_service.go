package service

import (
	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/domain"
	"github.com/grafikarsa/backend/internal/repository"
)

type NotificationService struct {
	repo *repository.NotificationRepository
}

func NewNotificationService(repo *repository.NotificationRepository) *NotificationService {
	return &NotificationService{repo: repo}
}

// NotifyNewFollower creates notification when someone follows a user
func (s *NotificationService) NotifyNewFollower(follower *domain.User, followedUserID uuid.UUID) error {
	notification := &domain.Notification{
		UserID:  followedUserID,
		Type:    domain.NotifNewFollower,
		Title:   "Pengikut Baru",
		Message: strPtr("@" + follower.Username + " mulai mengikuti kamu"),
		Data: domain.JSONB{
			"follower_id":       follower.ID.String(),
			"follower_username": follower.Username,
			"follower_nama":     follower.Nama,
			"follower_avatar":   follower.AvatarURL,
		},
	}
	return s.repo.Create(notification)
}

// NotifyPortfolioLiked creates notification when someone likes a portfolio
func (s *NotificationService) NotifyPortfolioLiked(liker *domain.User, portfolio *domain.Portfolio) error {
	// Don't notify if user likes their own portfolio
	if liker.ID == portfolio.UserID {
		return nil
	}

	notification := &domain.Notification{
		UserID:  portfolio.UserID,
		Type:    domain.NotifPortfolioLiked,
		Title:   "Portfolio Disukai",
		Message: strPtr("@" + liker.Username + " menyukai portfolio \"" + portfolio.Judul + "\""),
		Data: domain.JSONB{
			"liker_id":        liker.ID.String(),
			"liker_username":  liker.Username,
			"liker_nama":      liker.Nama,
			"liker_avatar":    liker.AvatarURL,
			"portfolio_id":    portfolio.ID.String(),
			"portfolio_judul": portfolio.Judul,
			"portfolio_slug":  portfolio.Slug,
		},
	}
	return s.repo.Create(notification)
}

// NotifyPortfolioApproved creates notification when portfolio is approved
func (s *NotificationService) NotifyPortfolioApproved(portfolio *domain.Portfolio) error {
	notification := &domain.Notification{
		UserID:  portfolio.UserID,
		Type:    domain.NotifPortfolioApproved,
		Title:   "Portfolio Dipublikasikan",
		Message: strPtr("Portfolio \"" + portfolio.Judul + "\" telah disetujui dan dipublikasikan"),
		Data: domain.JSONB{
			"portfolio_id":    portfolio.ID.String(),
			"portfolio_judul": portfolio.Judul,
			"portfolio_slug":  portfolio.Slug,
		},
	}
	return s.repo.Create(notification)
}

// NotifyPortfolioRejected creates notification when portfolio is rejected
func (s *NotificationService) NotifyPortfolioRejected(portfolio *domain.Portfolio, note string) error {
	notification := &domain.Notification{
		UserID:  portfolio.UserID,
		Type:    domain.NotifPortfolioRejected,
		Title:   "Portfolio Perlu Diperbaiki",
		Message: strPtr("Portfolio \"" + portfolio.Judul + "\" perlu diperbaiki"),
		Data: domain.JSONB{
			"portfolio_id":    portfolio.ID.String(),
			"portfolio_judul": portfolio.Judul,
			"portfolio_slug":  portfolio.Slug,
			"admin_note":      note,
		},
	}
	return s.repo.Create(notification)
}

func strPtr(s string) *string {
	return &s
}
