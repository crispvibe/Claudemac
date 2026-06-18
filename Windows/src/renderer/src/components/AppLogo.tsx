import appIcon from "../assets/app-icon.png";

export function AppLogo({ className = "" }: { className?: string }) {
  return <img alt="Codevoke" className={`app-icon-image ${className}`.trim()} draggable={false} src={appIcon} />;
}
