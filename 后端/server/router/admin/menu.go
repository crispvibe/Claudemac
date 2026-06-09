package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type MenuRouter struct{}

func (s *MenuRouter) InitMenuRouter(Router *gin.RouterGroup) (R gin.IRoutes) {
	menuRouter := Router.Group("navigation").Use(middleware.OperationRecord())
	menuRouterWithoutRecord := Router.Group("navigation")
	{
		menuRouter.POST("create", navigationApi.AddBaseMenu)                // 新增菜单
		menuRouter.POST("assign-role", navigationApi.AssignRoleNavigation)  //	增加menu和角色关联关系
		menuRouter.POST("delete", navigationApi.DeleteBaseMenu)             // 删除菜单
		menuRouter.POST("update", navigationApi.UpdateBaseMenu)             // 更新菜单
	}
	{
		menuRouterWithoutRecord.POST("routes", navigationApi.GetMenu)                    // 获取菜单树
		menuRouterWithoutRecord.POST("list", navigationApi.GetMenuList)                  // 分页获取基础menu列表
		menuRouterWithoutRecord.POST("tree", navigationApi.GetBaseMenuTree)              // 获取用户动态路由
		menuRouterWithoutRecord.POST("role-tree", navigationApi.GetRoleNavigation)       // 获取指定角色menu
		menuRouterWithoutRecord.POST("detail", navigationApi.GetBaseMenuById)            // 根据id获取菜单
	}
	return menuRouter
}
