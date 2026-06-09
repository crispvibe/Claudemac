package biz

import (
	"github.com/gin-gonic/gin"
	"heyu/server/middleware"
)

type RemoteRouter struct{}

func (r *RemoteRouter) InitRemoteRouter(publicGroup *gin.RouterGroup) {
	remoteRouter := publicGroup.Group("remote")
	{
		authRouter := remoteRouter.Group("auth")
		{
			authRouter.POST("register-code", remoteApi.RequestRegisterCode)
			authRouter.POST("register", remoteApi.Register)
			authRouter.POST("login", remoteApi.Login)
			authRouter.POST("refresh", remoteApi.Refresh)
			authRouter.POST("password-reset-code", remoteApi.RequestPasswordResetCode)
			authRouter.POST("reset-password", remoteApi.ResetPassword)
		}
		remoteRouter.GET("legal-documents", remoteApi.GetLegalDocument)
		remoteRouter.GET("app-footer", remoteApi.GetAppFooter)
		remoteRouter.GET("app-updates/check", remoteApi.CheckAppUpdate)
		remoteRouter.POST("payment/notify", remoteApi.PaymentNotify)
		remoteRouter.GET("signaling/ws", remoteApi.SignalingWebSocket)

		privateRouter := remoteRouter.Group("").Use(middleware.RemoteJWTAuth())
		{
			privateRouter.POST("auth/change-password", remoteApi.ChangePassword)
			privateRouter.POST("account/deletion", remoteApi.DeleteAccount)
			privateRouter.POST("devices/register", remoteApi.RegisterDevice)
			privateRouter.GET("devices", remoteApi.ListDevices)
			privateRouter.GET("devices/:deviceId", remoteApi.GetDevice)
			privateRouter.PATCH("devices/:deviceId", remoteApi.UpdateDevice)
			privateRouter.GET("devices/:deviceId/device-code", remoteApi.GetDeviceCode)
			privateRouter.POST("devices/:deviceId/device-code/reset", remoteApi.ResetDeviceCode)
			privateRouter.POST("device-codes/resolve", remoteApi.ResolveDeviceCode)
			privateRouter.POST("devices/:deviceId/connect", remoteApi.Connect)
			privateRouter.GET("ice-config", remoteApi.GetICEServers)
			privateRouter.GET("turn/ice-servers", remoteApi.GetICEServers)
			privateRouter.GET("connections", remoteApi.ListConnections)
			privateRouter.GET("connections/:connectionId", remoteApi.GetConnection)
			privateRouter.POST("connections/:connectionId/metrics", remoteApi.ReportConnectionMetrics)
			privateRouter.POST("connections/:connectionId/approve", remoteApi.ApproveConnection)
			privateRouter.POST("connections/:connectionId/reject", remoteApi.RejectConnection)
			privateRouter.POST("legal-consents", remoteApi.ConsentLegal)
			privateRouter.GET("subscription", remoteApi.GetSubscription)
			privateRouter.GET("subscription/plans", remoteApi.ListSubscriptionPlans)
			privateRouter.POST("subscription/orders", remoteApi.CreateSubscriptionOrder)
			privateRouter.GET("subscription/orders/:outTradeNo", remoteApi.GetSubscriptionOrder)
		}
	}
}
