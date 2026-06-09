package admin

import (
	"github.com/gin-gonic/gin"
	"heyu/server/middleware"
)

type RemoteAdminRouter struct{}

func (r *RemoteAdminRouter) InitRemoteAdminRouter(Router *gin.RouterGroup) {
	remoteRouter := Router.Group("remote-admin").Use(middleware.OperationRecord())
	remoteRouterWithoutRecord := Router.Group("remote-admin")
	{
		remoteRouterWithoutRecord.POST("users/list", remoteAdminApi.ListUsers)
		remoteRouter.POST("users/save", remoteAdminApi.SaveUser)
		remoteRouter.POST("users/status", remoteAdminApi.UpdateUserStatus)
		remoteRouter.POST("users/kick", remoteAdminApi.KickUser)
		remoteRouter.POST("users/ban", remoteAdminApi.BanUser)
		remoteRouter.POST("users/delete", remoteAdminApi.DeleteUser)
		remoteRouterWithoutRecord.POST("devices/list", remoteAdminApi.ListDevices)
		remoteRouter.POST("devices/update", remoteAdminApi.UpdateDevice)
		remoteRouter.POST("devices/kick", remoteAdminApi.KickDevice)
		remoteRouter.POST("devices/delete", remoteAdminApi.DeleteDevice)
		remoteRouterWithoutRecord.POST("connections/list", remoteAdminApi.ListConnections)
		remoteRouter.POST("connections/delete", remoteAdminApi.DeleteConnection)
		remoteRouterWithoutRecord.POST("code-attempts/list", remoteAdminApi.ListCodeAttempts)
		remoteRouter.POST("code-attempts/delete", remoteAdminApi.DeleteCodeAttempt)
		remoteRouterWithoutRecord.POST("legal-documents/list", remoteAdminApi.ListLegalDocuments)
		remoteRouter.POST("legal-documents/save", remoteAdminApi.SaveLegalDocument)
		remoteRouter.POST("legal-documents/delete", remoteAdminApi.DeleteLegalDocument)
		remoteRouterWithoutRecord.POST("app-footer/get", remoteAdminApi.GetAppFooter)
		remoteRouter.POST("app-footer/save", remoteAdminApi.SaveAppFooter)
		remoteRouterWithoutRecord.POST("app-updates/list", remoteAdminApi.ListAppUpdates)
		remoteRouter.POST("app-updates/save", remoteAdminApi.SaveAppUpdate)
		remoteRouter.POST("app-updates/delete", remoteAdminApi.DeleteAppUpdate)
		remoteRouterWithoutRecord.POST("legal-consents/list", remoteAdminApi.ListLegalConsents)
		remoteRouter.POST("legal-consents/delete", remoteAdminApi.DeleteLegalConsent)
		remoteRouterWithoutRecord.POST("subscription-plans/list", remoteAdminApi.ListSubscriptionPlans)
		remoteRouter.POST("subscription-plans/save", remoteAdminApi.SaveSubscriptionPlan)
		remoteRouterWithoutRecord.POST("subscription-orders/list", remoteAdminApi.ListSubscriptionOrders)
		remoteRouterWithoutRecord.POST("account-deletions/list", remoteAdminApi.ListAccountDeletions)
		remoteRouterWithoutRecord.POST("subscriptions/list", remoteAdminApi.ListSubscriptions)
		remoteRouter.POST("subscriptions/save", remoteAdminApi.SaveSubscription)
	}
}
