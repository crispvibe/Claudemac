package middleware

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"strconv"
	"strings"
)

// CasbinHandler 拦截器
func CasbinHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		waitUse, _ := utils.GetClaims(c)
		//获取请求的PATH
		path := c.Request.URL.Path
		obj := strings.TrimPrefix(path, global.AppConfig.System.RouterPrefix)
		// 获取请求方法
		act := c.Request.Method
		// 获取用户的角色
		sub := strconv.Itoa(int(waitUse.RoleID))
		e := utils.GetCasbin() // 判断策略中是否存在
		success, _ := e.Enforce(sub, obj, act)
		if !success {
			response.ErrorMessage("权限不足", c)
			c.Abort()
			return
		}
		c.Next()
	}
}
