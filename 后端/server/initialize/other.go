package initialize

import (
	"heyu/server/global"
	"heyu/server/utils"
	"heyu/server/utils/local_cache"
)

func OtherInit() {
	dr, err := utils.ParseDuration(global.AppConfig.JWT.ExpiresTime)
	if err != nil {
		panic(err)
	}
	_, err = utils.ParseDuration(global.AppConfig.JWT.BufferTime)
	if err != nil {
		panic(err)
	}

	global.BlackCache = local_cache.NewCache(
		local_cache.SetDefaultExpire(dr),
	)
}
