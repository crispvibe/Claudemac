package biz

import (
	"heyu/server/service"
	bizService "heyu/server/service/biz"
)

type APIPack struct {
	DashboardApi
	RemoteApi
}

var (
	dashboardService       = service.Services.Biz.DashboardService
	remoteService          = service.Services.Biz.RemoteService
	remoteSignalingService = bizService.SharedRemoteSignalingService
)
