package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type CaptchaConfigRouter struct{}

func (r *CaptchaConfigRouter) InitCaptchaConfigRouter(Router *gin.RouterGroup) {
	securityRouter := Router.Group("security").Use(middleware.OperationRecord())
	securityRouterReadonly := Router.Group("security")
	{
		securityRouterReadonly.GET("captcha-config", baseApi.GetCaptchaConfig)
	}
	{
		securityRouter.PUT("captcha-config", baseApi.UpdateCaptchaConfig)
	}
}
