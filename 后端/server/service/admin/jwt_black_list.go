package admin

import (
	"context"

	"go.uber.org/zap"

	"heyu/server/global"
	"heyu/server/model/admin"
)

type JwtService struct{}

var JwtServiceApp = new(JwtService)

//@function: JsonInBlacklist
//@description: 拉黑jwt
//@param: jwtList model.JwtBlacklist
//@return: err error

func (jwtService *JwtService) JsonInBlacklist(jwtList admin.JwtBlacklist) (err error) {
	err = global.AppDB.Create(&jwtList).Error
	if err != nil {
		return
	}
	global.BlackCache.SetDefault(jwtList.Jwt, struct{}{})
	return
}

//@function: GetRedisJWT
//@description: 从redis取jwt
//@param: userName string
//@return: redisJWT string, err error

func (jwtService *JwtService) GetRedisJWT(userName string) (redisJWT string, err error) {
	redisJWT, err = global.AppRedis.Get(context.Background(), userName).Result()
	return redisJWT, err
}

func LoadAll() {
	var data []string
	err := global.AppDB.Model(&admin.JwtBlacklist{}).Select("jwt").Find(&data).Error
	if err != nil {
		global.AppLog.Error("加载数据库jwt黑名单失败!", zap.Error(err))
		return
	}
	for i := 0; i < len(data); i++ {
		global.BlackCache.SetDefault(data[i], struct{}{})
	} // jwt黑名单 加入 BlackCache 中
}
