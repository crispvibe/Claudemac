package biz

var SharedRemoteSignalingService = &RemoteSignalingService{}

type ServicePack struct {
	DashboardService
	RemoteService
}
