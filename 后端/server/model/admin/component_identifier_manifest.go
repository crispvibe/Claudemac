package admin

import (
	_ "embed"
	"encoding/json"
	"strings"
	"sync"
)

type componentIdentifierManifestEntry struct {
	RelativePath string `json:"relativePath"`
	ComponentID  string `json:"componentId"`
	RuntimeName  string `json:"runtimeName"`
}

type componentIdentifierManifest struct {
	Entries           []componentIdentifierManifestEntry `json:"entries"`
	NamedComponentIDs map[string]string                  `json:"namedComponentIds"`
}

var (
	//go:embed component_identifier_manifest.json
	componentIdentifierManifestRaw []byte

	componentIdentifierManifestOnce sync.Once
	componentIdentifierPathToID     map[string]string
	componentIdentifierLegacyToID   map[string]string
	componentIdentifierIDSet        map[string]struct{}
)

func loadComponentIdentifierManifest() {
	componentIdentifierManifestOnce.Do(func() {
		componentIdentifierPathToID = make(map[string]string)
		componentIdentifierLegacyToID = make(map[string]string)
		componentIdentifierIDSet = make(map[string]struct{})

		var manifest componentIdentifierManifest
		if err := json.Unmarshal(componentIdentifierManifestRaw, &manifest); err != nil {
			return
		}

		for _, entry := range manifest.Entries {
			relativePath := normalizeLegacyComponentPath(entry.RelativePath)
			componentID := strings.ToLower(strings.TrimSpace(entry.ComponentID))
			if relativePath == "" || componentID == "" {
				continue
			}
			componentIdentifierPathToID[relativePath] = componentID
			componentIdentifierLegacyToID[buildLegacyHashedComponentIdentifier(relativePath)] = componentID
			componentIdentifierIDSet[componentID] = struct{}{}
		}
	})
}

func lookupManifestComponentIdentifierByPath(component string) (string, bool) {
	loadComponentIdentifierManifest()
	componentID, ok := componentIdentifierPathToID[normalizeLegacyComponentPath(component)]
	return componentID, ok
}

func lookupManifestComponentIdentifierByLegacyHash(component string) (string, bool) {
	loadComponentIdentifierManifest()
	componentID, ok := componentIdentifierLegacyToID[strings.ToLower(strings.TrimSpace(component))]
	return componentID, ok
}

func isManifestComponentIdentifier(component string) bool {
	loadComponentIdentifierManifest()
	_, ok := componentIdentifierIDSet[strings.ToLower(strings.TrimSpace(component))]
	return ok
}
