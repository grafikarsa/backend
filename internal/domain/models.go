package domain

import (
	"database/sql/driver"
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// Enum types
type UserRole string

const (
	RoleStudent UserRole = "student"
	RoleAlumni  UserRole = "alumni"
	RoleAdmin   UserRole = "admin"
)

type PortfolioStatus string

const (
	StatusDraft         PortfolioStatus = "draft"
	StatusPendingReview PortfolioStatus = "pending_review"
	StatusRejected      PortfolioStatus = "rejected"
	StatusPublished     PortfolioStatus = "published"
	StatusArchived      PortfolioStatus = "archived"
)

type ContentBlockType string

const (
	BlockText    ContentBlockType = "text"
	BlockImage   ContentBlockType = "image"
	BlockTable   ContentBlockType = "table"
	BlockYoutube ContentBlockType = "youtube"
	BlockButton  ContentBlockType = "button"
	BlockEmbed   ContentBlockType = "embed"
)

type SocialPlatform string

const (
	PlatformFacebook        SocialPlatform = "facebook"
	PlatformInstagram       SocialPlatform = "instagram"
	PlatformGithub          SocialPlatform = "github"
	PlatformLinkedin        SocialPlatform = "linkedin"
	PlatformTwitter         SocialPlatform = "twitter"
	PlatformPersonalWebsite SocialPlatform = "personal_website"
	PlatformTiktok          SocialPlatform = "tiktok"
	PlatformYoutube         SocialPlatform = "youtube"
	PlatformBehance         SocialPlatform = "behance"
	PlatformDribbble        SocialPlatform = "dribbble"
	PlatformThreads         SocialPlatform = "threads"
	PlatformBluesky         SocialPlatform = "bluesky"
	PlatformMedium          SocialPlatform = "medium"
	PlatformGitlab          SocialPlatform = "gitlab"
)

// JSONB type for GORM
type JSONB map[string]interface{}

func (j JSONB) Value() (driver.Value, error) {
	return json.Marshal(j)
}

func (j *JSONB) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return nil
	}
	return json.Unmarshal(bytes, j)
}

// Base model with soft delete
type BaseModel struct {
	ID        uuid.UUID  `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	CreatedAt time.Time  `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time  `gorm:"not null;default:now()" json:"updated_at"`
	DeletedAt *time.Time `gorm:"index" json:"-"`
}

// Jurusan (Department/Major)
type Jurusan struct {
	BaseModel
	Nama string `gorm:"type:varchar(100);not null" json:"nama"`
	Kode string `gorm:"type:varchar(10);not null;uniqueIndex" json:"kode"`
}

func (Jurusan) TableName() string { return "jurusan" }

// TahunAjaran (Academic Year)
type TahunAjaran struct {
	BaseModel
	TahunMulai     int  `gorm:"not null;uniqueIndex" json:"tahun_mulai"`
	IsActive       bool `gorm:"not null;default:false" json:"is_active"`
	PromotionMonth int  `gorm:"type:smallint;not null;default:7" json:"promotion_month"`
	PromotionDay   int  `gorm:"type:smallint;not null;default:1" json:"promotion_day"`
}

func (TahunAjaran) TableName() string { return "tahun_ajaran" }

// Kelas (Class)
type Kelas struct {
	BaseModel
	TahunAjaranID uuid.UUID    `gorm:"type:uuid;not null" json:"tahun_ajaran_id"`
	JurusanID     uuid.UUID    `gorm:"type:uuid;not null" json:"jurusan_id"`
	Tingkat       int          `gorm:"type:smallint;not null" json:"tingkat"`
	Rombel        string       `gorm:"type:char(1);not null" json:"rombel"`
	Nama          string       `gorm:"type:varchar(20);not null" json:"nama"`
	TahunAjaran   *TahunAjaran `gorm:"foreignKey:TahunAjaranID" json:"tahun_ajaran,omitempty"`
	Jurusan       *Jurusan     `gorm:"foreignKey:JurusanID" json:"jurusan,omitempty"`
}

func (Kelas) TableName() string { return "kelas" }

// Tags
type Tag struct {
	BaseModel
	Nama string `gorm:"type:varchar(50);not null;uniqueIndex" json:"nama"`
}

func (Tag) TableName() string { return "tags" }

// User
type User struct {
	BaseModel
	Username     string           `gorm:"type:varchar(30);not null;uniqueIndex" json:"username"`
	Email        string           `gorm:"type:varchar(255);not null;uniqueIndex" json:"email"`
	PasswordHash string           `gorm:"type:varchar(255);not null" json:"-"`
	Nama         string           `gorm:"type:varchar(100);not null" json:"nama"`
	Bio          *string          `gorm:"type:text" json:"bio,omitempty"`
	AvatarURL    *string          `gorm:"type:text" json:"avatar_url,omitempty"`
	BannerURL    *string          `gorm:"type:text" json:"banner_url,omitempty"`
	Role         UserRole         `gorm:"type:user_role;not null;default:'student'" json:"role"`
	NISN         *string          `gorm:"type:varchar(20)" json:"nisn,omitempty"`
	NIS          *string          `gorm:"type:varchar(30)" json:"nis,omitempty"`
	KelasID      *uuid.UUID       `gorm:"type:uuid" json:"kelas_id,omitempty"`
	TahunMasuk   *int             `gorm:"type:integer" json:"tahun_masuk,omitempty"`
	TahunLulus   *int             `gorm:"type:integer" json:"tahun_lulus,omitempty"`
	IsActive     bool             `gorm:"not null;default:true" json:"is_active"`
	LastLoginAt  *time.Time       `json:"last_login_at,omitempty"`
	Kelas        *Kelas           `gorm:"foreignKey:KelasID" json:"kelas,omitempty"`
	SocialLinks  []UserSocialLink `gorm:"foreignKey:UserID" json:"social_links,omitempty"`
}

func (User) TableName() string { return "users" }

// UserSocialLink
type UserSocialLink struct {
	ID        uuid.UUID      `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	UserID    uuid.UUID      `gorm:"type:uuid;not null" json:"user_id"`
	Platform  SocialPlatform `gorm:"type:social_platform;not null" json:"platform"`
	URL       string         `gorm:"type:text;not null" json:"url"`
	CreatedAt time.Time      `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time      `gorm:"not null;default:now()" json:"updated_at"`
}

func (UserSocialLink) TableName() string { return "user_social_links" }

// StudentClassHistory
type StudentClassHistory struct {
	ID            uuid.UUID    `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	UserID        uuid.UUID    `gorm:"type:uuid;not null" json:"user_id"`
	KelasID       uuid.UUID    `gorm:"type:uuid;not null" json:"kelas_id"`
	TahunAjaranID uuid.UUID    `gorm:"type:uuid;not null" json:"tahun_ajaran_id"`
	IsCurrent     bool         `gorm:"not null;default:false" json:"is_current"`
	CreatedAt     time.Time    `gorm:"not null;default:now()" json:"created_at"`
	Kelas         *Kelas       `gorm:"foreignKey:KelasID" json:"kelas,omitempty"`
	TahunAjaran   *TahunAjaran `gorm:"foreignKey:TahunAjaranID" json:"tahun_ajaran,omitempty"`
}

func (StudentClassHistory) TableName() string { return "student_class_history" }

// RefreshToken
type RefreshToken struct {
	ID            uuid.UUID  `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	UserID        uuid.UUID  `gorm:"type:uuid;not null" json:"user_id"`
	TokenHash     string     `gorm:"type:varchar(64);not null;uniqueIndex" json:"-"`
	FamilyID      uuid.UUID  `gorm:"type:uuid;not null" json:"family_id"`
	DeviceInfo    JSONB      `gorm:"type:jsonb" json:"device_info,omitempty"`
	IPAddress     *string    `gorm:"type:inet" json:"ip_address,omitempty"`
	IsRevoked     bool       `gorm:"not null;default:false" json:"is_revoked"`
	RevokedAt     *time.Time `json:"revoked_at,omitempty"`
	RevokedReason *string    `gorm:"type:varchar(100)" json:"revoked_reason,omitempty"`
	ExpiresAt     time.Time  `gorm:"not null" json:"expires_at"`
	CreatedAt     time.Time  `gorm:"not null;default:now()" json:"created_at"`
	LastUsedAt    *time.Time `json:"last_used_at,omitempty"`
	User          *User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (RefreshToken) TableName() string { return "refresh_tokens" }

// TokenBlacklist
type TokenBlacklist struct {
	ID            uuid.UUID  `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	JTI           string     `gorm:"type:varchar(64);not null;uniqueIndex" json:"jti"`
	UserID        *uuid.UUID `gorm:"type:uuid" json:"user_id,omitempty"`
	ExpiresAt     time.Time  `gorm:"not null" json:"expires_at"`
	BlacklistedAt time.Time  `gorm:"not null;default:now()" json:"blacklisted_at"`
	Reason        *string    `gorm:"type:varchar(100)" json:"reason,omitempty"`
}

func (TokenBlacklist) TableName() string { return "token_blacklist" }

// Follow
type Follow struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	FollowerID  uuid.UUID `gorm:"type:uuid;not null" json:"follower_id"`
	FollowingID uuid.UUID `gorm:"type:uuid;not null" json:"following_id"`
	CreatedAt   time.Time `gorm:"not null;default:now()" json:"created_at"`
	Follower    *User     `gorm:"foreignKey:FollowerID" json:"follower,omitempty"`
	Following   *User     `gorm:"foreignKey:FollowingID" json:"following,omitempty"`
}

func (Follow) TableName() string { return "follows" }

// Portfolio
type Portfolio struct {
	BaseModel
	UserID          uuid.UUID       `gorm:"type:uuid;not null" json:"user_id"`
	Judul           string          `gorm:"type:varchar(200);not null" json:"judul"`
	Slug            string          `gorm:"type:varchar(250);not null" json:"slug"`
	ThumbnailURL    *string         `gorm:"type:text" json:"thumbnail_url,omitempty"`
	Status          PortfolioStatus `gorm:"type:portfolio_status;not null;default:'draft'" json:"status"`
	AdminReviewNote *string         `gorm:"type:text" json:"admin_review_note,omitempty"`
	ReviewedBy      *uuid.UUID      `gorm:"type:uuid" json:"reviewed_by,omitempty"`
	ReviewedAt      *time.Time      `json:"reviewed_at,omitempty"`
	PublishedAt     *time.Time      `json:"published_at,omitempty"`
	User            *User           `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Reviewer        *User           `gorm:"foreignKey:ReviewedBy" json:"reviewer,omitempty"`
	Tags            []Tag           `gorm:"many2many:portfolio_tags" json:"tags,omitempty"`
	ContentBlocks   []ContentBlock  `gorm:"foreignKey:PortfolioID" json:"content_blocks,omitempty"`
}

func (Portfolio) TableName() string { return "portfolios" }

// PortfolioTag (junction table)
type PortfolioTag struct {
	PortfolioID uuid.UUID `gorm:"type:uuid;primaryKey" json:"portfolio_id"`
	TagID       uuid.UUID `gorm:"type:uuid;primaryKey" json:"tag_id"`
	CreatedAt   time.Time `gorm:"not null;default:now()" json:"created_at"`
}

func (PortfolioTag) TableName() string { return "portfolio_tags" }

// ContentBlock
type ContentBlock struct {
	ID          uuid.UUID        `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	PortfolioID uuid.UUID        `gorm:"type:uuid;not null" json:"portfolio_id"`
	BlockType   ContentBlockType `gorm:"type:content_block_type;not null" json:"block_type"`
	BlockOrder  int              `gorm:"not null" json:"block_order"`
	Payload     JSONB            `gorm:"type:jsonb;not null;default:'{}'" json:"payload"`
	CreatedAt   time.Time        `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt   time.Time        `gorm:"not null;default:now()" json:"updated_at"`
}

func (ContentBlock) TableName() string { return "content_blocks" }

// PortfolioLike
type PortfolioLike struct {
	UserID      uuid.UUID `gorm:"type:uuid;primaryKey" json:"user_id"`
	PortfolioID uuid.UUID `gorm:"type:uuid;primaryKey" json:"portfolio_id"`
	CreatedAt   time.Time `gorm:"not null;default:now()" json:"created_at"`
}

func (PortfolioLike) TableName() string { return "portfolio_likes" }

// AppSetting
type AppSetting struct {
	Key         string     `gorm:"type:varchar(100);primaryKey" json:"key"`
	Value       JSONB      `gorm:"type:jsonb;not null" json:"value"`
	Description *string    `gorm:"type:text" json:"description,omitempty"`
	UpdatedAt   time.Time  `gorm:"not null;default:now()" json:"updated_at"`
	UpdatedBy   *uuid.UUID `gorm:"type:uuid" json:"updated_by,omitempty"`
}

func (AppSetting) TableName() string { return "app_settings" }

// Feedback enums
type FeedbackKategori string

const (
	FeedbackKategoriBug     FeedbackKategori = "bug"
	FeedbackKategoriSaran   FeedbackKategori = "saran"
	FeedbackKategoriLainnya FeedbackKategori = "lainnya"
)

type FeedbackStatus string

const (
	FeedbackStatusPending  FeedbackStatus = "pending"
	FeedbackStatusRead     FeedbackStatus = "read"
	FeedbackStatusResolved FeedbackStatus = "resolved"
)

// Feedback
type Feedback struct {
	ID         uuid.UUID        `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	UserID     *uuid.UUID       `gorm:"type:uuid" json:"user_id,omitempty"`
	Kategori   FeedbackKategori `gorm:"type:feedback_kategori;not null" json:"kategori"`
	Pesan      string           `gorm:"type:text;not null" json:"pesan"`
	Status     FeedbackStatus   `gorm:"type:feedback_status;not null;default:'pending'" json:"status"`
	AdminNotes *string          `gorm:"type:text" json:"admin_notes,omitempty"`
	ResolvedBy *uuid.UUID       `gorm:"type:uuid" json:"resolved_by,omitempty"`
	ResolvedAt *time.Time       `json:"resolved_at,omitempty"`
	CreatedAt  time.Time        `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt  time.Time        `gorm:"not null;default:now()" json:"updated_at"`
	User       *User            `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Resolver   *User            `gorm:"foreignKey:ResolvedBy" json:"resolver,omitempty"`
}

func (Feedback) TableName() string { return "feedback" }

// ============================================================================
// ASSESSMENT MODELS
// ============================================================================

// AssessmentMetric - Master data metrik penilaian
type AssessmentMetric struct {
	BaseModel
	Nama      string  `gorm:"type:varchar(100);not null" json:"nama"`
	Deskripsi *string `gorm:"type:text" json:"deskripsi,omitempty"`
	Urutan    int     `gorm:"not null;default:0" json:"urutan"`
	IsActive  bool    `gorm:"not null;default:true" json:"is_active"`
}

func (AssessmentMetric) TableName() string { return "assessment_metrics" }

// PortfolioAssessment - Header penilaian portfolio
type PortfolioAssessment struct {
	ID           uuid.UUID                  `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	PortfolioID  uuid.UUID                  `gorm:"type:uuid;not null;uniqueIndex" json:"portfolio_id"`
	AssessedBy   uuid.UUID                  `gorm:"type:uuid;not null" json:"assessed_by"`
	FinalComment *string                    `gorm:"type:text" json:"final_comment,omitempty"`
	TotalScore   *float64                   `gorm:"type:decimal(4,2)" json:"total_score,omitempty"`
	CreatedAt    time.Time                  `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt    time.Time                  `gorm:"not null;default:now()" json:"updated_at"`
	Portfolio    *Portfolio                 `gorm:"foreignKey:PortfolioID" json:"portfolio,omitempty"`
	Assessor     *User                      `gorm:"foreignKey:AssessedBy" json:"assessor,omitempty"`
	Scores       []PortfolioAssessmentScore `gorm:"foreignKey:AssessmentID" json:"scores,omitempty"`
}

func (PortfolioAssessment) TableName() string { return "portfolio_assessments" }

// PortfolioAssessmentScore - Detail nilai per metrik
type PortfolioAssessmentScore struct {
	ID           uuid.UUID         `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	AssessmentID uuid.UUID         `gorm:"type:uuid;not null" json:"assessment_id"`
	MetricID     uuid.UUID         `gorm:"type:uuid;not null" json:"metric_id"`
	Score        int               `gorm:"type:smallint;not null" json:"score"`
	Comment      *string           `gorm:"type:text" json:"comment,omitempty"`
	CreatedAt    time.Time         `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt    time.Time         `gorm:"not null;default:now()" json:"updated_at"`
	Metric       *AssessmentMetric `gorm:"foreignKey:MetricID" json:"metric,omitempty"`
}

func (PortfolioAssessmentScore) TableName() string { return "portfolio_assessment_scores" }

// ============================================================================
// NOTIFICATION MODELS
// ============================================================================

// NotificationType enum
type NotificationType string

const (
	NotifNewFollower       NotificationType = "new_follower"
	NotifPortfolioLiked    NotificationType = "portfolio_liked"
	NotifPortfolioApproved NotificationType = "portfolio_approved"
	NotifPortfolioRejected NotificationType = "portfolio_rejected"
)

// Notification
type Notification struct {
	ID        uuid.UUID        `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	UserID    uuid.UUID        `gorm:"type:uuid;not null" json:"user_id"`
	Type      NotificationType `gorm:"type:notification_type;not null" json:"type"`
	Title     string           `gorm:"type:varchar(255);not null" json:"title"`
	Message   *string          `gorm:"type:text" json:"message,omitempty"`
	Data      JSONB            `gorm:"type:jsonb;default:'{}'" json:"data,omitempty"`
	IsRead    bool             `gorm:"default:false" json:"is_read"`
	ReadAt    *time.Time       `json:"read_at,omitempty"`
	CreatedAt time.Time        `gorm:"not null;default:now()" json:"created_at"`
	User      *User            `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (Notification) TableName() string { return "notifications" }
