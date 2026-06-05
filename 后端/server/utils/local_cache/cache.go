// Package local_cache 提供进程内轻量缓存的本地封装，屏蔽底层第三方实现。
//
// 设计目标：
//   - 对外暴露一个稳定的 Cache 接口（Get/GetWithExpire/Set/SetDefault/Delete/Increment）。
//   - 接口语义与项目历史调用完全一致（JWT 黑名单、IP 登录失败计数、限流计数）。
//   - 业务代码只依赖本包，不再直接引入任何带有框架指纹的第三方缓存库。
package local_cache

import (
	"time"

	gocache "github.com/patrickmn/go-cache"
)

// Cache 是进程内缓存对外暴露的最小稳定接口。
type Cache interface {
	Get(key string) (interface{}, bool)
	GetWithExpire(key string) (interface{}, time.Time, bool)
	Set(key string, value interface{}, ttl time.Duration)
	SetDefault(key string, value interface{})
	Delete(key string)
	Increment(key string, delta int64) error
}

// Option 用于 NewCache 的函数式配置。
type Option func(*options)

type options struct {
	defaultExpire   time.Duration
	cleanupInterval time.Duration
}

// SetDefaultExpire 设置默认过期时间（兼容历史调用名）。
func SetDefaultExpire(d time.Duration) Option {
	return func(o *options) { o.defaultExpire = d }
}

// SetCleanupInterval 设置后台清理过期项的周期。
func SetCleanupInterval(d time.Duration) Option {
	return func(o *options) { o.cleanupInterval = d }
}

type adapter struct {
	c *gocache.Cache
}

// NewCache 构造一个实现 Cache 接口的本地缓存实例。
func NewCache(opts ...Option) Cache {
	o := options{
		defaultExpire:   gocache.NoExpiration,
		cleanupInterval: 10 * time.Minute,
	}
	for _, f := range opts {
		f(&o)
	}
	return &adapter{c: gocache.New(o.defaultExpire, o.cleanupInterval)}
}

func (a *adapter) Get(key string) (interface{}, bool) {
	return a.c.Get(key)
}

func (a *adapter) GetWithExpire(key string) (interface{}, time.Time, bool) {
	return a.c.GetWithExpiration(key)
}

func (a *adapter) Set(key string, value interface{}, ttl time.Duration) {
	a.c.Set(key, value, ttl)
}

func (a *adapter) SetDefault(key string, value interface{}) {
	a.c.SetDefault(key, value)
}

func (a *adapter) Delete(key string) {
	a.c.Delete(key)
}

func (a *adapter) Increment(key string, delta int64) error {
	return a.c.Increment(key, delta)
}
