package middleware

import (
	"errors"
	"time"

	"heyu/server/global"
	"heyu/server/model/admin"
	"heyu/server/service"
	"heyu/server/utils"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"

	"heyu/server/model/shared/response"
	"github.com/gin-gonic/gin"
)

func JWTAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 鉴权优先读取 Authorization 头，其次回退到 httpOnly cookie，前端需配合统一的令牌续期策略
		token := utils.GetToken(c)
		if token == "" {
			response.Unauthorized("未登录或非法访问，请登录", c)
			c.Abort()
			return
		}
		if isBlacklist(token) {
			response.Unauthorized("您的帐户异地登陆或令牌失效", c)
			utils.ClearToken(c)
			c.Abort()
			return
		}
		j := utils.NewJWT()
		// parseToken 解析token包含的信息
		claims, err := j.ParseToken(token)
		if err != nil {
			if errors.Is(err, utils.TokenExpired) {
				response.Unauthorized("登录已过期，请重新登录", c)
				utils.ClearToken(c)
				c.Abort()
				return
			}
			global.AppLog.Warn("jwt parse failed", zap.Error(err))
			response.Unauthorized("登录状态无效，请重新登录", c)
			utils.ClearToken(c)
			c.Abort()
			return
		}

		userService := service.Services.Admin.UserService
		jwtService := service.Services.Admin.JwtService
		if user, err := userService.FindUserByUuid(claims.UUID.String()); err != nil || user.Enable != 1 {
			if blacklistErr := jwtService.JsonInBlacklist(admin.JwtBlacklist{Jwt: token}); blacklistErr != nil {
				global.AppLog.Warn("failed to blacklist disabled user token", zap.Error(blacklistErr))
			}
			response.Unauthorized("用户状态无效，请重新登录", c)
			utils.ClearToken(c)
			c.Abort()
			return
		}

		c.Set("claims", claims)
		if claims.ExpiresAt.Unix()-time.Now().Unix() < claims.BufferTime {
			dr, _ := utils.ParseDuration(global.AppConfig.JWT.ExpiresTime)
			claims.ExpiresAt = jwt.NewNumericDate(time.Now().Add(dr))
			newToken, _ := j.CreateTokenByOldToken(token, *claims)
			newClaims, _ := j.ParseToken(newToken)
			if blacklistErr := jwtService.JsonInBlacklist(admin.JwtBlacklist{Jwt: token}); blacklistErr != nil {
				global.AppLog.Warn("failed to blacklist rotated token", zap.Error(blacklistErr))
			}
			utils.SetToken(c, newToken, int(dr.Seconds()/60))
			if global.AppConfig.System.UseMultipoint {
				// 记录新的活跃jwt
				_ = utils.SetRedisJWT(newToken, newClaims.Username)
			}
		}
		c.Next()
	}
}

//@function: IsBlacklist
//@description: 判断JWT是否在黑名单内部
//@param: jwt string
//@return: bool

func isBlacklist(jwt string) bool {
	_, ok := global.BlackCache.Get(jwt)
	return ok
}
