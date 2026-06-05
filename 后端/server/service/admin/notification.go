package admin

import (
	"errors"
	"time"

	"heyu/server/global"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/model/shared/request"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

type NotificationService struct{}

// NotificationItem 列表返回附带已读状态
type NotificationItem struct {
	admin.SecurityNotification
	Read bool `json:"read"`
}

// Publish 发布一条通知，内部调用点统一入口
func (s *NotificationService) Publish(n admin.SecurityNotification) error {
	if global.AppDB == nil {
		return errors.New("database not initialized")
	}
	if n.Category == "" {
		n.Category = admin.NotificationCategorySystem
	}
	if n.Level == "" {
		n.Level = admin.NotificationLevelInfo
	}
	return global.AppDB.Create(&n).Error
}

// PublishAsync 异步发布（安全事件回调不阻塞主流程）
func (s *NotificationService) PublishAsync(n admin.SecurityNotification) {
	go func() {
		if err := s.Publish(n); err != nil {
			global.AppLog.Error("发布通知失败", zap.Error(err))
		}
	}()
}

// List 分页获取指定用户可见的通知 + 已读状态
func (s *NotificationService) List(userID uint, info systemReq.NotificationSearch) (items []NotificationItem, total int64, err error) {
	db := global.AppDB.Model(&admin.SecurityNotification{}).
		Where("target_user_id = ? OR target_user_id = 0", userID)
	if info.Category != "" {
		db = db.Where("category = ?", info.Category)
	}
	if info.Level != "" {
		db = db.Where("level = ?", info.Level)
	}
	if info.OnlyUnread {
		sub := global.AppDB.Model(&admin.SecurityNotificationRead{}).
			Select("notification_id").
			Where("user_id = ?", userID)
		db = db.Where("id NOT IN (?)", sub)
	}
	if err = db.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var raw []admin.SecurityNotification
	if err = db.Scopes(info.PageInfo.Paginate()).Order("id desc").Find(&raw).Error; err != nil {
		return nil, 0, err
	}
	if len(raw) == 0 {
		return []NotificationItem{}, total, nil
	}
	ids := make([]uint, 0, len(raw))
	for _, n := range raw {
		ids = append(ids, n.ID)
	}
	var reads []admin.SecurityNotificationRead
	if err = global.AppDB.Where("user_id = ? AND notification_id IN ?", userID, ids).Find(&reads).Error; err != nil {
		return nil, 0, err
	}
	readSet := make(map[uint]struct{}, len(reads))
	for _, r := range reads {
		readSet[r.NotificationID] = struct{}{}
	}
	items = make([]NotificationItem, 0, len(raw))
	for _, n := range raw {
		_, ok := readSet[n.ID]
		items = append(items, NotificationItem{SecurityNotification: n, Read: ok})
	}
	return items, total, nil
}

// UnreadCount 统计用户未读数量
func (s *NotificationService) UnreadCount(userID uint) (int64, error) {
	sub := global.AppDB.Model(&admin.SecurityNotificationRead{}).
		Select("notification_id").
		Where("user_id = ?", userID)
	var count int64
	err := global.AppDB.Model(&admin.SecurityNotification{}).
		Where("target_user_id = ? OR target_user_id = 0", userID).
		Where("id NOT IN (?)", sub).
		Count(&count).Error
	return count, err
}

// Detail 获取详情并鉴权（仅本人或广播）
func (s *NotificationService) Detail(userID, id uint) (admin.SecurityNotification, error) {
	var n admin.SecurityNotification
	if err := global.AppDB.First(&n, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return n, errors.New("通知不存在")
		}
		return n, err
	}
	if n.TargetUserID != 0 && n.TargetUserID != userID {
		return n, errors.New("通知不存在")
	}
	return n, nil
}

// MarkRead 标记单条已读
func (s *NotificationService) MarkRead(userID, id uint) error {
	if _, err := s.Detail(userID, id); err != nil {
		return err
	}
	read := admin.SecurityNotificationRead{
		NotificationID: id,
		UserID:         userID,
		ReadAt:         time.Now(),
	}
	// primary key (notification_id,user_id) 冲突时忽略，保持首次已读时间
	return global.AppDB.Where("notification_id = ? AND user_id = ?", id, userID).
		Attrs(admin.SecurityNotificationRead{ReadAt: read.ReadAt}).
		FirstOrCreate(&read).Error
}

// MarkAllRead 标记全部已读
func (s *NotificationService) MarkAllRead(userID uint) error {
	var notifications []admin.SecurityNotification
	if err := global.AppDB.Model(&admin.SecurityNotification{}).
		Select("id").
		Where("target_user_id = ? OR target_user_id = 0", userID).
		Find(&notifications).Error; err != nil {
		return err
	}
	if len(notifications) == 0 {
		return nil
	}
	// 仅插入未读条目
	sub := global.AppDB.Model(&admin.SecurityNotificationRead{}).
		Select("notification_id").
		Where("user_id = ?", userID)
	var unreadIDs []uint
	if err := global.AppDB.Model(&admin.SecurityNotification{}).
		Where("target_user_id = ? OR target_user_id = 0", userID).
		Where("id NOT IN (?)", sub).
		Pluck("id", &unreadIDs).Error; err != nil {
		return err
	}
	if len(unreadIDs) == 0 {
		return nil
	}
	now := time.Now()
	reads := make([]admin.SecurityNotificationRead, 0, len(unreadIDs))
	for _, id := range unreadIDs {
		reads = append(reads, admin.SecurityNotificationRead{
			NotificationID: id,
			UserID:         userID,
			ReadAt:         now,
		})
	}
	return global.AppDB.Create(&reads).Error
}

// 语义包装，避免调用方裸用 request 包
var _ = request.Empty{}
