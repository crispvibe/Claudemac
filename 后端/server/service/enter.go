package service

import (
	"heyu/server/service/biz"
	"heyu/server/service/admin"
)

var Services = new(ServicePack)

type ServicePack struct {
	Biz   biz.ServicePack
	Admin admin.ServicePack
}
