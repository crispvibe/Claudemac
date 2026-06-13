import {
  Eye,
  EyeOff,
  Loader2,
  LockKeyhole,
  Mail,
  X
} from "lucide-react";
import { useEffect, useState } from "react";
import type { AccountRemoteState, RemoteLegalDocument, RemoteLegalDocumentType } from "@shared/account";
import { AppLogo } from "@renderer/src/components/AppLogo";
import { useAccountRemoteStore } from "../../stores/accountStore";
import { AccountStatusCard } from "./AccountStatusCard";
import { formatConnectResult } from "./accountRemoteShared";
import { LegalDocumentModal } from "./LegalDocumentModal";
import { RemoteDeviceList } from "./RemoteDeviceList";

type AuthMode = "login" | "register" | "forgot";
type RemoteActionRunner = (label: string, action: () => Promise<unknown>, successMessage?: string) => Promise<boolean>;

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

export interface AccountRemoteControlPanelProps {
  embedded?: boolean;
}

export function AccountRemoteControlPanel({ embedded = false }: AccountRemoteControlPanelProps) {
  const account = useAccountRemoteStore((state) => state.account);
  const device = useAccountRemoteStore((state) => state.device);
  const devices = useAccountRemoteStore((state) => state.devices);
  const connectionStatus = useAccountRemoteStore((state) => state.connectionStatus);
  const activeConnection = useAccountRemoteStore((state) => state.activeConnection);
  const hydrateRemoteState = useAccountRemoteStore((state) => state.hydrateRemoteState);
  const setConnectionStatus = useAccountRemoteStore((state) => state.setConnectionStatus);
  const setActiveConnection = useAccountRemoteStore((state) => state.setActiveConnection);
  const [remoteAction, setRemoteAction] = useState<string | null>(null);
  const [connectingDeviceId, setConnectingDeviceId] = useState<number | null>(null);
  const [message, setMessage] = useState<{ kind: "info" | "success" | "error"; text: string } | null>(null);
  const isAuthenticated = account.status === "authenticated";
  const isConnected = connectionStatus === "connected";

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

  async function connectRemoteDevice(deviceId: number): Promise<void> {
    setConnectingDeviceId(deviceId);
    setMessage(null);
    try {
      const result = await requireBridge().connectDevice(deviceId);
      setActiveConnection(result);
      setMessage({ kind: "success", text: formatConnectResult(result) });
    } catch (error) {
      const text = error instanceof Error ? error.message : "连接失败";
      setMessage({ kind: "error", text });
      setConnectionStatus("error", text);
    } finally {
      setConnectingDeviceId(null);
    }
  }

  if (!isAuthenticated) {
    return <p className="account-empty">登录后可管理本机设备、设备码和远程连接。</p>;
  }

  return (
    <div className={`account-remote-control ${embedded ? "embedded" : ""}`}>
      <AccountStatusCard
        activeConnection={activeConnection}
        embedded={embedded}
        message={message}
        remoteAction={remoteAction}
        runRemoteAction={runRemoteAction}
        onToggleSignaling={() => void runRemoteAction(
          isConnected ? "停止信令" : "启动信令",
          () => (isConnected ? requireBridge().stopSignaling() : requireBridge().startSignaling())
        )}
      />

      <section className="account-dialog-section account-device-list-panel">
        <div className="account-section-header">
          <div>
            <h3>同账号设备</h3>
            <p>优先尝试局域网直连，不可用时自动降级到跨网通道。</p>
          </div>
          <span className="account-device-count">{devices.length} 台</span>
        </div>
        <RemoteDeviceList
          devices={devices}
          localDeviceID={device?.deviceID}
          connectingDeviceId={connectingDeviceId}
          disabled={Boolean(remoteAction)}
          onConnectDevice={(deviceId) => void connectRemoteDevice(deviceId)}
        />
      </section>
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

function isAccountRemoteState(value: unknown): value is AccountRemoteState {
  return Boolean(value && typeof value === "object" && "account" in value && "signaling" in value);
}
