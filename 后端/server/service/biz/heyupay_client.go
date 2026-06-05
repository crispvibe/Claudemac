package biz

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"heyu/server/global"
)

const heyupaySignType = "HMAC-SHA256"

type heyupayClient struct {
	gateway   string
	appKey    string
	appSecret string
	client    *http.Client
}

type heyupayOrderRequest struct {
	ChannelCode   string         `json:"channel_code"`
	TradeType     string         `json:"trade_type"`
	OutTradeNo    string         `json:"out_trade_no"`
	TotalFee      int64          `json:"total_fee"`
	Currency      string         `json:"currency,omitempty"`
	Subject       string         `json:"subject"`
	NotifyURL     string         `json:"notify_url,omitempty"`
	ReturnURL     string         `json:"return_url,omitempty"`
	ExpireSeconds int            `json:"expire_seconds,omitempty"`
	Attach        string         `json:"attach,omitempty"`
	WechatExt     map[string]any `json:"wechat_ext,omitempty"`
}

type heyupayResponse struct {
	Code      int            `json:"code"`
	Msg       string         `json:"msg"`
	Data      map[string]any `json:"data"`
	RequestID string         `json:"request_id"`
}

func newHeyupayClient() (*heyupayClient, error) {
	gateway := strings.TrimRight(strings.TrimSpace(global.AppConfig.Remote.PayGateway), "/")
	if gateway == "" {
		gateway = "https://pay.anna.vin"
	}
	appKey := strings.TrimSpace(global.AppConfig.Remote.PayAppKey)
	appSecret := strings.TrimSpace(global.AppConfig.Remote.PayAppSecret)
	if appKey == "" || appSecret == "" {
		return nil, errors.New("支付还没有配置好，请先在服务器配置支付密钥。")
	}
	return &heyupayClient{
		gateway:   gateway,
		appKey:    appKey,
		appSecret: appSecret,
		client:    &http.Client{Timeout: 12 * time.Second},
	}, nil
}

func (c *heyupayClient) createOrder(ctx context.Context, req heyupayOrderRequest) (heyupayResponse, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return heyupayResponse{}, err
	}
	resp, err := c.postJSON(ctx, "/openapi/v1/pay/orders", body)
	if err != nil {
		return heyupayResponse{}, err
	}
	if resp.Code != 0 {
		if resp.Msg == "" {
			resp.Msg = "支付下单失败，请稍后重试。"
		}
		return resp, errors.New(resp.Msg)
	}
	return resp, nil
}

func (c *heyupayClient) postJSON(ctx context.Context, path string, body []byte) (heyupayResponse, error) {
	ts := fmt.Sprintf("%d", time.Now().Unix())
	nonce, err := randomToken(12)
	if err != nil {
		return heyupayResponse{}, err
	}
	signature := heyupaySignature("POST", path, "", ts, nonce, body, c.appSecret)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.gateway+path, bytes.NewReader(body))
	if err != nil {
		return heyupayResponse{}, err
	}
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
	request.Header.Set("X-Heyupay-AppKey", c.appKey)
	request.Header.Set("X-Heyupay-Timestamp", ts)
	request.Header.Set("X-Heyupay-Nonce", nonce)
	request.Header.Set("X-Heyupay-SignType", heyupaySignType)
	request.Header.Set("X-Heyupay-Signature", signature)

	httpResp, err := c.client.Do(request)
	if err != nil {
		return heyupayResponse{}, err
	}
	defer httpResp.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(httpResp.Body, 1<<20))
	if err != nil {
		return heyupayResponse{}, err
	}
	var parsed heyupayResponse
	if err := json.Unmarshal(payload, &parsed); err != nil {
		return heyupayResponse{}, fmt.Errorf("支付平台返回格式不正确")
	}
	if parsed.RequestID == "" {
		parsed.RequestID = httpResp.Header.Get("X-Heyupay-Request-Id")
	}
	return parsed, nil
}

func heyupaySignature(method, path, query, timestamp, nonce string, body []byte, secret string) string {
	bodyHash := sha256.Sum256(body)
	stringToSign := strings.Join([]string{
		strings.ToUpper(method),
		path,
		query,
		timestamp,
		nonce,
		hex.EncodeToString(bodyHash[:]),
	}, "\n")
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

func heyupayCanonicalQuery(values url.Values) string {
	if len(values) == 0 {
		return ""
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(values))
	for _, key := range keys {
		items := append([]string(nil), values[key]...)
		sort.Strings(items)
		for _, value := range items {
			parts = append(parts, heyupayEscape(key)+"="+heyupayEscape(value))
		}
	}
	return strings.Join(parts, "&")
}

func heyupayEscape(value string) string {
	return strings.ReplaceAll(url.QueryEscape(value), "+", "%20")
}

func verifyHeyupaySignature(method, path, query, timestamp, nonce string, body []byte, secret, signature string) bool {
	if strings.TrimSpace(secret) == "" || strings.TrimSpace(signature) == "" {
		return false
	}
	expected := heyupaySignature(method, path, query, timestamp, nonce, body, secret)
	return subtle.ConstantTimeCompare([]byte(expected), []byte(signature)) == 1
}

func randomBase36(size int) (string, error) {
	const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
	raw := make([]byte, size)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	out := make([]byte, size)
	for i, b := range raw {
		out[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(out), nil
}
