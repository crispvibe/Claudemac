package global

import (
	"fmt"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/qiniu/qmgo"

	"heyu/server/utils/local_cache"
	"heyu/server/utils/timer"

	"golang.org/x/sync/singleflight"

	"go.uber.org/zap"

	"heyu/server/setting"

	"github.com/redis/go-redis/v9"
	"github.com/spf13/viper"
	"gorm.io/gorm"
)

var (
	AppDB        *gorm.DB
	AppDBList    map[string]*gorm.DB
	AppRedis     redis.UniversalClient
	AppRedisList map[string]redis.UniversalClient
	AppMongo     *qmgo.QmgoClient
	AppConfig    setting.Server
	AppVP        *viper.Viper
	// AppLog    *oplogging.Logger
	AppLog                 *zap.Logger
	AppTimer               timer.Timer = timer.NewTimerTask()
	AppConcurrencyControl             = &singleflight.Group{}
	AppRouters             gin.RoutesInfo
	AppActiveDBName       *string
	BlackCache              local_cache.Cache
	lock                    sync.RWMutex
)

// GetGlobalDBByDBName 通过名称获取db list中的db
func GetGlobalDBByDBName(dbname string) *gorm.DB {
	lock.RLock()
	defer lock.RUnlock()
	return AppDBList[dbname]
}

// MustGetGlobalDBByDBName 通过名称获取db 如果不存在则panic
func MustGetGlobalDBByDBName(dbname string) *gorm.DB {
	lock.RLock()
	defer lock.RUnlock()
	db, ok := AppDBList[dbname]
	if !ok || db == nil {
		panic("db no init")
	}
	return db
}

func GetRedis(name string) redis.UniversalClient {
	redis, ok := AppRedisList[name]
	if !ok || redis == nil {
		panic(fmt.Sprintf("redis `%s` no init", name))
	}
	return redis
}
