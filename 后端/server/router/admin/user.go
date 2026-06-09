package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type UserRouter struct{}

func (s *UserRouter) InitUserRouter(Router *gin.RouterGroup) {
	accountRouter := Router.Group("accounts").Use(middleware.OperationRecord())
	accountRouterWithoutRecord := Router.Group("accounts")
	{
		accountRouter.POST("create", baseApi.Register)                   // 管理员注册账号
		accountRouter.POST("password/change", baseApi.ChangePassword)    // 用户修改密码
		accountRouter.POST("role/primary", baseApi.SetUserPrimaryRole)   // 设置用户权限
		accountRouter.DELETE("remove", baseApi.DeleteUser)               // 删除用户
		accountRouter.PUT("update", baseApi.SetUserInfo)                 // 设置用户信息
		accountRouter.PUT("profile", baseApi.SetSelfInfo)                // 设置自身信息
		accountRouter.POST("roles/update", baseApi.SetUserRoles)         // 设置用户权限组
		accountRouter.POST("password/reset", baseApi.ResetPassword)      // 重置用户密码
		accountRouter.PUT("preferences", baseApi.SetSelfSetting)         // 用户界面配置
	}
	{
		accountRouterWithoutRecord.POST("list", baseApi.GetUserList)     // 分页获取用户列表
		accountRouterWithoutRecord.GET("profile", baseApi.GetUserInfo)   // 获取自身信息
	}
}
