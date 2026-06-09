package middleware

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"time"

	"go.uber.org/zap"

	"heyu/server/global"
	"heyu/server/model/shared/response"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

var limitCounterScript = redis.NewScript(`
 local current = redis.call("INCR", KEYS[1])
 if current == 1 then
   redis.call("PEXPIRE", KEYS[1], ARGV[2])
 end
 if current > tonumber(ARGV[1]) then
   return redis.call("PTTL", KEYS[1])
 end
 return 0
`)

type LimitConfig struct {
	// GenerationKey 根据业务生成key 下面CheckOrMark查询生成
	GenerationKey func(c *gin.Context) string
	// 检查函数,用户可修改具体逻辑,更加灵活
	CheckOrMark func(key string, expire int, limit int) error
	// Expire key 过期时间
	Expire int
	// Limit 周期时间
	Limit int
}

func (l LimitConfig) LimitWithTime() gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := l.CheckOrMark(l.GenerationKey(c), l.Expire, l.Limit); err != nil {
			c.JSON(http.StatusOK, gin.H{"code": response.ERROR, "msg": err.Error()})
			c.Abort()
			return
		} else {
			c.Next()
		}
	}
}

// DefaultGenerationKey 默认生成key
func DefaultGenerationKey(c *gin.Context) string {
	return "App_Limit" + c.ClientIP()
}

func DefaultCheckOrMark(key string, expire int, limit int) (err error) {
	// 判断是否开启redis
	if global.AppRedis == nil {
		if value, _, ok := global.BlackCache.GetWithExpire(key); ok {
			current := 0
			switch counter := value.(type) {
			case int:
				current = counter
			case int64:
				current = int(counter)
			case uint:
				current = int(counter)
			}
			if current >= limit {
				return errors.New("请求太过频繁，请稍后再试")
			}
			return global.BlackCache.Increment(key, 1)
		}
		global.BlackCache.Set(key, 1, time.Duration(expire)*time.Second)
		return nil
	}
	if err = SetLimitWithTime(key, limit, time.Duration(expire)*time.Second); err != nil {
		global.AppLog.Error("limit", zap.Error(err))
	}
	return err
}

func DefaultLimit() gin.HandlerFunc {
	return LimitConfig{
		GenerationKey: DefaultGenerationKey,
		CheckOrMark:   DefaultCheckOrMark,
		Expire:        global.AppConfig.System.LimitTimeIP,
		Limit:         global.AppConfig.System.LimitCountIP,
	}.LimitWithTime()
}

// SetLimitWithTime 设置访问次数
func SetLimitWithTime(key string, limit int, expiration time.Duration) error {
	result, err := limitCounterScript.Run(context.Background(), global.AppRedis, []string{key}, limit, expiration.Milliseconds()).Int64()
	if err != nil {
		return err
	}
	if result <= 0 {
		return nil
	}
	waitSeconds := int64(math.Ceil(float64(result) / 1000))
	if waitSeconds < 1 {
		waitSeconds = 1
	}
	return errors.New(fmt.Sprintf("请求太过频繁, 请 %d 秒后尝试", waitSeconds))
}
