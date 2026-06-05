package admin

import (
	"github.com/gin-gonic/gin"
)

type RoleButtonBindingRouter struct{}

var RoleButtonBindingRouterApp = new(RoleButtonBindingRouter)

func (s *RoleButtonBindingRouter) InitRoleButtonBindingRouter(Router *gin.RouterGroup) {
	// roleButtonRouter := Router.Group("role-buttons").Use(middleware.OperationRecord())
	roleButtonRouterWithoutRecord := Router.Group("role-buttons")
	{
		roleButtonRouterWithoutRecord.POST("bindings", roleButtonBindingApi.GetRoleButtonBindings)
		roleButtonRouterWithoutRecord.POST("bindings/update", roleButtonBindingApi.UpdateRoleButtonBindings)
		roleButtonRouterWithoutRecord.POST("bindings/removal-check", roleButtonBindingApi.CanRemoveRoleButtonBinding)
	}
}
