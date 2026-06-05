package admin

import (
	"heyu/server/api/v1"
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type LoginLogRouter struct{}

func (s *LoginLogRouter) InitLoginLogRouter(Router *gin.RouterGroup) {
	loginLogRouter := Router.Group("login-logs").Use(middleware.OperationRecord())
	loginLogRouterWithoutRecord := Router.Group("login-logs")
	loginLogApi := v1.APIs.Admin.LoginLogApi
	{
		loginLogRouter.DELETE("deleteLoginLog", loginLogApi.DeleteLoginLog)           // 删除登录日志
		loginLogRouter.DELETE("deleteLoginLogByIds", loginLogApi.DeleteLoginLogByIds) // 批量删除登录日志
	}
	{
		loginLogRouterWithoutRecord.GET("findLoginLog", loginLogApi.FindLoginLog)       // 根据ID获取登录日志(详情)
		loginLogRouterWithoutRecord.GET("getLoginLogList", loginLogApi.GetLoginLogList) // 获取登录日志列表
	}
}
