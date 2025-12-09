package handler

import (
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/grafikarsa/backend/internal/dto"
	"github.com/grafikarsa/backend/internal/repository"
)

type PublicHandler struct {
	adminRepo *repository.AdminRepository
}

func NewPublicHandler(adminRepo *repository.AdminRepository) *PublicHandler {
	return &PublicHandler{adminRepo: adminRepo}
}

func (h *PublicHandler) ListJurusan(c *fiber.Ctx) error {
	jurusan, err := h.adminRepo.ListJurusan()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal mengambil data jurusan"))
	}

	var result []dto.JurusanDTO
	for _, j := range jurusan {
		result = append(result, dto.JurusanDTO{ID: j.ID, Nama: j.Nama, Kode: j.Kode})
	}

	return c.JSON(dto.SuccessResponse(result, ""))
}

func (h *PublicHandler) ListKelas(c *fiber.Ctx) error {
	var jurusanID *uuid.UUID
	var tingkat *int

	if id := c.Query("jurusan_id"); id != "" {
		parsed, _ := uuid.Parse(id)
		jurusanID = &parsed
	}
	if t := c.Query("tingkat"); t != "" {
		parsed, _ := strconv.Atoi(t)
		tingkat = &parsed
	}

	kelas, err := h.adminRepo.ListKelasPublic(jurusanID, tingkat)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(dto.ErrorResponse("INTERNAL_ERROR", "Gagal mengambil data kelas"))
	}

	var result []map[string]interface{}
	for _, k := range kelas {
		item := map[string]interface{}{
			"id":      k.ID,
			"nama":    k.Nama,
			"tingkat": k.Tingkat,
		}
		if k.Jurusan != nil {
			item["jurusan"] = dto.JurusanDTO{ID: k.Jurusan.ID, Nama: k.Jurusan.Nama}
		}
		result = append(result, item)
	}

	return c.JSON(dto.SuccessResponse(result, ""))
}
