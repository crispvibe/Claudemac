import {
  Copy,
  Eye,
  EyeOff,
  Loader2,
  LockKeyhole,
  Mail,
  Monitor,
  Radio,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  X
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import type { AccountRemoteState, RemoteDevice, RemoteLegalDocument, RemoteLegalDocumentType } from "@shared/account";
import { AppLogo } from "@renderer/src/components/AppLogo";
import { useAccountRemoteStore } from "../../stores/accountStore";
import { LegalDocumentModal } from "./LegalDocumentModal";

type AuthMode = "login" | "register" | "forgot";
type RemoteActionRunner = (label: string, action: () => Promise<unknown>, successMessage?: string) => Promise<boolean>;

const deviceApprovalOptions = [
  { value: "always_ask", label: "每次询问" },
  { value: "allow_anyone", label: "允许任意连接" }
] as const;

const legalDocumentLinks = [
  { type: "user_agreement", label: "用户协议" },
  { type: "privacy_policy", label: "隐私政策" }
] as const satisfies Array<{ type: RemoteLegalDocumentType; label: string }>;

export interface AccountRemoteDialogProps {
  dismissible?: boolean;
  onClose: () => void;
  open: boolean;
}

export function AccountRemoteDialog({ dismissible = true, onClose, open }: AccountRemoteDialogProps) {
  const account = useAccountRemoteStore((state) => state.account);
  const isAuthenticated = account.status === "authenticated";

  useEffect(() => {
    if (!open) {
      return;
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && dismissible) {
        onClose();
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [dismissible, onClose, open]);

  if (!open) {
    return null;
  }

  return (
    <div
      className="account-dialog-backdrop"
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && dismissible) {
          onClose();
        }
      }}
    >
      <section className={`account-dialog ${isAuthenticated ? "wide" : ""}`} role="dialog" aria-modal="true" aria-label="账号与设备">
        <header className="account-dialog-header">
          <div className="account-dialog-brand">
            <div className="account-dialog-logo">
              <AppLogo />
            </div>
            <div>
              <h2>{isAuthenticated ? "账号与设备" : "Acode"}</h2>
              <p>{isAuthenticated ? "管理当前账号、本机设备、设备码和信令连接。" : "登录以继续你的远程开发工作"}</p>
            </div>
          </div>
          {dismissible ? (
            <button className="account-dialog-close" type="button" onClick={onClose} aria-label="关闭账号弹窗">
              <X size={17} />
            </button>
          ) : null}
        </header>

        {isAuthenticated ? <AccountRemoteControlPanel /> : <AccountAuthPanel />}
      </section>
    </div>
  );
}

export function AccountRemoteControlPanel() {
  const account = useAccountRemoteStore((state) => state.account);
  const device = useAccountRemoteStore((state) => state.device);
  const deviceCode = useAccountRemoteStore((state) => state.deviceCode);
  const devices = useAccountRemoteStore((state) => state.devices);
  const connectionStatus = useAccountRemoteStore((state) => state.connectionStatus);
  const lastError = useAccountRemoteStore((state) => state.lastError);
  const hydrateRemoteState = useAccountRemoteStore((state) => state.hydrateRemoteState);
  const setConnectionStatus = useAccountRemoteStore((state) => state.setConnectionStatus);
  const [deviceName, setDeviceName] = useState(device?.deviceName ?? "");
  const [approvalPolicy, setApprovalPolicy] = useState<"always_ask" | "allow_anyone">("always_ask");
  const [remoteEnabled, setRemoteEnabled] = useState(true);
  const [remoteAction, setRemoteAction] = useState<string | null>(null);
  const [message, setMessage] = useState<{ kind: "info" | "success" | "error"; text: string } | null>(null);
  const isAuthenticated = account.status === "authenticated";
  const isConnected = connectionStatus === "connected";
  const accountLabel = account.displayAccount ?? account.userId?.toString() ?? "已登录";

  useEffect(() => {
    setDeviceName(device?.deviceName ?? "");
    const currentRemoteDevice = device?.deviceID ? devices.find((item) => item.id === device.deviceID) : undefined;
    setApprovalPolicy(currentRemoteDevice?.approvalPolicy === "allow_anyone" ? "allow_anyone" : "always_ask");
    setRemoteEnabled(currentRemoteDevice?.remoteEnabled ?? true);
  }, [device?.deviceID, device?.deviceName, devices]);

  const onlineDevices = useMemo(() => devices.filter((item) => item.online), [devices]);

  const runRemoteAction: RemoteActionRunner = async (label, action, successMessage) => {
    setRemoteAction(label);
    setMessage(null);
    try {
      const result = await action();
      if (isAccountRemoteState(result)) {
        hydrateRemoteState(result);
      }
      if (successMessage) {
        setMessage({ kind: "success", text: successMessage });
      }
      return true;
    } catch (error) {
      const text = error instanceof Error ? error.message : `${label}失败`;
      setMessage({ kind: "error", text });
      setConnectionStatus("error", text);
      return false;
    } finally {
      setRemoteAction(null);
    }
  };

  function requireBridge() {
    const bridge = window.acode?.accountRemote;
    if (!bridge) {
      throw new Error("Account API is not available.");
    }
    return bridge;
  }

  async function copyDeviceCode() {
    if (!deviceCode.deviceCode) {
      return;
    }
    await navigator.clipboard.writeText(formatDeviceCode(deviceCode.deviceCode));
    setMessage({ kind: "success", text: "设备码已复制。" });
  }

  return (
    <div className="account-remote-control">
      <div className="account-control-summary">
        <SummaryTile icon={<ShieldCheck size={18} />} label="账号" value={accountLabel} detail={account.userStatus ?? account.status} />
        <SummaryTile icon={<Monitor size={18} />} label="本机设备" value={device?.deviceName ?? "未注册"} detail={device?.deviceID ? `设备 #${device.deviceID}` : "等待注册"} />
        <SummaryTile icon={<Radio size={18} />} label="信令" value={connectionStatusLabel(connectionStatus)} detail={onlineDevices.length > 0 ? `${onlineDevices.length} 个设备在线` : "无在线设备"} />
      </div>

      <div className="account-dialog-grid">
        <section className="account-dialog-section">
          <div className="account-section-header">
            <div>
              <h3>账号状态</h3>
              <p>登录状态、本机凭证和远程设备状态来自 main 进程。</p>
            </div>
            <span className={`status-badge ${isConnected ? "active" : ""}`}>{connectionStatusLabel(connectionStatus)}</span>
          </div>
          <div className="account-key-value"><span>账号</span><b>{accountLabel}</b></div>
          <div className="account-key-value"><span>状态</span><b>{account.status}</b></div>
          <div className="account-key-value"><span>过期时间</span><b>{account.expiresAtISO ?? "无"}</b></div>
          <div className="account-dialog-actions">
            <button type="button" disabled={Boolean(remoteAction)} onClick={() => void runRemoteAction("刷新状态", () => requireBridge().getState())}>
              <RefreshCw size={14} /> 刷新状态
            </button>
            <button type="button" disabled={Boolean(remoteAction)} onClick={() => void runRemoteAction("退出登录", () => requireBridge().logout(), "已退出登录。")}>
              退出登录
            </button>
          </div>
        </section>

        <section className="account-dialog-section">
          <div className="account-section-header">
            <div>
              <h3>本机设备</h3>
              <p>设备名、连接策略、远程开关会同步到账号设备服务。</p>
            </div>
          </div>
          <input className="settings-input" value={deviceName} placeholder="本机设备名" onChange={(event) => setDeviceName(event.currentTarget.value)} />
          <div className="account-device-options">
            <select className="settings-select" value={approvalPolicy} onChange={(event) => setApprovalPolicy(event.currentTarget.value as "always_ask" | "allow_anyone")}>
              {deviceApprovalOptions.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
            </select>
            <label className="account-checkbox">
              <input checked={remoteEnabled} type="checkbox" onChange={(event) => setRemoteEnabled(event.currentTarget.checked)} />
              <span>允许远程连接</span>
            </label>
          </div>
          <div className="account-dialog-actions">
            <button type="button" disabled={Boolean(remoteAction) || !isAuthenticated} onClick={() => void runRemoteAction("注册本机", () => requireBridge().registerDevice(), "本机设备已注册。")}>
              注册本机
            </button>
            <button
              className="settings-primary-button"
              type="button"
              disabled={Boolean(remoteAction) || !isAuthenticated || !device?.deviceID || !deviceName.trim()}
              onClick={() => void runRemoteAction("保存设备", () => requireBridge().updateDevice({
                approvalPolicy,
                deviceName: deviceName.trim(),
                remoteEnabled
              }), "设备设置已保存。")}
            >
              保存
            </button>
          </div>
        </section>

        <section className="account-dialog-section">
          <div className="account-section-header">
            <div>
              <h3>设备码</h3>
              <p>其他账号使用设备码连接，同账号设备可通过设备列表识别。</p>
            </div>
          </div>
          <div className="device-code-box">{deviceCode.deviceCode ? formatDeviceCode(deviceCode.deviceCode) : deviceCodeFallback(deviceCode.hint, device?.hasDeviceCode)}</div>
          <div className="account-dialog-actions">
            <button type="button" disabled={Boolean(remoteAction) || !device?.deviceID} onClick={() => void runRemoteAction("读取设备码", () => requireBridge().refreshDeviceCode())}>
              读取
            </button>
            <button type="button" disabled={!deviceCode.deviceCode} onClick={() => void copyDeviceCode()}>
              <Copy size={14} /> 复制
            </button>
            <button type="button" disabled={Boolean(remoteAction) || !device?.deviceID} onClick={() => void runRemoteAction("重置设备码", () => requireBridge().resetDeviceCode(), "设备码已重置。")}>
              重置
            </button>
          </div>
        </section>

        <section className="account-dialog-section">
          <div className="account-section-header">
            <div>
              <h3>设备连接服务</h3>
              <p>控制账号信令通道，用于接收远程连接请求。</p>
            </div>
          </div>
          <div className="account-key-value"><span>连接状态</span><b>{connectionStatusLabel(connectionStatus)}</b></div>
          <div className="account-key-value"><span>最后错误</span><b>{lastError ?? "无"}</b></div>
          <div className="account-dialog-actions">
            <button type="button" disabled={Boolean(remoteAction) || !isAuthenticated} onClick={() => void runRemoteAction("刷新设备", () => requireBridge().refreshDevices())}>
              <RefreshCw size={14} /> 刷新设备
            </button>
            <button
              className="settings-primary-button"
              type="button"
              disabled={Boolean(remoteAction) || !isAuthenticated}
              onClick={() => void runRemoteAction(isConnected ? "停止信令" : "启动信令", () => (
                isConnected ? requireBridge().stopSignaling() : requireBridge().startSignaling()
              ))}
            >
              {isConnected ? "停止信令" : "启动信令"}
            </button>
          </div>
        </section>
      </div>

      <section className="account-dialog-section account-device-list-panel">
        <div className="account-section-header">
          <div>
            <h3>同账号设备</h3>
            <p>展示账号下已知设备、在线状态、平台和最近在线时间；远程连接入口会在 main 进程链路接入后启用。</p>
          </div>
          <span>{devices.length} 台</span>
        </div>
        {devices.length === 0 ? (
          <p className="account-empty">暂无设备。登录后会自动注册本机，也可以手动刷新设备列表。</p>
        ) : (
          <div className="account-device-list">
            {devices.map((remoteDevice) => (
              <div className="account-device-row" key={remoteDevice.id}>
                <Smartphone size={17} />
                <div>
                  <b>{remoteDevice.deviceName}</b>
                  <span>{remoteDeviceDetail(remoteDevice, device?.deviceID)}</span>
                </div>
                <small className={remoteDeviceConnectionClass(remoteDevice, device?.deviceID)}>{remoteDeviceConnectionLabel(remoteDevice, device?.deviceID)}</small>
              </div>
            ))}
          </div>
        )}
      </section>

      {remoteAction ? <p className="account-action-status"><Loader2 size={14} /> 正在执行：{remoteAction}</p> : null}
      {message ? <p className={`account-message ${message.kind}`}>{message.text}</p> : null}
    </div>
  );
}

function AccountAuthPanel() {
  const hydrateRemoteState = useAccountRemoteStore((state) => state.hydrateRemoteState);
  const setConnectionStatus = useAccountRemoteStore((state) => state.setConnectionStatus);
  const account = useAccountRemoteStore((state) => state.account);
  const [mode, setMode] = useState<AuthMode>("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [verificationCode, setVerificationCode] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [legalDocuments, setLegalDocuments] = useState<Partial<Record<RemoteLegalDocumentType, RemoteLegalDocument>>>({});
  const [selectedLegalDocument, setSelectedLegalDocument] = useState<RemoteLegalDocument | null>(null);
  const [legalLoading, setLegalLoading] = useState(false);
  const [legalError, setLegalError] = useState<string | null>(null);
  const [remoteAction, setRemoteAction] = useState<string | null>(null);
  const [message, setMessage] = useState<{ kind: "info" | "success" | "error"; text: string } | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function loadLegalDocuments() {
      const bridge = window.acode?.accountRemote;
      if (!bridge) {
        setLegalError("协议服务不可用。");
        return;
      }

      setLegalLoading(true);
      setLegalError(null);
      try {
        const documents = await Promise.all(legalDocumentLinks.map((item) => bridge.legalDocument(item.type)));
        if (cancelled) {
          return;
        }
        setLegalDocuments(Object.fromEntries(documents.map((document) => [document.type, document])));
      } catch (error) {
        if (!cancelled) {
          setLegalError(error instanceof Error ? error.message : "协议暂时无法加载。");
        }
      } finally {
        if (!cancelled) {
          setLegalLoading(false);
        }
      }
    }

    void loadLegalDocuments();
    return () => {
      cancelled = true;
    };
  }, []);

  function requireBridge() {
    const bridge = window.acode?.accountRemote;
    if (!bridge) {
      throw new Error("Account API is not available.");
    }
    return bridge;
  }

  const runRemoteAction: RemoteActionRunner = async (label, action, successMessage) => {
    setRemoteAction(label);
    setMessage(null);
    try {
      const result = await action();
      if (isAccountRemoteState(result)) {
        hydrateRemoteState(result);
      }
      if (successMessage) {
        setMessage({ kind: "success", text: successMessage });
      }
      return true;
    } catch (error) {
      const text = error instanceof Error ? error.message : `${label}失败`;
      setMessage({ kind: "error", text });
      setConnectionStatus("error", text);
      return false;
    } finally {
      setRemoteAction(null);
    }
  };

  const canLogin = email.trim() && password && agreed && !remoteAction;
  const canRegister = canLogin && confirmPassword === password && verificationCode.trim();
  const canResetPassword = email.trim() && password && confirmPassword === password && verificationCode.trim() && !remoteAction;
  const canAgree = legalDocumentLinks.every((item) => legalDocuments[item.type]) && !legalLoading;
  const title = mode === "login" ? "登录" : mode === "register" ? "注册账号" : "忘记密码";

  async function requestCode() {
    const label = mode === "register" ? "发送注册验证码" : "发送重置验证码";
    const action = mode === "register"
      ? () => requireBridge().requestRegisterCode(email)
      : () => requireBridge().requestPasswordResetCode(email);
    await runRemoteAction(label, action, "验证码已发送，请检查邮箱。");
  }

  async function submitAuth() {
    if (mode === "login") {
      await runRemoteAction("登录", () => requireBridge().login(email, password));
      return;
    }
    if (mode === "register") {
      await runRemoteAction("注册账号", () => requireBridge().register(email, password, verificationCode));
      return;
    }
    const ok = await runRemoteAction("重置密码", () => requireBridge().resetPassword(email, password, verificationCode), "密码已重置，请使用新密码登录。");
    if (ok) {
      setPassword("");
      setConfirmPassword("");
      setVerificationCode("");
      setMode("login");
    }
  }

  async function openLegalDocument(type: RemoteLegalDocumentType) {
    const cached = legalDocuments[type];
    if (cached) {
      setSelectedLegalDocument(cached);
      return;
    }

    setLegalLoading(true);
    setLegalError(null);
    try {
      const document = await requireBridge().legalDocument(type);
      setLegalDocuments((current) => ({ ...current, [document.type]: document }));
      setSelectedLegalDocument(document);
    } catch (error) {
      setLegalError(error instanceof Error ? error.message : "协议暂时无法加载。");
    } finally {
      setLegalLoading(false);
    }
  }

  return (
    <div className="account-auth-panel">
      <div className="account-auth-title-row">
        <h3>{title}</h3>
      </div>

      {account.status === "expired" ? <p className="account-message error">登录状态已失效，请重新登录。</p> : null}

      <label className="account-field">
        <span>手机号 / 邮箱</span>
        <div className="account-input-shell">
          <Mail size={16} />
          <input autoFocus value={email} placeholder="手机号 / 邮箱" onChange={(event) => setEmail(event.currentTarget.value)} />
        </div>
      </label>
      <label className="account-field">
        <span>{mode === "forgot" ? "新密码" : "密码"}</span>
        <div className="account-input-shell">
          <LockKeyhole size={16} />
          <input type={passwordVisible ? "text" : "password"} value={password} placeholder={mode === "forgot" ? "新密码" : "密码"} onChange={(event) => setPassword(event.currentTarget.value)} />
          <button type="button" onClick={() => setPasswordVisible((value) => !value)} aria-label={passwordVisible ? "隐藏密码" : "显示密码"}>
            {passwordVisible ? <EyeOff size={15} /> : <Eye size={15} />}
          </button>
        </div>
      </label>
      {mode !== "login" ? (
        <>
          <label className="account-field">
            <span>确认密码</span>
            <div className="account-input-shell">
              <LockKeyhole size={16} />
              <input type={passwordVisible ? "text" : "password"} value={confirmPassword} placeholder="确认密码" onChange={(event) => setConfirmPassword(event.currentTarget.value)} />
            </div>
          </label>
          <label className="account-field">
            <span>验证码</span>
            <div className="account-code-row">
              <div className="account-input-shell">
                <Mail size={16} />
                <input value={verificationCode} placeholder="验证码" onChange={(event) => setVerificationCode(event.currentTarget.value)} />
              </div>
              <button type="button" disabled={!email.trim() || Boolean(remoteAction)} onClick={() => void requestCode()}>
                获取验证码
              </button>
            </div>
          </label>
        </>
      ) : null}

      {mode !== "forgot" ? (
        <label className="account-agreement">
          <input checked={agreed} disabled={!canAgree} type="checkbox" onChange={(event) => setAgreed(event.currentTarget.checked)} />
          <span>
            我已阅读并同意
            {legalDocumentLinks.map((item) => (
              <button key={item.type} type="button" disabled={legalLoading} onClick={() => void openLegalDocument(item.type)}>
                《{item.label}》
              </button>
            ))}
          </span>
        </label>
      ) : null}

      {legalError ? <p className="account-message error">{legalError}</p> : null}
      {password && confirmPassword && password !== confirmPassword ? <p className="account-message error">两次密码不一致。</p> : null}
      {message ? <p className={`account-message ${message.kind}`}>{message.text}</p> : null}
      {remoteAction ? <p className="account-action-status"><Loader2 size={14} /> 正在执行：{remoteAction}</p> : null}

      <button
        className="settings-primary-button account-submit-button"
        type="button"
        disabled={mode === "login" ? !canLogin : mode === "register" ? !canRegister : !canResetPassword}
        onClick={() => void submitAuth()}
      >
        {mode === "login" ? "登录" : mode === "register" ? "创建账号" : "重置密码"}
      </button>

      {mode === "login" ? (
        <div className="account-auth-footer">
          <button type="button" onClick={() => setMode("forgot")}>忘记密码</button>
          <button type="button" onClick={() => setMode("register")}>注册账号</button>
        </div>
      ) : (
        <div className="account-auth-footer single">
          <button type="button" onClick={() => setMode("login")}>返回登录</button>
        </div>
      )}

      {selectedLegalDocument ? <LegalDocumentModal document={selectedLegalDocument} onClose={() => setSelectedLegalDocument(null)} /> : null}
    </div>
  );
}

function SummaryTile({ detail, icon, label, value }: { detail: string; icon: ReactNode; label: string; value: string }) {
  return (
    <div className="account-summary-tile">
      {icon}
      <span>{label}</span>
      <b>{value}</b>
      <small>{detail}</small>
    </div>
  );
}

function isAccountRemoteState(value: unknown): value is AccountRemoteState {
  return Boolean(value && typeof value === "object" && "account" in value && "signaling" in value);
}

function remoteDeviceDetail(device: RemoteDevice, localDeviceID?: number | null): string {
  return [
    device.platform ?? "unknown",
    device.online ? "在线" : "离线",
    device.remoteEnabled ? "允许远程" : "已关闭远程",
    localDeviceID === device.id ? "本机设备" : "连接未接入",
    device.lastSeenAt ?? "未记录在线时间"
  ].join(" · ");
}

function remoteDeviceConnectionLabel(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "本机";
  }
  if (!device.remoteEnabled) {
    return "远程关闭";
  }
  if (!device.online) {
    return "离线";
  }
  return "连接未接入";
}

function remoteDeviceConnectionClass(device: RemoteDevice, localDeviceID?: number | null): string {
  if (localDeviceID === device.id) {
    return "local";
  }
  if (device.online && device.remoteEnabled) {
    return "unavailable";
  }
  return "";
}

function connectionStatusLabel(status: string): string {
  switch (status) {
    case "connecting":
      return "连接中";
    case "connected":
      return "已连接";
    case "reconnecting":
      return "重连中";
    case "closed":
      return "已关闭";
    case "error":
      return "异常";
    case "idle":
    default:
      return "空闲";
  }
}

function formatDeviceCode(value: string): string {
  return value.replace(/\s+/g, "").replace(/(.{4})/g, "$1-").replace(/-$/, "");
}

function deviceCodeFallback(hint: string | null, hasDeviceCode?: boolean): string {
  if (hint) {
    return `仅保存尾号 ****-${hint}`;
  }
  return hasDeviceCode ? "已保存，请读取或重置后显示完整设备码" : "未生成";
}
