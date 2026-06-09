package request

import (
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
)

type LoginLogSearch struct {
	admin.LoginLog
	request.PageInfo
}