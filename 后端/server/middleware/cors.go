package middleware

import (
	"heyu/server/setting"
	"heyu/server/global"
	"github.com/gin-gonic/gin"
	"net/http"
)

// CorsByRules 按照配置处理跨域请求
func CorsByRules() gin.HandlerFunc {
	return func(c *gin.Context) {
		currentOrigin := c.GetHeader("origin")
		if global.AppConfig.Cors.Mode == "allow-all" {
			if currentOrigin != "" {
				c.Header("Access-Control-Allow-Origin", currentOrigin)
				c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-CSRF-Token")
				c.Header("Access-Control-Allow-Methods", "POST, GET, OPTIONS,DELETE,PUT")
				c.Header("Access-Control-Expose-Headers", "Content-Length, Access-Control-Allow-Origin, Access-Control-Allow-Headers, Content-Type")
				c.Header("Access-Control-Allow-Credentials", "true")
			}
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.Next()
			return
		}

		whitelist := checkCors(currentOrigin)

		// 通过检查, 添加请求头
		if whitelist != nil {
			c.Header("Access-Control-Allow-Origin", whitelist.AllowOrigin)
			c.Header("Access-Control-Allow-Headers", whitelist.AllowHeaders)
			c.Header("Access-Control-Allow-Methods", whitelist.AllowMethods)
			c.Header("Access-Control-Expose-Headers", whitelist.ExposeHeaders)
			if whitelist.AllowCredentials {
				c.Header("Access-Control-Allow-Credentials", "true")
			}
		}

		// 无 Origin 的同源 / 代理 / 非浏览器请求直接放行，仅对显式跨域请求执行白名单校验
		if currentOrigin == "" {
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.Next()
			return
		}

		// 严格白名单模式且未通过检查，直接拒绝处理请求
		if whitelist == nil && global.AppConfig.Cors.Mode == "strict-whitelist" && !(c.Request.Method == "GET" && c.Request.URL.Path == "/health") {
			c.AbortWithStatus(http.StatusForbidden)
			return
		} else {
			// 非严格白名单模式，无论是否通过检查均放行所有 OPTIONS 方法
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
		}

		// 处理请求
		c.Next()
	}
}

func checkCors(currentOrigin string) *setting.CORSWhitelist {
	for _, whitelist := range global.AppConfig.Cors.Whitelist {
		// 遍历配置中的跨域头，寻找匹配项
		if currentOrigin == whitelist.AllowOrigin {
			return &whitelist
		}
	}
	return nil
}
