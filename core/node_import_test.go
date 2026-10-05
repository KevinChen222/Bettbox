package main

import (
	"encoding/base64"
	"encoding/json"
	"net/url"
	"testing"
)

func TestImportSS2022LinksAndObjects(t *testing.T) {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	credentials := base64.RawStdEncoding.EncodeToString([]byte("2022-blake3-aes-256-gcm:" + key))
	link := "ss://" + credentials + "@example.com:64000#" + url.PathEscape("🇭🇰 测试出口")
	object := map[string]any{"type": "ss", "name": "🇭🇰 测试出口", "server": "example.com", "port": 64000, "cipher": "2022-blake3-aes-256-gcm", "password": key, "udp": true, "skip-cert-verify": true}
	encoded, _ := json.Marshal(object)
	for _, input := range []string{
		link + "\n" + link,
		base64.StdEncoding.EncodeToString([]byte(link + "\n" + link)),
		" - " + string(encoded) + "\n  - " + string(encoded),
		string(encoded) + "\n" + string(encoded),
		link + "\n" + string(encoded),
	} {
		nodes, err := parseImportedNodes(input)
		if err != nil {
			t.Fatal(err)
		}
		if len(nodes) != 2 || nodes[0]["name"] != "🇭🇰 测试出口" || nodes[1]["name"] != "🇭🇰 测试出口 (2)" {
			t.Fatalf("unexpected names: %v", nodes)
		}
		for _, node := range nodes {
			if node["cipher"] != object["cipher"] || node["password"] != key || node["server"] != "example.com" {
				t.Fatalf("SS2022 parameters changed: %v", node)
			}
		}
	}
}

func TestImportOnlySubscriptionNodes(t *testing.T) {
	nodes, err := parseImportedNodes(`proxies:
  - name: test
    type: socks5
    server: example.com
    port: 1080
    password: "quoted } { password"
proxy-groups:
  - name: ignored
    type: not-a-valid-group
rules: [invalid-rule]
`)
	if err != nil || len(nodes) != 1 || nodes[0]["password"] != "quoted } { password" {
		t.Fatalf("subscription extraction: %v %v", nodes, err)
	}
	nodes, err = parseImportedNodes(`{name: nested, type: socks5, server: example.com, port: 1080, password: 'it''s } {', custom: {headers: [a, b]}}
{name: next, type: http, server: example.com, port: 8080}`)
	if err != nil || len(nodes) != 2 || nodes[0]["password"] != "it's } {" {
		t.Fatalf("flow objects: %v %v", nodes, err)
	}
}

func TestImportRejectsInvalidBatch(t *testing.T) {
	for _, input := range []string{
		"", "proxies: []", "proxies: invalid", "proxy-providers: {}",
		"{name: bad, type: ss, server: example.com, port: 1, cipher: invalid, password: x}",
		"{name: test, type: socks5, server: example.com, port: 1080}\nnot-a-node",
		"{name: test, type: socks5, server: example.com, port: 1080", "unknown://example.com",
	} {
		if nodes, err := parseImportedNodes(input); err == nil || nodes != nil {
			t.Fatalf("invalid input accepted: %v %v", nodes, err)
		}
	}
}
