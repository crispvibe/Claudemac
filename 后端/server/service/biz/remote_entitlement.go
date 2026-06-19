package biz

import (
	"errors"
	"time"

	"gorm.io/gorm"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizRes "heyu/server/model/biz/response"
)

const (
	remoteSubscriptionFree     = "free"
	remoteSubscriptionTrial    = "trial"
	remoteSubscriptionActive   = "active"
	remoteSubscriptionExpired  = "expired"
	remoteSubscriptionCanceled = "canceled"

	remoteUsageModeCrossNetwork = "cross_network"
	remoteUsageStatusReserved   = "reserved"
)

// grantRegistrationTrial 在用户注册成功后写入一条 1 天有效期的试用订阅，
// 让“免费注册即可免费使用一天”生效。须在注册事务中调用。
func grantRegistrationTrial(tx *gorm.DB, userID uint) error {
	now := time.Now()
	expires := now.Add(remoteRegisterTrialDuration)
	sub := modelBiz.RemoteSubscription{
		UserID:    userID,
		PlanCode:  remoteSubscriptionTrial,
		Status:    remoteSubscriptionTrial,
		StartedAt: &now,
		ExpiresAt: &expires,
		Provider:  "register_trial",
	}
	return tx.Create(&sub).Error
}

type RemoteEntitlementService struct{}

type RemoteEntitlementSnapshot struct {
	PlanCode            string
	Status              string
	ExpiresAt           *time.Time
	TrialSecondsAllowed int
	TrialSecondsUsed    int
	TrialSecondsLeft    int
	RenewURL            string
}

func (s *RemoteEntitlementService) Snapshot(userID uint) (RemoteEntitlementSnapshot, error) {
	allowed := configuredTrialSecondsPerDay()
	snapshot := RemoteEntitlementSnapshot{
		PlanCode:            remoteSubscriptionFree,
		Status:              remoteSubscriptionFree,
		TrialSecondsAllowed: allowed,
		TrialSecondsLeft:    allowed,
		RenewURL:            "",
	}
	var sub modelBiz.RemoteSubscription
	err := global.AppDB.Where("user_id = ?", userID).Order("id desc").First(&sub).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return s.withTrialUsage(userID, snapshot)
	}
	if err != nil {
		return RemoteEntitlementSnapshot{}, err
	}
	snapshot.PlanCode = sub.PlanCode
	if snapshot.PlanCode == "" {
		snapshot.PlanCode = remoteSubscriptionFree
	}
	snapshot.Status = effectiveSubscriptionStatus(sub, time.Now())
	snapshot.ExpiresAt = sub.ExpiresAt
	return s.withTrialUsage(userID, snapshot)
}

func (s *RemoteEntitlementService) SubscriptionResponse(userID uint) (bizRes.RemoteSubscriptionResponse, error) {
	snapshot, err := s.Snapshot(userID)
	if err != nil {
		return bizRes.RemoteSubscriptionResponse{}, err
	}
	return bizRes.RemoteSubscriptionResponse{
		PlanCode:            snapshot.PlanCode,
		Status:              snapshot.Status,
		ExpiresAt:           snapshot.ExpiresAt,
		TrialSecondsAllowed: snapshot.TrialSecondsAllowed,
		TrialSecondsUsed:    snapshot.TrialSecondsUsed,
		TrialSecondsLeft:    snapshot.TrialSecondsLeft,
		RenewURL:            snapshot.RenewURL,
	}, nil
}

func (s *RemoteEntitlementService) withTrialUsage(userID uint, snapshot RemoteEntitlementSnapshot) (RemoteEntitlementSnapshot, error) {
	allowed := configuredTrialSecondsPerDay()
	snapshot.TrialSecondsAllowed = allowed
	var used int64
	today := time.Now().Format("2006-01-02")
	if err := global.AppDB.Model(&modelBiz.RemoteEntitlementUsage{}).
		Where("user_id = ? AND usage_date = ? AND mode = ?", userID, today, remoteUsageModeCrossNetwork).
		Select("COALESCE(SUM(billed_seconds), 0)").Scan(&used).Error; err != nil {
		return RemoteEntitlementSnapshot{}, err
	}
	snapshot.TrialSecondsUsed = int(used)
	left := allowed - snapshot.TrialSecondsUsed
	if left < 0 {
		left = 0
	}
	snapshot.TrialSecondsLeft = left
	return snapshot, nil
}

func effectiveSubscriptionStatus(sub modelBiz.RemoteSubscription, now time.Time) string {
	if sub.ExpiresAt != nil && !sub.ExpiresAt.After(now) {
		return remoteSubscriptionExpired
	}
	switch sub.Status {
	case remoteSubscriptionTrial, remoteSubscriptionActive, remoteSubscriptionExpired, remoteSubscriptionCanceled, remoteSubscriptionFree:
		return sub.Status
	default:
		return remoteSubscriptionFree
	}
}

func configuredTrialSecondsPerDay() int {
	minutes := global.AppConfig.Remote.TrialMinutesPerDay
	if minutes <= 0 {
		return 0
	}
	return minutes * 60
}
