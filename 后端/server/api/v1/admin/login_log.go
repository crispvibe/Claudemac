package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type LoginLogApi struct{}

func (s *LoginLogApi) DeleteLoginLog(c *gin.Context) {
	var loginLog admin.LoginLog
	err := c.ShouldBindJSON(&loginLog)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = loginLogService.DeleteLoginLog(loginLog)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

func (s *LoginLogApi) DeleteLoginLogByIds(c *gin.Context) {
	var SDS request.IdsReq
	err := c.ShouldBindJSON(&SDS)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = loginLogService.DeleteLoginLogByIds(SDS)
	if err != nil {
		global.AppLog.Error("批量删除失败!", zap.Error(err))
		response.ErrorMessage("批量删除失败", c)
		return
	}
	response.SuccessMessage("批量删除成功", c)
}

func (s *LoginLogApi) FindLoginLog(c *gin.Context) {
	var loginLog admin.LoginLog
	err := c.ShouldBindQuery(&loginLog)
	if err != nil {
		failInvalidParams(c)
		return
	}
	reLoginLog, err := loginLogService.GetLoginLog(loginLog.ID)
	if err != nil {
		global.AppLog.Error("查询失败!", zap.Error(err))
		response.ErrorMessage("查询失败", c)
		return
	}
	response.SuccessPayload(reLoginLog, "查询成功", c)
}

func (s *LoginLogApi) GetLoginLogList(c *gin.Context) {
	var pageInfo systemReq.LoginLogSearch
	err := c.ShouldBindQuery(&pageInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	list, total, err := loginLogService.GetLoginLogInfoList(pageInfo)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(response.PageResult{
		List:     list,
		Total:    total,
		Page:     pageInfo.Page,
		PageSize: pageInfo.PageSize,
	}, "获取成功", c)
}
