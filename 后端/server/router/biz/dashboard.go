package biz

import "github.com/gin-gonic/gin"

type DashboardRouter struct{}

func (r *DashboardRouter) InitDashboardRouter(Router *gin.RouterGroup) {
	dashboardRouter := Router.Group("dashboard")
	{
		dashboardRouter.GET("panel", dashboardApi.GetPanel)
	}
}
