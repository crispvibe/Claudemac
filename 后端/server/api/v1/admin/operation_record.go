package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type OperationRecordApi struct{}

// DeleteOperationRecord
// @Tags      OperationRecord
// @Summary   删除操作日志
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.OperationRecord      true  "操作日志模型"
// @Success   200   {object}  response.Response{msg=string}  "删除操作日志"
// @Router    /operation-logs/delete [delete]
func (s *OperationRecordApi) DeleteOperationRecord(c *gin.Context) {
	var record admin.OperationRecord
	err := c.ShouldBindJSON(&record)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = operationRecordService.DeleteOperationRecord(record)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

// DeleteOperationRecordsByIDs
// @Tags      OperationRecord
// @Summary   批量删除操作日志
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.IdsReq                 true  "批量删除操作日志"
// @Success   200   {object}  response.Response{msg=string}  "批量删除操作日志"
// @Router    /operation-logs/deleteByIds [delete]
func (s *OperationRecordApi) DeleteOperationRecordsByIDs(c *gin.Context) {
	var IDS request.IdsReq
	err := c.ShouldBindJSON(&IDS)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = operationRecordService.DeleteOperationRecordsByIDs(IDS)
	if err != nil {
		global.AppLog.Error("批量删除失败!", zap.Error(err))
		response.ErrorMessage("批量删除失败", c)
		return
	}
	response.SuccessMessage("批量删除成功", c)
}

// FindOperationRecord
// @Tags      OperationRecord
// @Summary   根据ID查询操作日志
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  query     admin.OperationRecord                                  true  "Id"
// @Success   200   {object}  response.Response{data=map[string]interface{},msg=string}  "根据ID查询操作日志"
// @Router    /operation-logs/detail [get]
func (s *OperationRecordApi) FindOperationRecord(c *gin.Context) {
	var record admin.OperationRecord
	err := c.ShouldBindQuery(&record)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(record, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	recordDetail, err := operationRecordService.GetOperationRecord(record.ID)
	if err != nil {
		global.AppLog.Error("查询失败!", zap.Error(err))
		response.ErrorMessage("查询失败", c)
		return
	}
	response.SuccessPayload(gin.H{"recordDetail": recordDetail}, "查询成功", c)
}

// GetOperationRecordList
// @Tags      OperationRecord
// @Summary   分页获取操作日志列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  query     request.OperationRecordSearch                        true  "页码, 每页大小, 搜索条件"
// @Success   200   {object}  response.Response{data=response.PageResult,msg=string}  "分页获取操作日志列表,返回包括列表,总数,页码,每页数量"
// @Router    /operation-logs/list [get]
func (s *OperationRecordApi) GetOperationRecordList(c *gin.Context) {
	var pageInfo systemReq.OperationRecordSearch
	err := c.ShouldBindQuery(&pageInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	list, total, err := operationRecordService.GetOperationRecordList(pageInfo)
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
