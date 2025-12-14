package dto

import (
	"time"

	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/domain"
)

// SeriesDTO untuk response list
type SeriesDTO struct {
	ID             uuid.UUID `json:"id"`
	Nama           string    `json:"nama"`
	Deskripsi      *string   `json:"deskripsi,omitempty"`
	IsActive       bool      `json:"is_active"`
	BlockCount     int       `json:"block_count"`
	PortfolioCount int64     `json:"portfolio_count"`
	CreatedAt      time.Time `json:"created_at"`
}

// SeriesDetailDTO untuk response detail dengan blocks
type SeriesDetailDTO struct {
	ID             uuid.UUID        `json:"id"`
	Nama           string           `json:"nama"`
	Deskripsi      *string          `json:"deskripsi,omitempty"`
	IsActive       bool             `json:"is_active"`
	Blocks         []SeriesBlockDTO `json:"blocks"`
	PortfolioCount int64            `json:"portfolio_count"`
	CreatedAt      time.Time        `json:"created_at"`
}

// SeriesBlockDTO untuk response block template
type SeriesBlockDTO struct {
	ID         uuid.UUID `json:"id"`
	BlockType  string    `json:"block_type"`
	BlockOrder int       `json:"block_order"`
	Instruksi  string    `json:"instruksi"`
}

// SeriesBriefDTO untuk dropdown/select (minimal info)
type SeriesBriefDTO struct {
	ID         uuid.UUID        `json:"id"`
	Nama       string           `json:"nama"`
	Deskripsi  *string          `json:"deskripsi,omitempty"`
	BlockCount int              `json:"block_count"`
	Blocks     []SeriesBlockDTO `json:"blocks,omitempty"`
}

// CreateSeriesRequest untuk admin create
type CreateSeriesRequest struct {
	Nama      string                     `json:"nama" validate:"required,max=100"`
	Deskripsi *string                    `json:"deskripsi,omitempty"`
	IsActive  *bool                      `json:"is_active,omitempty"`
	Blocks    []CreateSeriesBlockRequest `json:"blocks" validate:"required,min=1"`
}

// CreateSeriesBlockRequest untuk block dalam create series
type CreateSeriesBlockRequest struct {
	BlockType string `json:"block_type" validate:"required"`
	Instruksi string `json:"instruksi" validate:"required"`
}

// UpdateSeriesRequest untuk admin update
type UpdateSeriesRequest struct {
	Nama      *string                    `json:"nama,omitempty" validate:"omitempty,max=100"`
	Deskripsi *string                    `json:"deskripsi,omitempty"`
	IsActive  *bool                      `json:"is_active,omitempty"`
	Blocks    []CreateSeriesBlockRequest `json:"blocks,omitempty"`
}

// Helper function to convert domain.SeriesBlock to DTO
func SeriesBlockToDTO(block domain.SeriesBlock) SeriesBlockDTO {
	return SeriesBlockDTO{
		ID:         block.ID,
		BlockType:  string(block.BlockType),
		BlockOrder: block.BlockOrder,
		Instruksi:  block.Instruksi,
	}
}

// Helper function to convert slice of domain.SeriesBlock to DTOs
func SeriesBlocksToDTOs(blocks []domain.SeriesBlock) []SeriesBlockDTO {
	result := make([]SeriesBlockDTO, len(blocks))
	for i, b := range blocks {
		result[i] = SeriesBlockToDTO(b)
	}
	return result
}
