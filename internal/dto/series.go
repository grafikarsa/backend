package dto

import (
	"time"

	"github.com/google/uuid"
)

// SeriesDTO untuk response
type SeriesDTO struct {
	ID        uuid.UUID `json:"id"`
	Nama      string    `json:"nama"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateSeriesRequest untuk admin create
type CreateSeriesRequest struct {
	Nama     string `json:"nama" validate:"required,max=100"`
	IsActive *bool  `json:"is_active,omitempty"` // default true
}

// UpdateSeriesRequest untuk admin update
type UpdateSeriesRequest struct {
	Nama     *string `json:"nama,omitempty" validate:"omitempty,max=100"`
	IsActive *bool   `json:"is_active,omitempty"`
}
