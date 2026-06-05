import appIcon from "../assets/app-icon.png";

export function AppLogo({ className = "" }: { className?: string }) {
  return <img alt="Acode" className={`app-icon-image ${className}`.trim()} draggable={false} src={appIcon} />;
}
