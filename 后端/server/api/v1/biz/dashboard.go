package biz

import (
	"heyu/server/model/shared/response"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
)

type DashboardApi struct{}

func (a *DashboardApi) GetPanel(c *gin.Context) {
	panel, err := dashboardService.GetPanel(utils.GetUserRoleID(c))
	if err != nil {
		response.ErrorMessage("获取看板数据失败", c)
		return
	}
	response.SuccessPayload(panel, "获取成功", c)
}
