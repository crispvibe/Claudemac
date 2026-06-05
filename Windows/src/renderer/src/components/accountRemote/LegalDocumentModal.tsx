import { X } from "lucide-react";
import type { RemoteLegalDocument } from "@shared/account";

export function LegalDocumentModal({ document, onClose }: { document: RemoteLegalDocument; onClose: () => void }) {
  return (
    <div className="legal-document-overlay" role="presentation" onMouseDown={(event) => {
      if (event.currentTarget === event.target) {
        onClose();
      }
    }}>
      <section className="legal-document-modal" role="dialog" aria-modal="true" aria-label={document.title}>
        <header>
          <div>
            <h3>{document.title}</h3>
            <p>版本 {document.version || "未标记"} · {document.platform || "all"}</p>
          </div>
          <button type="button" onClick={onClose} aria-label="关闭协议">
            <X size={16} />
          </button>
        </header>
        <div className="legal-document-content">
          {document.content}
        </div>
      </section>
    </div>
  );
}
