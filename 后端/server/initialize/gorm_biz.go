package initialize

import (
	"heyu/server/global"
	"heyu/server/model/biz"
)

func bizModel() error {
	return global.AppDB.AutoMigrate(
		biz.RemoteUser{},
		biz.RemoteUserToken{},
		biz.RemoteAuthCode{},
		biz.RemoteDevice{},
		biz.RemoteDeviceCodeAttempt{},
		biz.RemoteDeviceGrant{},
		biz.RemoteConnectionAttempt{},
		biz.RemoteLegalDocument{},
		biz.RemoteLegalConsent{},
		biz.RemoteAppFooterConfig{},
		biz.RemoteAppUpdate{},
		biz.RemoteSubscription{},
		biz.RemoteSubscriptionPlan{},
		biz.RemoteSubscriptionOrder{},
		biz.RemotePaymentNotifyEvent{},
		biz.RemoteAccountDeletionRecord{},
		biz.RemoteEntitlementUsage{},
		biz.RemoteAuditLog{},
	)
}
