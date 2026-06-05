package admin

import (
	"time"

	"heyu/server/global"
)

// 通知分类
const (
	NotificationCategorySecurity = "security"
	NotificationCategorySystem   = "system"
	NotificationCategoryBusiness = "business"
)

// 通知风险级别
const (
	NotificationLevelInfo    = "info"
	NotificationLevelSuccess = "success"
	NotificationLevelWarning = "warning"
	NotificationLevelDanger  = "danger"
)

// SecurityNotification 系统/安全通知中心消息
// 约定：target_user_id=0 表示广播给所有管理员，否则仅可见于指定用户
type SecurityNotification struct {
	global.BaseModel
	Category     string `json:"category" gorm:"column:category;type:varchar(32);not null;default:'system';comment:通知分类"`
	Level        string `json:"level" gorm:"column:level;type:varchar(16);not null;default:'info';comment:风险级别"`
	Title        string `json:"title" gorm:"column:title;type:varchar(200);not null;default:'';comment:标题"`
	Content      string `json:"content" gorm:"column:content;type:text;comment:正文"`
	Source       string `json:"source" gorm:"column:source;type:varchar(64);not null;default:'';comment:事件来源"`
	RefType      string `json:"refType" gorm:"column:ref_type;type:varchar(64);not null;default:'';comment:关联业务类型"`
	RefID        string `json:"refId" gorm:"column:ref_id;type:varchar(64);not null;default:'';comment:关联业务ID"`
	TargetUserID uint   `json:"targetUserId" gorm:"column:target_user_id;type:bigint unsigned;not null;default:0;comment:目标用户ID,0广播"`
}

func (SecurityNotification) TableName() string {
	return "security_notifications"
}

// SecurityNotificationRead 用户对通知的已读状态
type SecurityNotificationRead struct {
	NotificationID uint      `json:"notificationId" gorm:"column:notification_id;type:bigint unsigned;primaryKey;comment:通知ID"`
	UserID         uint      `json:"userId" gorm:"column:user_id;type:bigint unsigned;primaryKey;comment:用户ID"`
	ReadAt         time.Time `json:"readAt" gorm:"column:read_at;type:datetime(3);not null;comment:标记已读时间"`
}

func (SecurityNotificationRead) TableName() string {
	return "security_notification_reads"
}
