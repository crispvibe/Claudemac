package request

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"
)

var defaultHTTPClient = &http.Client{
	Timeout: 10 * time.Second,
	// 禁用默认自动重定向，避免 30x 跳内网导致 SSRF 绕过
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

// ErrUnsafeHTTPTarget 表示目标 URL 指向内网 / 非 http(s) / 解析失败等风险地址
var ErrUnsafeHTTPTarget = errors.New("unsafe http target")

func isPublicIP(addr netip.Addr) bool {
	return addr.IsValid() &&
		!addr.IsLoopback() &&
		!addr.IsPrivate() &&
		!addr.IsMulticast() &&
		!addr.IsLinkLocalUnicast() &&
		!addr.IsLinkLocalMulticast() &&
		!addr.IsUnspecified()
}

// guardAgainstSSRF 校验 URL 仅允许 http/https + 公网地址
func guardAgainstSSRF(u *url.URL) error {
	scheme := strings.ToLower(u.Scheme)
	if scheme != "http" && scheme != "https" {
		return ErrUnsafeHTTPTarget
	}
	hostname := strings.TrimSpace(u.Hostname())
	if hostname == "" {
		return ErrUnsafeHTTPTarget
	}
	if addr, err := netip.ParseAddr(hostname); err == nil {
		if !isPublicIP(addr) {
			return ErrUnsafeHTTPTarget
		}
		return nil
	}
	ips, err := net.LookupIP(hostname)
	if err != nil || len(ips) == 0 {
		return ErrUnsafeHTTPTarget
	}
	for _, ip := range ips {
		addr, ok := netip.AddrFromSlice(ip)
		if !ok || !isPublicIP(addr) {
			return ErrUnsafeHTTPTarget
		}
	}
	return nil
}

func HttpRequest(
	urlStr string,
	method string,
	headers map[string]string,
	params map[string]string,
	data any) (*http.Response, error) {
	// 创建URL
	u, err := url.Parse(urlStr)
	if err != nil {
		return nil, err
	}
	if err := guardAgainstSSRF(u); err != nil {
		return nil, err
	}

	// 添加查询参数
	query := u.Query()
	for k, v := range params {
		query.Set(k, v)
	}
	u.RawQuery = query.Encode()

	// 将数据编码为JSON
	buf := new(bytes.Buffer)
	if data != nil {
		b, err := json.Marshal(data)
		if err != nil {
			return nil, err
		}
		buf = bytes.NewBuffer(b)
	}

	// 创建请求
	req, err := http.NewRequest(method, u.String(), buf)

	if err != nil {
		return nil, err
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	if data != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	// 发送请求
	resp, err := defaultHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}

	// 返回响应，让调用者处理
	return resp, nil
}
