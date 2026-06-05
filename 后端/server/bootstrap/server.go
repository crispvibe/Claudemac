package bootstrap

import (
	"fmt"
	"heyu/server/global"
	"heyu/server/initialize"
	"heyu/server/service/admin"
	"go.uber.org/zap"
	"time"
)

func RunServer() {
	if global.AppConfig.System.UseRedis {
		// 初始化redis服务
		initialize.Redis()
		if global.AppConfig.System.UseMultipoint {
			initialize.RedisList()
		}
	}

	if global.AppConfig.System.UseMongo {
		err := initialize.Mongo.Initialization()
		if err != nil {
			zap.L().Error(fmt.Sprintf("%+v", err))
		}
	}
	// 从db加载jwt数据
	if global.AppDB != nil {
		admin.LoadAll()
	}

	Router := initialize.Routers()
	if global.AppDB != nil {
		admin.BootstrapSystemMetadata()
	}

	address := fmt.Sprintf(":%d", global.AppConfig.System.Addr)

	
	initServer(address, Router, 10*time.Minute, 10*time.Minute)
}
