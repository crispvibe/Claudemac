package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type NotificationApi struct{}

// GetList 获取当前用户的通知列表
func (n *NotificationApi) GetList(c *gin.Context) {
	var search systemReq.NotificationSearch
	if err := c.ShouldBindJSON(&search); err != nil {
		failInvalidParams(c)
		return
	}
	userID := utils.GetUserID(c)
	if userID == 0 {
		response.Unauthorized("未登录", c)
		return
	}
	list, total, err := notificationService.List(userID, search)
	if err != nil {
		global.AppLog.Error("获取通知列表失败", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(response.PageResult{
		List:     list,
		Total:    total,
		Page:     search.Page,
		PageSize: search.PageSize,
	}, "获取成功", c)
}

// UnreadCount 获取未读数
func (n *NotificationApi) UnreadCount(c *gin.Context) {
	userID := utils.GetUserID(c)
	if userID == 0 {
		response.Unauthorized("未登录", c)
		return
	}
	count, err := notificationService.UnreadCount(userID)
	if err != nil {
		global.AppLog.Error("获取未读数失败", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(gin.H{"unread": count}, "获取成功", c)
}

// Detail 获取通知详情
func (n *NotificationApi) Detail(c *gin.Context) {
	var param request.GetById
	if err := c.ShouldBindJSON(&param); err != nil {
		failInvalidParams(c)
		return
	}
	userID := utils.GetUserID(c)
	if userID == 0 {
		response.Unauthorized("未登录", c)
		return
	}
	item, err := notificationService.Detail(userID, param.Uint())
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(item, "获取成功", c)
}

// MarkRead 标记单条已读
func (n *NotificationApi) MarkRead(c *gin.Context) {
	var param systemReq.MarkNotificationRead
	if err := c.ShouldBindJSON(&param); err != nil {
		failInvalidParams(c)
		return
	}
	userID := utils.GetUserID(c)
	if userID == 0 {
		response.Unauthorized("未登录", c)
		return
	}
	if err := notificationService.MarkRead(userID, param.ID); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已读", c)
}

// MarkAllRead 全部已读
func (n *NotificationApi) MarkAllRead(c *gin.Context) {
	userID := utils.GetUserID(c)
	if userID == 0 {
		response.Unauthorized("未登录", c)
		return
	}
	if err := notificationService.MarkAllRead(userID); err != nil {
		global.AppLog.Error("标记全部已读失败", zap.Error(err))
		response.ErrorMessage("操作失败", c)
		return
	}
	response.SuccessMessage("已全部标记为已读", c)
}
