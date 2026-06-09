package biz

import (
	"go.uber.org/zap"
	"heyu/server/global"
)

func remoteAppLog() *zap.Logger {
	if global.AppLog != nil {
		return global.AppLog
	}
	return zap.NewNop()
}
