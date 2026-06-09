package request

import (
	"heyu/server/model/shared/request"
)

// NotificationSearch 通知列表查询
type NotificationSearch struct {
	request.PageInfo
	Category   string `json:"category" form:"category"`     // security/system/business
	Level      string `json:"level" form:"level"`           // info/success/warning/danger
	OnlyUnread bool   `json:"onlyUnread" form:"onlyUnread"` // 仅看未读
}

// MarkNotificationRead 标记单条已读
type MarkNotificationRead struct {
	ID uint `json:"id" form:"id" binding:"required"`
}
