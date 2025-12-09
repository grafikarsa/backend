package repository

import (
	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/domain"
	"gorm.io/gorm"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *domain.User) error {
	return r.db.Create(user).Error
}

func (r *UserRepository) FindByID(id uuid.UUID) (*domain.User, error) {
	var user domain.User
	err := r.db.Preload("Kelas.Jurusan").Preload("SocialLinks").
		Where("id = ? AND deleted_at IS NULL", id).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByUsername(username string) (*domain.User, error) {
	var user domain.User
	err := r.db.Preload("Kelas.Jurusan").Preload("SocialLinks").
		Where("username = ? AND deleted_at IS NULL", username).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByEmail(email string) (*domain.User, error) {
	var user domain.User
	err := r.db.Where("email = ? AND deleted_at IS NULL", email).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByUsernameOrEmail(identifier string) (*domain.User, error) {
	var user domain.User
	err := r.db.Where("(username = ? OR email = ?) AND deleted_at IS NULL", identifier, identifier).
		First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) Update(user *domain.User) error {
	return r.db.Save(user).Error
}

func (r *UserRepository) Delete(id uuid.UUID) error {
	return r.db.Where("id = ?", id).Delete(&domain.User{}).Error
}

func (r *UserRepository) UsernameExists(username string, excludeID *uuid.UUID) (bool, error) {
	var count int64
	query := r.db.Model(&domain.User{}).Where("username = ? AND deleted_at IS NULL", username)
	if excludeID != nil {
		query = query.Where("id != ?", *excludeID)
	}
	err := query.Count(&count).Error
	return count > 0, err
}

func (r *UserRepository) EmailExists(email string, excludeID *uuid.UUID) (bool, error) {
	var count int64
	query := r.db.Model(&domain.User{}).Where("email = ? AND deleted_at IS NULL", email)
	if excludeID != nil {
		query = query.Where("id != ?", *excludeID)
	}
	err := query.Count(&count).Error
	return count > 0, err
}

func (r *UserRepository) List(search string, jurusanID, kelasID *uuid.UUID, role *string, page, limit int) ([]domain.User, int64, error) {
	var users []domain.User
	var total int64

	query := r.db.Model(&domain.User{}).Where("deleted_at IS NULL")

	if search != "" {
		query = query.Where("nama ILIKE ? OR username ILIKE ? OR bio ILIKE ?",
			"%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	if role != nil {
		query = query.Where("role = ?", *role)
	}

	if kelasID != nil {
		query = query.Where("kelas_id = ?", *kelasID)
	} else if jurusanID != nil {
		query = query.Joins("JOIN kelas ON users.kelas_id = kelas.id").
			Where("kelas.jurusan_id = ?", *jurusanID)
	}

	query.Count(&total)

	offset := (page - 1) * limit
	err := query.Preload("Kelas.Jurusan").
		Offset(offset).Limit(limit).
		Order("nama ASC").
		Find(&users).Error

	return users, total, err
}

func (r *UserRepository) GetFollowerCount(userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.Model(&domain.Follow{}).Where("following_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *UserRepository) GetFollowingCount(userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.Model(&domain.Follow{}).Where("follower_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *UserRepository) GetPublishedPortfolioCount(userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.Model(&domain.Portfolio{}).
		Where("user_id = ? AND status = 'published' AND deleted_at IS NULL", userID).
		Count(&count).Error
	return count, err
}

func (r *UserRepository) IsFollowing(followerID, followingID uuid.UUID) (bool, error) {
	var count int64
	err := r.db.Model(&domain.Follow{}).
		Where("follower_id = ? AND following_id = ?", followerID, followingID).
		Count(&count).Error
	return count > 0, err
}

func (r *UserRepository) GetClassHistory(userID uuid.UUID) ([]domain.StudentClassHistory, error) {
	var history []domain.StudentClassHistory
	err := r.db.Preload("Kelas").Preload("TahunAjaran").
		Where("user_id = ?", userID).
		Order("created_at ASC").
		Find(&history).Error
	return history, err
}

func (r *UserRepository) UpdateSocialLinks(userID uuid.UUID, links []domain.UserSocialLink) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		// Delete existing links
		if err := tx.Where("user_id = ?", userID).Delete(&domain.UserSocialLink{}).Error; err != nil {
			return err
		}
		// Insert new links
		if len(links) > 0 {
			for i := range links {
				links[i].UserID = userID
			}
			if err := tx.Create(&links).Error; err != nil {
				return err
			}
		}
		return nil
	})
}
