package v1

import (
	"heyu/server/api/v1/biz"
	"heyu/server/api/v1/admin"
)

var APIs = new(APIPack)

type APIPack struct {
	Biz   biz.APIPack
	Admin admin.APIPack
}
