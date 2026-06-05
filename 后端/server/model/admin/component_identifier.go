package admin

import (
	"crypto/sha1"
	"encoding/hex"
	"strings"
)

const componentIDPrefix = "cmp_"

func normalizeLegacyComponentPath(component string) string {
	normalized := strings.TrimSpace(strings.ReplaceAll(component, "\\", "/"))
	normalized = strings.TrimPrefix(normalized, "/")
	if strings.HasPrefix(normalized, "src/") {
		normalized = strings.TrimPrefix(normalized, "src/")
	}
	return normalized
}

func IsLegacyComponentPath(component string) bool {
	normalized := normalizeLegacyComponentPath(component)
	return strings.HasPrefix(normalized, "view/") && strings.HasSuffix(normalized, ".vue")
}

func IsComponentIdentifier(component string) bool {
	normalized := strings.ToLower(strings.TrimSpace(component))
	if !strings.HasPrefix(normalized, componentIDPrefix) {
		return false
	}
	if len(normalized) != len(componentIDPrefix)+16 {
		return false
	}
	for _, char := range normalized[len(componentIDPrefix):] {
		if (char < '0' || char > '9') && (char < 'a' || char > 'f') {
			return false
		}
	}
	return true
}

func buildLegacyHashedComponentIdentifier(component string) string {
	normalized := normalizeLegacyComponentPath(component)
	if !IsLegacyComponentPath(normalized) {
		return normalized
	}
	sum := sha1.Sum([]byte(normalized))
	return componentIDPrefix + hex.EncodeToString(sum[:])[:16]
}

func BuildComponentIdentifierFromLegacyPath(component string) string {
	normalized := normalizeLegacyComponentPath(component)
	if !IsLegacyComponentPath(normalized) {
		return normalized
	}
	if componentID, ok := lookupManifestComponentIdentifierByPath(normalized); ok {
		return componentID
	}
	return buildLegacyHashedComponentIdentifier(normalized)
}

func NormalizeComponentIdentifier(component string) string {
	normalized := normalizeLegacyComponentPath(component)
	if normalized == "" {
		return ""
	}
	if IsComponentIdentifier(normalized) {
		if componentID, ok := lookupManifestComponentIdentifierByLegacyHash(normalized); ok {
			return componentID
		}
		if isManifestComponentIdentifier(normalized) {
			return strings.ToLower(normalized)
		}
		return strings.ToLower(normalized)
	}
	if IsLegacyComponentPath(normalized) {
		return BuildComponentIdentifierFromLegacyPath(normalized)
	}
	return normalized
}
