package middleware

import (
	"strings"

	"heyu/server/global"
	"github.com/gin-gonic/gin"
)

// 默认 CSP：后端仅返回 JSON / 静态资源，去除 'unsafe-inline'，
// 避免误渲染 HTML 时被注入内联脚本/样式；前端 SPA 由 nginx 独立下发 CSP
var defaultCSP = strings.Join([]string{
	"default-src 'self'",
	"base-uri 'self'",
	"object-src 'none'",
	"frame-ancestors 'none'",
	"form-action 'self'",
	"script-src 'self'",
	"style-src 'self'",
	"img-src 'self' data: blob: http: https:",
	"font-src 'self' data:",
	"connect-src 'self' http: https: ws: wss:",
	"media-src 'self' blob: http: https:",
	"worker-src 'self' blob:",
}, "; ")

// 上传静态目录策略：即便攻击者绕过白名单塞了任意 HTML/SVG/JS，
// 浏览器也不会加载脚本/样式/字体，彻底堵死存储型 XSS
var uploadsCSP = strings.Join([]string{
	"default-src 'none'",
	"img-src 'self' data: blob:",
	"media-src 'self' blob:",
	"style-src 'none'",
	"script-src 'none'",
	"font-src 'none'",
	"connect-src 'none'",
	"base-uri 'none'",
	"form-action 'none'",
	"frame-ancestors 'none'",
	"sandbox",
}, "; ")

func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		if isUploadsPath(c.Request.URL.Path) {
			c.Header("Content-Security-Policy", uploadsCSP)
			// 静态资源默认以附件下载返回，避免浏览器主动渲染可疑文件
			if c.Request.Method == "GET" && c.GetHeader("X-Preview") == "" {
				c.Header("X-Download-Options", "noopen")
			}
		} else {
			c.Header("Content-Security-Policy", defaultCSP)
		}
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		if c.Request.TLS != nil {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}

func isUploadsPath(path string) bool {
	prefix := strings.TrimSpace(global.AppConfig.Local.Path)
	if prefix == "" {
		return false
	}
	if !strings.HasPrefix(prefix, "/") {
		prefix = "/" + prefix
	}
	return strings.HasPrefix(path, prefix+"/") || path == prefix
}
