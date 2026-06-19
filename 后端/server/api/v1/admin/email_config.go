package admin

import (
	systemReq "heyu/server/model/admin/request"
	"heyu/server/model/shared/response"

	"github.com/gin-gonic/gin"
)

type EmailConfigApi struct{}

func (a *EmailConfigApi) GetEmailConfig(c *gin.Context) {
	response.SuccessPayload(emailConfigService.GetEmailConfig(), "获取成功", c)
}

func (a *EmailConfigApi) UpdateEmailConfig(c *gin.Context) {
	var req systemReq.EmailConfigUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	result, err := emailConfigService.UpdateEmailConfig(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(result, "保存成功", c)
}

func (a *EmailConfigApi) SendTestEmail(c *gin.Context) {
	var req systemReq.EmailConfigTest
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	if err := emailConfigService.SendTestEmail(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("测试邮件已发送，请查收", c)
}
