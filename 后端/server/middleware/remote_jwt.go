package middleware

import (
	"github.com/gin-gonic/gin"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	"heyu/server/model/shared/response"
	"heyu/server/utils"
)

func RemoteJWTAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := utils.GetToken(c)
		if token == "" {
			response.Unauthorized("未登录或非法访问，请登录", c)
			c.Abort()
			return
		}
		claims, err := utils.ParseRemoteAccessToken(token)
		if err != nil {
			response.Unauthorized("登录状态无效，请重新登录", c)
			c.Abort()
			return
		}
		var user modelBiz.RemoteUser
		if err := global.AppDB.Select("id", "status", "token_version").First(&user, claims.UserID).Error; err != nil || user.Status != "active" || user.TokenVersion != claims.TokenVersion {
			response.Unauthorized("账号已禁用或不存在", c)
			c.Abort()
			return
		}
		c.Set("remoteClaims", claims)
		c.Next()
	}
}
