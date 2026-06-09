package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type JwtApi struct{}

// JsonInBlacklist
// @Tags      Jwt
// @Summary   jwt加入黑名单
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200  {object}  response.Response{msg=string}  "jwt加入黑名单"
// @Router    /auth-tokens/jsonInBlacklist [post]
func (j *JwtApi) JsonInBlacklist(c *gin.Context) {
	token := utils.GetToken(c)
	jwt := admin.JwtBlacklist{Jwt: token}
	err := jwtService.JsonInBlacklist(jwt)
	if err != nil {
		global.AppLog.Error("jwt作废失败!", zap.Error(err))
		response.ErrorMessage("jwt作废失败", c)
		return
	}
	utils.ClearToken(c)
	response.SuccessMessage("jwt作废成功", c)
}
