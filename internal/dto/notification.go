package dto

import "time"

// NotificationResponse - response untuk notification
type NotificationResponse struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"`
	Title     string                 `json:"title"`
	Message   *string                `json:"message,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
	IsRead    bool                   `json:"is_read"`
	ReadAt    *time.Time             `json:"read_at,omitempty"`
	CreatedAt time.Time              `json:"created_at"`
}

// NotificationCountResponse - response untuk unread count
type NotificationCountResponse struct {
	UnreadCount int64 `json:"unread_count"`
}

// NotificationListMeta - meta untuk list notifications
type NotificationListMeta struct {
	Page        int   `json:"page"`
	Limit       int   `json:"limit"`
	Total       int64 `json:"total"`
	TotalPages  int   `json:"total_pages"`
	UnreadCount int64 `json:"unread_count"`
}
