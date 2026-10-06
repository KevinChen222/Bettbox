package main

import (
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/component/age"
)

func parseProviderForTest(t *testing.T, content []byte, provider map[string]any) ([]map[string]any, error) {
	t.Helper()
	options := map[string]any{"type": "http"}
	for key, value := range provider {
		options[key] = value
	}
	input, err := json.Marshal(map[string]any{
		"content": base64.StdEncoding.EncodeToString(content), "provider": options,
	})
	if err != nil {
		t.Fatal(err)
	}
	result, err := handleParseProviderNodes(string(input))
	if err != nil {
		return nil, err
	}
	var nodes []map[string]any
	if err := json.Unmarshal([]byte(result), &nodes); err != nil {
		t.Fatal(err)
	}
	return nodes, nil
}

func TestProviderNodesFormatsAndCredentials(t *testing.T) {
	link := "trojan://secret@example.com:443#HK"
	for _, content := range []string{
		"defaults: &n {type: trojan, server: example.com, port: 443, password: secret}\nproxies: [{<<: *n, name: HK}]",
		`{"proxies":[{"name":"HK","type":"trojan","server":"example.com","port":443,"password":"secret"}]}`,
		link,
		base64.StdEncoding.EncodeToString([]byte(link)),
	} {
		nodes, err := parseProviderForTest(t, []byte(content), map[string]any{})
		if err != nil || len(nodes) != 1 || nodes[0]["name"] != "HK" || nodes[0]["password"] != "secret" || nodes[0]["server"] != "example.com" {
			t.Fatalf("provider format or credentials changed: %v %v", nodes, err)
		}
	}
}

func TestProviderNodesFiltersAndOverrides(t *testing.T) {
	content := []byte(`proxies:
  - {name: HK, type: socks5, server: example.com, port: 1080}
  - {name: HK-blocked, type: socks5, server: example.com, port: 1080}
  - {name: HK-http, type: http, server: example.com, port: 8080}
  - {name: US, type: socks5, server: example.com, port: 1080}
`)
	nodes, err := parseProviderForTest(t, content, map[string]any{
		"filter": "(?i)^hk", "exclude-filter": "blocked", "exclude-type": "http",
		"dialer-proxy": "old-dialer",
		"override": map[string]any{
			"additional-prefix": "IEPL-", "additional-suffix": "-exit",
			"proxy-name": []map[string]any{{"pattern": "HK", "target": "HongKong"}},
			"udp":        true, "dialer-proxy": "new-dialer",
		},
	})
	if err != nil || len(nodes) != 1 || nodes[0]["name"] != "IEPL-HongKong-exit" || nodes[0]["udp"] != true || nodes[0]["dialer-proxy"] != "new-dialer" {
		t.Fatalf("provider filters or overrides changed: %v %v", nodes, err)
	}
}

func TestProviderNodesAgeEncryption(t *testing.T) {
	secret, public, err := age.GenX25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}
	content, err := age.EncryptBytes([]byte("proxies: [{name: encrypted, type: socks5, server: example.com, port: 1080}]"), public)
	if err != nil {
		t.Fatal(err)
	}
	nodes, err := parseProviderForTest(t, content, map[string]any{"age-secret-key": secret})
	if err != nil || len(nodes) != 1 || nodes[0]["name"] != "encrypted" {
		t.Fatalf("encrypted provider: %v %v", nodes, err)
	}
	if _, err := parseProviderForTest(t, content, map[string]any{}); err == nil || !strings.Contains(err.Error(), "decrypt") {
		t.Fatalf("encrypted provider accepted without a key: %v", err)
	}
}
