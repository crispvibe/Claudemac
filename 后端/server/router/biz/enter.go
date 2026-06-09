package biz

import api "heyu/server/api/v1"

type RouterPack struct {
	DashboardRouter
	RemoteRouter
}

var (
	dashboardApi = api.APIs.Biz.DashboardApi
	remoteApi    = api.APIs.Biz.RemoteApi
)
