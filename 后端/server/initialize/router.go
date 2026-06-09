package initialize

import (
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"heyu/server/global"
	"heyu/server/middleware"
	"heyu/server/router"
)

type justFilesFilesystem struct {
	fs http.FileSystem
}

func (fs justFilesFilesystem) Open(name string) (http.File, error) {
	f, err := fs.fs.Open(name)
	if err != nil {
		return nil, err
	}

	stat, err := f.Stat()
	if stat.IsDir() {
		return nil, os.ErrPermission
	}

	return f, nil
}

// 初始化总路由

func Routers() *gin.Engine {
	Router := gin.New()
	Router.Use(middleware.SecurityHeaders())
	// 使用自定义的 Recovery 中间件，记录 panic 并入库
	Router.Use(middleware.GinRecovery(true))
	if gin.Mode() == gin.DebugMode {
		Router.Use(gin.Logger())
	}

	adminRouter := router.Routers.Admin
	// 如果想要不使用nginx代理前端网页，可以修改 web/.env.production 下的
	// VUE_APP_BASE_API = /
	// VUE_APP_BASE_PATH = 本地访问地址
	// 然后执行打包命令 npm run build。在打开下面3行注释
	// Router.StaticFile("/favicon.ico", "./dist/favicon.ico")
	// Router.Static("/assets", "./dist/assets")   // dist里面的静态资源
	// Router.StaticFile("/", "./dist/index.html") // 前端网页入口页面

	Router.StaticFS(global.AppConfig.Local.StorePath, justFilesFilesystem{http.Dir(global.AppConfig.Local.StorePath)}) // Router.Use(middleware.LoadTls())  // 如果需要使用https 请打开此中间件 然后前往 core/server.go 将启动模式 更变为 Router.RunTLS("端口","你的cre/pem文件","你的key文件")
	// 跨域，如需跨域可以打开下面的注释
	// Router.Use(middleware.Cors()) // 直接放行全部跨域请求
	Router.Use(middleware.CorsByRules()) // 按照配置的规则放行跨域请求
	// global.AppLog.Info("use middleware cors")
	// 方便统一添加路由组前缀 多服务器上线使用

	// /health 这类运维探针不走 slug，根路径即可访问，方便 k8s / 负载均衡健康检查
	OpsGroup := Router.Group("")
	PublicGroup := Router.Group(global.AppConfig.System.RouterPrefix)
	PrivateGroup := Router.Group(global.AppConfig.System.RouterPrefix)

	PrivateGroup.Use(middleware.JWTAuth()).Use(middleware.CasbinHandler())

	{
		// 健康监测
		OpsGroup.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, "ok")
		})
	}
	{
		adminRouter.InitBaseRouter(PublicGroup) // 注册基础功能路由 不做鉴权
	}

	{
		adminRouter.InitApiRouter(PrivateGroup, PublicGroup)      // 注册功能api路由
		adminRouter.InitJwtRouter(PrivateGroup)                   // jwt相关路由
		adminRouter.InitCaptchaConfigRouter(PrivateGroup)         // 验证码配置
		adminRouter.InitUserRouter(PrivateGroup)                  // 注册用户路由
		adminRouter.InitMenuRouter(PrivateGroup)                  // 注册menu路由
		adminRouter.InitCasbinRouter(PrivateGroup)                // 权限相关路由
		adminRouter.InitRoleRouter(PrivateGroup)                  // 注册角色路由
		adminRouter.InitOperationRecordRouter(PrivateGroup)       // 操作记录
		adminRouter.InitRoleButtonBindingRouter(PrivateGroup)     // 按钮权限管理
		adminRouter.InitFileUploadAndDownloadRouter(PrivateGroup) // 媒体库文件管理
		adminRouter.InitAttachmentCategoryRouter(PrivateGroup)    // 媒体库分类管理
		adminRouter.InitNotificationRouter(PrivateGroup)          // 通知中心（系统/安全/业务）
		adminRouter.InitRemoteAdminRouter(PrivateGroup)           // 远程业务后台管理
	}

	RemoteGroup := Router.Group("")

	// 注册业务路由
	initBizRouter(PrivateGroup, PublicGroup, RemoteGroup)

	global.AppRouters = Router.Routes()

	global.AppLog.Info("router register success")
	return Router
}
