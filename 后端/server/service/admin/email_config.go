package admin

import (
	"crypto/tls"
	"errors"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"sync"
	"time"

	"heyu/server/global"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
)

var emailConfigWriteLock sync.Mutex

type EmailConfigService struct{}

func (s *EmailConfigService) GetEmailConfig() systemRes.EmailConfigResponse {
	cfg := global.AppConfig.Email
	return buildEmailConfigResponse(cfg.Host, cfg.Port, cfg.From, cfg.Nickname, cfg.IsSSL, cfg.IsLoginAuth, strings.TrimSpace(cfg.Secret) != "")
}

func (s *EmailConfigService) UpdateEmailConfig(input systemReq.EmailConfigUpdate) (systemRes.EmailConfigResponse, error) {
	host := strings.TrimSpace(input.Host)
	from := strings.TrimSpace(input.From)
	if host == "" {
		return systemRes.EmailConfigResponse{}, errors.New("请填写邮件服务器地址")
	}
	if input.Port <= 0 || input.Port > 65535 {
		return systemRes.EmailConfigResponse{}, errors.New("端口号需在 1-65535 之间")
	}
	if _, err := mail.ParseAddress(from); err != nil {
		return systemRes.EmailConfigResponse{}, errors.New("发件人邮箱地址格式不正确")
	}

	emailConfigWriteLock.Lock()
	defer emailConfigWriteLock.Unlock()

	// 授权码未改动时沿用旧值，避免覆盖为空。
	secret := strings.TrimSpace(global.AppConfig.Email.Secret)
	if input.SecretChanged {
		secret = strings.TrimSpace(input.Secret)
	}
	if secret == "" {
		return systemRes.EmailConfigResponse{}, errors.New("请填写邮箱 SMTP 授权码")
	}
	nickname := strings.TrimSpace(input.Nickname)

	global.AppVP.Set("email.host", host)
	global.AppVP.Set("email.port", input.Port)
	global.AppVP.Set("email.from", from)
	global.AppVP.Set("email.nickname", nickname)
	global.AppVP.Set("email.secret", secret)
	global.AppVP.Set("email.is-ssl", input.IsSSL)
	global.AppVP.Set("email.is-loginauth", input.IsLoginAuth)
	if err := global.AppVP.WriteConfig(); err != nil {
		return systemRes.EmailConfigResponse{}, fmt.Errorf("保存邮件配置失败: %w", err)
	}

	global.AppConfig.Email.Host = host
	global.AppConfig.Email.Port = input.Port
	global.AppConfig.Email.From = from
	global.AppConfig.Email.Nickname = nickname
	global.AppConfig.Email.Secret = secret
	global.AppConfig.Email.IsSSL = input.IsSSL
	global.AppConfig.Email.IsLoginAuth = input.IsLoginAuth

	return buildEmailConfigResponse(host, input.Port, from, nickname, input.IsSSL, input.IsLoginAuth, true), nil
}

// SendTestEmail 使用当前已保存的配置发送一封测试邮件，便于验证 QQ/163 授权码是否正确。
func (s *EmailConfigService) SendTestEmail(input systemReq.EmailConfigTest) error {
	to := strings.TrimSpace(input.To)
	if to == "" {
		to = strings.TrimSpace(global.AppConfig.Email.From)
	}
	if _, err := mail.ParseAddress(to); err != nil {
		return errors.New("收件人邮箱地址格式不正确")
	}
	subject := "AnnaCode 邮件配置测试"
	body := fmt.Sprintf("这是一封来自 AnnaCode 后台的测试邮件，发送时间：%s。\n\n如果你收到了它，说明邮件发送配置已生效。", time.Now().Format("2006-01-02 15:04:05"))
	return sendAdminEmail(to, subject, body)
}

func buildEmailConfigResponse(host string, port int, from, nickname string, isSSL, isLoginAuth, secretSet bool) systemRes.EmailConfigResponse {
	return systemRes.EmailConfigResponse{
		Host:        host,
		Port:        port,
		From:        from,
		Nickname:    nickname,
		IsSSL:       isSSL,
		IsLoginAuth: isLoginAuth,
		SecretSet:   secretSet,
		Configured:  strings.TrimSpace(host) != "" && port > 0 && strings.TrimSpace(from) != "" && secretSet,
	}
}

func sendAdminEmail(to, subject, body string) error {
	cfg := global.AppConfig.Email
	host := strings.TrimSpace(cfg.Host)
	from := strings.TrimSpace(cfg.From)
	secret := strings.TrimSpace(cfg.Secret)
	if host == "" || from == "" || secret == "" || cfg.Port <= 0 {
		return errors.New("邮件服务未配置，请先填写并保存邮件发送配置。")
	}

	addr := net.JoinHostPort(host, strconv.Itoa(cfg.Port))
	fromAddress := mail.Address{Name: strings.TrimSpace(cfg.Nickname), Address: from}
	headers := []string{
		"From: " + fromAddress.String(),
		"To: " + to,
		"Subject: " + mime.QEncoding.Encode("UTF-8", subject),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: 8bit",
	}
	message := []byte(strings.Join(headers, "\r\n") + "\r\n\r\n" + body)

	var auth smtp.Auth
	if cfg.IsLoginAuth {
		auth = newAdminLoginAuth(from, secret)
	} else {
		auth = smtp.PlainAuth("", from, secret, host)
	}

	if cfg.IsSSL {
		conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		if err != nil {
			return fmt.Errorf("连接邮件服务器失败: %w", err)
		}
		defer conn.Close()
		client, err := smtp.NewClient(conn, host)
		if err != nil {
			return fmt.Errorf("初始化邮件客户端失败: %w", err)
		}
		defer client.Close()
		return deliverAdminEmail(client, auth, from, to, message)
	}

	client, err := smtp.Dial(addr)
	if err != nil {
		return fmt.Errorf("连接邮件服务器失败: %w", err)
	}
	defer client.Close()
	if ok, _ := client.Extension("STARTTLS"); ok {
		if err := client.StartTLS(&tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}); err != nil {
			return fmt.Errorf("启用邮件加密失败: %w", err)
		}
	}
	return deliverAdminEmail(client, auth, from, to, message)
}

func deliverAdminEmail(client *smtp.Client, auth smtp.Auth, from, to string, message []byte) error {
	if auth != nil {
		if ok, _ := client.Extension("AUTH"); ok {
			if err := client.Auth(auth); err != nil {
				return fmt.Errorf("邮件认证失败（请检查授权码）: %w", err)
			}
		}
	}
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("设置发件人失败: %w", err)
	}
	if err := client.Rcpt(to); err != nil {
		return fmt.Errorf("设置收件人失败: %w", err)
	}
	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("写入邮件失败: %w", err)
	}
	if _, err := writer.Write(message); err != nil {
		_ = writer.Close()
		return fmt.Errorf("发送邮件失败: %w", err)
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("完成邮件发送失败: %w", err)
	}
	return client.Quit()
}

type adminLoginAuth struct {
	username string
	password string
}

func newAdminLoginAuth(username, password string) smtp.Auth {
	return &adminLoginAuth{username: username, password: password}
}

func (a *adminLoginAuth) Start(*smtp.ServerInfo) (string, []byte, error) {
	return "LOGIN", []byte(a.username), nil
}

func (a *adminLoginAuth) Next(_ []byte, more bool) ([]byte, error) {
	if more {
		return []byte(a.password), nil
	}
	return nil, nil
}
