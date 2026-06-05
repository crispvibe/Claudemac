package admin

import (
	"heyu/server/api/v1"
	"github.com/gin-gonic/gin"
)

type NotificationRouter struct{}

func (s *NotificationRouter) InitNotificationRouter(Router *gin.RouterGroup) {
	r := Router.Group("notifications")
	notificationApi := v1.APIs.Admin.NotificationApi
	{
		r.POST("list", notificationApi.GetList)
		r.GET("unread-count", notificationApi.UnreadCount)
		r.POST("detail", notificationApi.Detail)
		r.POST("read", notificationApi.MarkRead)
		r.POST("read-all", notificationApi.MarkAllRead)
	}
}
