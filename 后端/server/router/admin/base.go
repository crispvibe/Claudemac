package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type BaseRouter struct{}

func (s *BaseRouter) InitBaseRouter(Router *gin.RouterGroup) (R gin.IRoutes) {
	baseRouter := Router.Group("auth")
	{
		baseRouter.GET("captcha", baseApi.Captcha)
		baseRouter.GET("slide-captcha", middleware.DefaultLimit(), baseApi.GenerateSlideCaptcha)
		baseRouter.POST("slide-captcha/verify", middleware.DefaultLimit(), baseApi.VerifySlideCaptcha)
		baseRouter.POST("login", middleware.DefaultLimit(), baseApi.Login)
	}
	return baseRouter
}
