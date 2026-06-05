package utils

import (
	"fmt"
	"testing"
)

func TestGetJSONKeys(t *testing.T) {
	var jsonStr = `
	{
		"Name": "test",
		"TableName": "test",
		"TemplateID": "test",
		"TemplateInfo": "test",
		"Limit": 0
}`
	keys, err := GetJSONKeys(jsonStr)
	if err != nil {
		t.Errorf("GetJSONKeys failed: %v", err)
		return
	}
	if len(keys) != 5 {
		t.Errorf("GetJSONKeys failed: unexpected key count %d", len(keys))
		return
	}
	if keys[0] != "Name" {
		t.Errorf("GetJSONKeys failed: unexpected key[0]=%s", keys[0])

		return
	}
	if keys[1] != "TableName" {
		t.Errorf("GetJSONKeys failed: unexpected key[1]=%s", keys[1])

		return
	}
	if keys[2] != "TemplateID" {
		t.Errorf("GetJSONKeys failed: unexpected key[2]=%s", keys[2])

		return
	}
	if keys[3] != "TemplateInfo" {
		t.Errorf("GetJSONKeys failed: unexpected key[3]=%s", keys[3])

		return
	}
	if keys[4] != "Limit" {
		t.Errorf("GetJSONKeys failed: unexpected key[4]=%s", keys[4])

		return
	}

	fmt.Println(keys)
}
