package biz

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"

	"gorm.io/gorm"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizReq "heyu/server/model/biz/request"
	bizRes "heyu/server/model/biz/response"
	"heyu/server/model/shared"
)

const (
	remotePlanStatusActive     = "active"
	remotePlanStatusDisabled   = "disabled"
	remoteOrderStatusPending   = "pending"
	remoteOrderStatusPaid      = "paid"
	remoteOrderStatusClosed    = "closed"
	remoteOrderStatusFailed    = "failed"
	remotePaymentProvider      = "heyupay"
	remotePaymentSucceededKind = "payment.succeeded"
	remotePaymentFailedKind    = "payment.failed"
)

func (s *RemoteService) ListSubscriptionPlans() ([]bizRes.RemoteSubscriptionPlanResponse, error) {
	var plans []modelBiz.RemoteSubscriptionPlan
	if err := global.AppDB.Where("status = ?", remotePlanStatusActive).Order("sort asc, price_fen asc, id asc").Find(&plans).Error; err != nil {
		return nil, err
	}
	responses := make([]bizRes.RemoteSubscriptionPlanResponse, 0, len(plans))
	for _, plan := range plans {
		responses = append(responses, bizRes.RemoteSubscriptionPlanResponse{
			Code:           plan.Code,
			Name:           plan.Name,
			Description:    plan.Description,
			DurationMonths: plan.DurationMonths,
			PriceFen:       plan.PriceFen,
			Currency:       plan.Currency,
		})
	}
	return responses, nil
}

func (s *RemoteService) CreateSubscriptionOrder(ctx context.Context, userID uint, req bizReq.RemoteSubscriptionOrderCreateRequest) (bizRes.RemoteSubscriptionOrderResponse, error) {
	planCode := strings.TrimSpace(req.PlanCode)
	if planCode == "" {
		return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("请选择要购买的套餐。")
	}
	var plan modelBiz.RemoteSubscriptionPlan
	if err := global.AppDB.Where("code = ? AND status = ?", planCode, remotePlanStatusActive).First(&plan).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("这个套餐暂时不能购买，请刷新后再试。")
		}
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	if plan.DurationMonths != 6 && plan.DurationMonths != 12 {
		return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("套餐时长配置不正确，请联系管理员。")
	}
	if plan.PriceFen <= 0 {
		return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("套餐价格还没有设置，请联系管理员。")
	}
	outTradeNo, err := newRemoteOutTradeNo()
	if err != nil {
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	channelCode := strings.TrimSpace(req.ChannelCode)
	if channelCode == "" {
		channelCode = strings.TrimSpace(global.AppConfig.Remote.PayChannelCode)
	}
	if channelCode == "" {
		channelCode = "wechat"
	}
	tradeType := strings.TrimSpace(req.TradeType)
	if tradeType == "" {
		tradeType = strings.TrimSpace(global.AppConfig.Remote.PayTradeType)
	}
	if tradeType == "" {
		tradeType = "H5"
	}
	returnURL := strings.TrimSpace(req.ReturnURL)
	if returnURL == "" {
		returnURL = strings.TrimSpace(global.AppConfig.Remote.PayReturnURL)
	}
	notifyURL := strings.TrimSpace(global.AppConfig.Remote.PayNotifyURL)
	if notifyURL == "" {
		return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("支付回调地址还没有配置，请联系管理员。")
	}

	order := modelBiz.RemoteSubscriptionOrder{
		UserID:         userID,
		PlanID:         plan.ID,
		PlanCode:       plan.Code,
		PlanName:       plan.Name,
		DurationMonths: plan.DurationMonths,
		AmountFen:      plan.PriceFen,
		Currency:       normalizedCurrency(plan.Currency),
		Status:         remoteOrderStatusPending,
		OutTradeNo:     outTradeNo,
		ChannelCode:    channelCode,
		TradeType:      tradeType,
	}
	if err := global.AppDB.Create(&order).Error; err != nil {
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}

	client, err := newHeyupayClient()
	if err != nil {
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	payReq := heyupayOrderRequest{
		ChannelCode:   channelCode,
		TradeType:     tradeType,
		OutTradeNo:    outTradeNo,
		TotalFee:      plan.PriceFen,
		Currency:      order.Currency,
		Subject:       plan.Name,
		NotifyURL:     notifyURL,
		ReturnURL:     returnURL,
		ExpireSeconds: 15 * 60,
		Attach:        fmt.Sprintf("remote_user_id=%d;plan=%s", userID, plan.Code),
	}
	payResp, err := client.createOrder(ctx, payReq)
	if err != nil {
		_ = global.AppDB.Model(&order).Updates(map[string]any{"status": remoteOrderStatusFailed, "updated_at": time.Now(), "raw_response": shared.JSONMap{"code": payResp.Code, "msg": payResp.Msg, "request_id": payResp.RequestID}}).Error
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	updates := map[string]any{
		"pay_order_no":  stringFromPayData(payResp.Data, "pay_order_no"),
		"invoke_params": jsonMapFromPayData(payResp.Data, "invoke_params"),
		"pay_url":       firstPayURL(payResp.Data),
		"raw_response":  shared.JSONMap{"code": payResp.Code, "msg": payResp.Msg, "request_id": payResp.RequestID, "data": payResp.Data},
		"updated_at":    time.Now(),
	}
	if err := global.AppDB.Model(&order).Updates(updates).Error; err != nil {
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	order.PayOrderNo = stringFromPayData(payResp.Data, "pay_order_no")
	order.InvokeParams = jsonMapFromPayData(payResp.Data, "invoke_params")
	order.PayURL = firstPayURL(payResp.Data)
	return subscriptionOrderResponse(order), nil
}

func (s *RemoteService) GetSubscriptionOrder(userID uint, outTradeNo string) (bizRes.RemoteSubscriptionOrderResponse, error) {
	var order modelBiz.RemoteSubscriptionOrder
	if err := global.AppDB.Where("user_id = ? AND out_trade_no = ?", userID, strings.TrimSpace(outTradeNo)).First(&order).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return bizRes.RemoteSubscriptionOrderResponse{}, errors.New("订单不存在，请刷新后重试。")
		}
		return bizRes.RemoteSubscriptionOrderResponse{}, err
	}
	return subscriptionOrderResponse(order), nil
}

func (s *RemoteService) HandlePaymentNotify(path string, query url.Values, headers map[string]string, body []byte) error {
	secret := strings.TrimSpace(global.AppConfig.Remote.PayAppSecret)
	if !verifyHeyupaySignature("POST", path, heyupayCanonicalQuery(query), headers["timestamp"], headers["nonce"], body, secret, headers["signature"]) {
		return errors.New("支付通知校验失败。")
	}
	eventID := strings.TrimSpace(headers["event_id"])
	eventKind := strings.TrimSpace(headers["event_kind"])
	if eventID == "" || eventKind == "" {
		return errors.New("支付通知缺少事件编号。")
	}
	var existing modelBiz.RemotePaymentNotifyEvent
	if err := global.AppDB.Where("event_id = ?", eventID).First(&existing).Error; err == nil {
		return nil
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return err
	}
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return errors.New("支付通知内容格式不正确。")
	}
	eventData := heyupayEventData(payload)
	outTradeNo := stringFromAny(eventData["out_trade_no"])
	payOrderNo := stringFromAny(eventData["pay_order_no"])
	if outTradeNo == "" {
		outTradeNo = stringFromAny(eventData["outTradeNo"])
	}
	now := time.Now()
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		event := modelBiz.RemotePaymentNotifyEvent{
			EventID:     eventID,
			EventKind:   eventKind,
			OutTradeNo:  outTradeNo,
			PayOrderNo:  payOrderNo,
			Status:      "processed",
			Payload:     shared.JSONMap(payload),
			ProcessedAt: &now,
		}
		if err := tx.Create(&event).Error; err != nil {
			return err
		}
		switch eventKind {
		case remotePaymentSucceededKind:
			return s.markSubscriptionOrderPaid(tx, outTradeNo, payOrderNo, now)
		case remotePaymentFailedKind:
			return tx.Model(&modelBiz.RemoteSubscriptionOrder{}).Where("out_trade_no = ? AND status = ?", outTradeNo, remoteOrderStatusPending).Updates(map[string]any{"status": remoteOrderStatusFailed, "updated_at": now}).Error
		default:
			return tx.Model(&event).Updates(map[string]any{"status": "ignored", "updated_at": now}).Error
		}
	})
}

func (s *RemoteService) markSubscriptionOrderPaid(tx *gorm.DB, outTradeNo, payOrderNo string, now time.Time) error {
	if outTradeNo == "" {
		return errors.New("支付通知缺少订单号。")
	}
	var order modelBiz.RemoteSubscriptionOrder
	if err := tx.Where("out_trade_no = ?", outTradeNo).First(&order).Error; err != nil {
		return err
	}
	if order.Status == remoteOrderStatusPaid {
		return nil
	}
	startedAt := now
	expiresAt := subscriptionExpiryBase(tx, order.UserID, now).AddDate(0, order.DurationMonths, 0)
	subscription := modelBiz.RemoteSubscription{
		UserID:          order.UserID,
		PlanCode:        order.PlanCode,
		Status:          remoteSubscriptionActive,
		StartedAt:       &startedAt,
		ExpiresAt:       &expiresAt,
		Provider:        remotePaymentProvider,
		ProviderOrderID: firstNonEmpty(payOrderNo, order.PayOrderNo, order.OutTradeNo),
	}
	if err := tx.Create(&subscription).Error; err != nil {
		return err
	}
	return tx.Model(&order).Updates(map[string]any{
		"status":          remoteOrderStatusPaid,
		"pay_order_no":    firstNonEmpty(payOrderNo, order.PayOrderNo),
		"paid_at":         now,
		"subscription_id": subscription.ID,
		"updated_at":      now,
	}).Error
}

func newRemoteOutTradeNo() (string, error) {
	suffix, err := randomBase36(12)
	if err != nil {
		return "", err
	}
	return "RS" + time.Now().Format("20060102150405") + suffix, nil
}

func normalizedCurrency(value string) string {
	value = strings.TrimSpace(strings.ToUpper(value))
	if value == "" {
		return "CNY"
	}
	return value
}

func subscriptionOrderResponse(order modelBiz.RemoteSubscriptionOrder) bizRes.RemoteSubscriptionOrderResponse {
	invokeParams := map[string]any(nil)
	if order.InvokeParams != nil {
		invokeParams = map[string]any(order.InvokeParams)
	}
	return bizRes.RemoteSubscriptionOrderResponse{
		ID:           order.ID,
		OutTradeNo:   order.OutTradeNo,
		PayOrderNo:   order.PayOrderNo,
		Status:       order.Status,
		AmountFen:    order.AmountFen,
		Currency:     order.Currency,
		PlanCode:     order.PlanCode,
		PlanName:     order.PlanName,
		InvokeParams: invokeParams,
		PayURL:       order.PayURL,
	}
}

func stringFromPayData(data map[string]any, key string) string {
	if data == nil {
		return ""
	}
	return stringFromAny(data[key])
}

func jsonMapFromPayData(data map[string]any, key string) shared.JSONMap {
	value, ok := data[key]
	if !ok || value == nil {
		return nil
	}
	if item, ok := value.(map[string]any); ok {
		return shared.JSONMap(item)
	}
	raw, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil
	}
	return shared.JSONMap(parsed)
}

func firstPayURL(data map[string]any) string {
	for _, key := range []string{"h5_url", "form_url", "code_url", "qr_code"} {
		if value := stringFromPayData(data, key); value != "" {
			return value
		}
	}
	return ""
}

func heyupayEventData(payload map[string]any) map[string]any {
	if data, ok := payload["data"].(map[string]any); ok {
		return data
	}
	return payload
}

func subscriptionExpiryBase(tx *gorm.DB, userID uint, now time.Time) time.Time {
	var current modelBiz.RemoteSubscription
	err := tx.Where("user_id = ? AND status = ? AND expires_at > ?", userID, remoteSubscriptionActive, now).
		Order("expires_at desc, id desc").
		First(&current).Error
	if err == nil && current.ExpiresAt != nil && current.ExpiresAt.After(now) {
		return *current.ExpiresAt
	}
	return now
}

func stringFromAny(value any) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	case fmt.Stringer:
		return strings.TrimSpace(v.String())
	default:
		return ""
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
