package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type RoleRouter struct{}

func (s *RoleRouter) InitRoleRouter(Router *gin.RouterGroup) {
	roleRouter := Router.Group("roles").Use(middleware.OperationRecord())
	roleRouterWithoutRecord := Router.Group("roles")
	{
		roleRouter.POST("create", roleApi.CreateRole)                  // 创建角色
		roleRouter.POST("delete", roleApi.DeleteRole)                  // 删除角色
		roleRouter.PUT("update", roleApi.UpdateRole)                   // 更新角色
		roleRouter.POST("copy", roleApi.CopyRole)                      // 拷贝角色
		roleRouter.POST("data-scope", roleApi.SetRoleDataScope)        // 设置角色资源权限
	}
	{
		roleRouterWithoutRecord.POST("list", roleApi.GetRoleList)                 // 获取角色列表
	}
}
