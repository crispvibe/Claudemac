package admin

import (
	"heyu/server/middleware"

	"github.com/gin-gonic/gin"
)

type EmailConfigRouter struct{}

func (r *EmailConfigRouter) InitEmailConfigRouter(Router *gin.RouterGroup) {
	securityRouter := Router.Group("security").Use(middleware.OperationRecord())
	securityRouterReadonly := Router.Group("security")
	{
		securityRouterReadonly.GET("email-config", emailConfigApi.GetEmailConfig)
	}
	{
		securityRouter.PUT("email-config", emailConfigApi.UpdateEmailConfig)
		securityRouter.POST("email-config/test", emailConfigApi.SendTestEmail)
	}
}
