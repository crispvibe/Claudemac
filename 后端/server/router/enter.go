package router

import (
	"heyu/server/router/biz"
	"heyu/server/router/admin"
)

var Routers = new(RouterPack)

type RouterPack struct {
	Biz   biz.RouterPack
	Admin admin.RouterPack
}
