package captcha

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"

	assetsImages "github.com/wenlng/go-captcha-assets/resources/images"
	assetsTiles "github.com/wenlng/go-captcha-assets/resources/tiles"
	"github.com/wenlng/go-captcha/v2/slide"
)

const (
	slideCaptchaChallengeTTL = 3 * time.Minute
	slideCaptchaTokenTTL     = 5 * time.Minute
	slideCaptchaTolerance    = 3 // 允许 ±3px 偏差
)

// SlidePayload 描述一次滑块挑战的响应数据。
type SlidePayload struct {
	CaptchaID     string `json:"captchaId"`
	MasterBase64  string `json:"masterBase64"`
	ThumbBase64   string `json:"thumbBase64"`
	ThumbWidth    int    `json:"thumbWidth"`
	ThumbHeight   int    `json:"thumbHeight"`
	ThumbY        int    `json:"thumbY"`
}

type slideChallenge struct {
	TargetX   int
	ExpiresAt time.Time
}

type slideToken struct {
	ExpiresAt time.Time
}

type slideCaptchaRegistry struct {
	mu         sync.Mutex
	challenges map[string]slideChallenge
	tokens     map[string]slideToken
	builder    slide.Captcha
}

var registry *slideCaptchaRegistry
var registryOnce sync.Once

func getRegistry() (*slideCaptchaRegistry, error) {
	var buildErr error
	registryOnce.Do(func() {
		builder := slide.NewBuilder(
			slide.WithGenGraphNumber(1),
			slide.WithEnableGraphVerticalRandom(true),
		)
		tiles, err := assetsTiles.GetTiles()
		if err != nil {
			buildErr = fmt.Errorf("加载滑块素材失败: %w", err)
			return
		}
		graphs := make([]*slide.GraphImage, 0, len(tiles))
		for i := 0; i < len(tiles); i++ {
			graphs = append(graphs, &slide.GraphImage{
				OverlayImage: tiles[i].OverlayImage,
				ShadowImage:  tiles[i].ShadowImage,
				MaskImage:    tiles[i].MaskImage,
			})
		}
		backgrounds, err := assetsImages.GetImages()
		if err != nil {
			buildErr = fmt.Errorf("加载背景素材失败: %w", err)
			return
		}
		builder.SetResources(
			slide.WithGraphImages(graphs),
			slide.WithBackgrounds(backgrounds),
		)
		registry = &slideCaptchaRegistry{
			challenges: make(map[string]slideChallenge),
			tokens:     make(map[string]slideToken),
			builder:    builder.Make(),
		}
	})
	if buildErr != nil {
		return nil, buildErr
	}
	return registry, nil
}

// GenerateSlide 生成一次滑块挑战。
func GenerateSlide() (SlidePayload, error) {
	r, err := getRegistry()
	if err != nil {
		return SlidePayload{}, err
	}
	captData, err := r.builder.Generate()
	if err != nil {
		return SlidePayload{}, fmt.Errorf("生成滑块失败: %w", err)
	}
	masterB64, err := captData.GetMasterImage().ToBase64()
	if err != nil {
		return SlidePayload{}, fmt.Errorf("编码主图失败: %w", err)
	}
	tileB64, err := captData.GetTileImage().ToBase64()
	if err != nil {
		return SlidePayload{}, fmt.Errorf("编码滑块失败: %w", err)
	}
	block := captData.GetData()
	if block == nil {
		return SlidePayload{}, errors.New("滑块元数据缺失")
	}

	captchaID, err := randomID()
	if err != nil {
		return SlidePayload{}, err
	}

	r.mu.Lock()
	r.purgeExpiredLocked()
	r.challenges[captchaID] = slideChallenge{
		TargetX:   block.X,
		ExpiresAt: time.Now().Add(slideCaptchaChallengeTTL),
	}
	r.mu.Unlock()

	return SlidePayload{
		CaptchaID:    captchaID,
		MasterBase64: masterB64,
		ThumbBase64:  tileB64,
		ThumbWidth:   block.Width,
		ThumbHeight:  block.Height,
		ThumbY:       block.Y,
	}, nil
}

// VerifySlide 校验一次滑块拖动结果并发放登录 token。
func VerifySlide(captchaID string, x int) (string, error) {
	r, err := getRegistry()
	if err != nil {
		return "", err
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	r.purgeExpiredLocked()

	challenge, ok := r.challenges[captchaID]
	if !ok || time.Now().After(challenge.ExpiresAt) {
		delete(r.challenges, captchaID)
		return "", errors.New("验证码已过期，请刷新重试")
	}
	// 一次性消费，无论成功失败都清除
	delete(r.challenges, captchaID)

	diff := x - challenge.TargetX
	if diff < 0 {
		diff = -diff
	}
	if diff > slideCaptchaTolerance {
		return "", errors.New("未对齐缺口，请重新拖动")
	}

	token, err := randomID()
	if err != nil {
		return "", err
	}
	r.tokens[token] = slideToken{ExpiresAt: time.Now().Add(slideCaptchaTokenTTL)}
	return token, nil
}

// ConsumeSlideToken 消费一次性登录 token，返回是否有效。
func ConsumeSlideToken(token string) bool {
	if token == "" {
		return false
	}
	r, err := getRegistry()
	if err != nil {
		return false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.purgeExpiredLocked()
	rec, ok := r.tokens[token]
	if !ok {
		return false
	}
	delete(r.tokens, token)
	return time.Now().Before(rec.ExpiresAt)
}

// purgeExpiredLocked 清理过期挑战与 token，调用方需持锁。
func (r *slideCaptchaRegistry) purgeExpiredLocked() {
	now := time.Now()
	for id, c := range r.challenges {
		if now.After(c.ExpiresAt) {
			delete(r.challenges, id)
		}
	}
	for id, t := range r.tokens {
		if now.After(t.ExpiresAt) {
			delete(r.tokens, id)
		}
	}
}

func randomID() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
