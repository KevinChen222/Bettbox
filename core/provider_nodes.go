package main

import (
	"encoding/base64"
	"encoding/json"

	"github.com/metacubex/mihomo/adapter/provider"
)

func handleParseProviderNodes(input string) (string, error) {
	var params struct {
		Content  string         `json:"content"`
		Provider map[string]any `json:"provider"`
	}
	if err := json.Unmarshal([]byte(input), &params); err != nil {
		return "", err
	}
	content, err := base64.StdEncoding.DecodeString(params.Content)
	if err != nil {
		return "", err
	}
	nodes, err := provider.ParseProxyProviderNodes(content, params.Provider)
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(nodes)
	return string(data), err
}
