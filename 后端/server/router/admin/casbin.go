package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type CasbinRouter struct{}

func (s *CasbinRouter) InitCasbinRouter(Router *gin.RouterGroup) {
	rolePolicyRouter := Router.Group("role-policies").Use(middleware.OperationRecord())
	rolePolicyRouterWithoutRecord := Router.Group("role-policies")
	{
		rolePolicyRouter.POST("update", casbinApi.UpdateCasbin)
	}
	{
		rolePolicyRouterWithoutRecord.POST("by-role", casbinApi.GetPolicyPathByRoleID)
	}
}
