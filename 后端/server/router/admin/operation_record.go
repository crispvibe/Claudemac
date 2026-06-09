package admin

import (
	"github.com/gin-gonic/gin"
)

type OperationRecordRouter struct{}

func (s *OperationRecordRouter) InitOperationRecordRouter(Router *gin.RouterGroup) {
	operationRecordRouter := Router.Group("operation-logs")
	{
		operationRecordRouter.DELETE("delete", operationRecordApi.DeleteOperationRecord)            // 删除操作日志
		operationRecordRouter.DELETE("deleteByIds", operationRecordApi.DeleteOperationRecordsByIDs) // 批量删除操作日志
		operationRecordRouter.GET("detail", operationRecordApi.FindOperationRecord)                 // 根据ID查询操作日志
		operationRecordRouter.GET("list", operationRecordApi.GetOperationRecordList)                // 分页获取操作日志列表
	}
}
