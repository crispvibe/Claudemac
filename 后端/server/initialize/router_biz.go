package initialize

import (
	"github.com/gin-gonic/gin"
	"heyu/server/router"
)

func initBizRouter(routers ...*gin.RouterGroup) {
	privateGroup := routers[0]
	publicGroup := routers[1]
	remoteGroup := publicGroup
	if len(routers) > 2 {
		remoteGroup = routers[2]
	}
	_ = publicGroup
	bizRouter := router.Routers.Biz
	bizRouter.InitDashboardRouter(privateGroup)
	bizRouter.InitRemoteRouter(remoteGroup)
}

// 占位方法，保证文件可以正确加载，避免go空变量检测报错，请勿删除。
