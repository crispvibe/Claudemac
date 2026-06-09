package request

import (
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
)

type OperationRecordSearch struct {
	admin.OperationRecord
	request.PageInfo
}