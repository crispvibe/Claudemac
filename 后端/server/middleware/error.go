package middleware

import (
	"net"
	"net/http"
	"os"
	"runtime/debug"
	"strings"

	"heyu/server/global"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// GinRecovery recover掉项目可能出现的panic，并使用zap记录相关日志
func GinRecovery(stack bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				// Check for a broken connection, as it is not really a
				// condition that warrants a panic stack trace.
				var brokenPipe bool
				if ne, ok := err.(*net.OpError); ok {
					if se, ok := ne.Err.(*os.SyscallError); ok {
						if strings.Contains(strings.ToLower(se.Error()), "broken pipe") || strings.Contains(strings.ToLower(se.Error()), "connection reset by peer") {
							brokenPipe = true
						}
					}
				}

				if brokenPipe {
					global.AppLog.Error(c.Request.URL.Path,
						zap.Any("error", err),
						zap.String("method", c.Request.Method),
						zap.String("path", c.Request.URL.Path),
					)
					// If the connection is dead, we can't write a status to it.
					_ = c.Error(err.(error)) // nolint: errcheck
					c.Abort()
					return
				}

				if stack {
					global.AppLog.Error("[Recovery from panic]",
						zap.Any("error", err),
						zap.String("stack", string(debug.Stack())),
						zap.String("method", c.Request.Method),
						zap.String("path", c.Request.URL.Path),
					)
				} else {
					global.AppLog.Error("[Recovery from panic]",
						zap.Any("error", err),
						zap.String("method", c.Request.Method),
						zap.String("path", c.Request.URL.Path),
					)
				}
				c.AbortWithStatus(http.StatusInternalServerError)
			}
		}()
		c.Next()
	}
}
