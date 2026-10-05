package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"testing"

	yamlv3 "go.yaml.in/yaml/v3"
)

func TestImportOrdinaryShadowsocks(t *testing.T) {
	for _, cipher := range []string{"aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "aes-256-cfb"} {
		t.Run(cipher, func(t *testing.T) {
			credentials := cipher + ":test-password"
			for _, link := range []string{
				"ss://" + base64.RawURLEncoding.EncodeToString([]byte(credentials)) + "@example.com:443#ordinary-ss",
				"ss://" + base64.RawStdEncoding.EncodeToString([]byte(credentials+"@example.com:443")) + "#ordinary-ss",
				"ss://" + credentials + "@example.com:443#ordinary-ss",
			} {
				nodes, err := parseImportedNodes(link)
				if err != nil || len(nodes) != 1 {
					t.Fatalf("ordinary SS link: %v %v", nodes, err)
				}
				if nodes[0]["cipher"] != cipher || nodes[0]["password"] != "test-password" || nodes[0]["server"] != "example.com" {
					t.Fatalf("SS credentials changed: %v", nodes[0])
				}
				testImportNodeObjects(t, nodes)
			}
		})
	}
}

func TestImportProtocolLinksAndObjects(t *testing.T) {
	const uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"
	vmess, _ := json.Marshal(map[string]any{"v": "2", "ps": "vmess-json", "add": "example.com", "port": "443", "id": uuid, "aid": "0", "scy": "auto", "net": "ws", "path": "/edge", "host": "cdn.example.com", "tls": "tls"})
	ssr := base64.RawURLEncoding.EncodeToString([]byte("example.com:443:origin:aes-128-cfb:plain:" + base64.RawURLEncoding.EncodeToString([]byte("test-password")) + "/?remarks=" + base64.RawURLEncoding.EncodeToString([]byte("ssr"))))
	cases := []struct {
		name, kind, link string
		fields           map[string]any
	}{
		{"ssr", "ssr", "ssr://" + ssr, map[string]any{"password": "test-password", "protocol": "origin"}},
		{"vmess-json", "vmess", "vmess://" + base64.StdEncoding.EncodeToString(vmess), map[string]any{"uuid": uuid, "network": "ws", "tls": true}},
		{"vmess-uri", "vmess", "vmess://" + uuid + "@example.com:443?security=tls&type=grpc&serviceName=edge#vmess-uri", map[string]any{"uuid": uuid, "network": "grpc", "tls": true}},
		{"vless", "vless", "vless://" + uuid + "@example.com:443?encryption=none&security=tls&type=ws&path=%2Fedge#vless", map[string]any{"uuid": uuid, "network": "ws", "tls": true}},
		{"vless-reality", "vless", "vless://" + uuid + "@example.com:443?security=reality&type=tcp&pbk=ppQ9FwLrLIa0AOrp1WvcyiaQ37vg2WSy_CD4bIdiTUw&sid=00112233&flow=xtls-rprx-vision#reality", map[string]any{"uuid": uuid, "flow": "xtls-rprx-vision", "tls": true}},
		{"trojan", "trojan", "trojan://test-password@example.com:443?sni=example.com&type=ws&path=%2Fedge#trojan", map[string]any{"password": "test-password", "network": "ws"}},
		{"hysteria", "hysteria", "hysteria://example.com:443?auth=test-password&upmbps=10&downmbps=50&protocol=udp#hysteria", map[string]any{"auth_str": "test-password"}},
		{"hysteria2", "hysteria2", "hysteria2://test-password@example.com:443?obfs=salamander&obfs-password=obfs-test&sni=example.com#hysteria2", map[string]any{"password": "test-password", "obfs": "salamander"}},
		{"hy2", "hysteria2", "hy2://test-password@example.com:443?sni=example.com#hy2", map[string]any{"password": "test-password"}},
		{"tuic", "tuic", "tuic://" + uuid + ":test-password@example.com:443?congestion_control=bbr#tuic", map[string]any{"uuid": uuid, "password": "test-password"}},
		{"anytls", "anytls", "anytls://test-password@example.com:443?sni=example.com#anytls", map[string]any{"password": "test-password"}},
		{"http", "http", "http://user:test-password@example.com:443#http", map[string]any{"username": "user", "password": "test-password"}},
		{"https", "http", "https://user:test-password@example.com:443#https", map[string]any{"username": "user", "password": "test-password", "tls": true}},
		{"socks", "socks5", "socks://user:test-password@example.com:443#socks", map[string]any{"username": "user", "password": "test-password"}},
		{"socks5", "socks5", "socks5://user:test-password@example.com:443#socks5", map[string]any{"username": "user", "password": "test-password"}},
		{"socks5h", "socks5", "socks5h://user:test-password@example.com:443#socks5h", map[string]any{"username": "user", "password": "test-password"}},
		{"mieru", "mieru", "mierus://user:test-password@example.com?port=443&protocol=TCP&profile=mieru", map[string]any{"username": "user", "password": "test-password"}},
	}
	var links []string
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			nodes, err := parseImportedNodes(tc.link)
			if err != nil || len(nodes) != 1 {
				t.Fatalf("%s import: %v %v", tc.name, nodes, err)
			}
			node := nodes[0]
			if node["type"] != tc.kind || node["server"] != "example.com" || fmt.Sprint(node["port"]) != "443" {
				t.Fatalf("endpoint/type changed: %v", node)
			}
			for key, value := range tc.fields {
				if node[key] != value {
					t.Fatalf("%s changed: got %v, want %v", key, node[key], value)
				}
			}
			testImportNodeObjects(t, nodes)
		})
		links = append(links, tc.link)
	}
	for _, input := range []string{strings.Join(links, "\n"), base64.StdEncoding.EncodeToString([]byte(strings.Join(links, "\n")))} {
		nodes, err := parseImportedNodes(input)
		if err != nil || len(nodes) != len(cases) {
			t.Fatalf("mixed-protocol subscription: %d nodes, %v", len(nodes), err)
		}
	}
}

func testImportNodeObjects(t *testing.T, expected []map[string]any) {
	t.Helper()
	jsonNode, _ := json.Marshal(expected[0])
	yamlNodes, _ := yamlv3.Marshal(map[string]any{"proxies": expected})
	for _, input := range []string{string(jsonNode), " - " + string(jsonNode), string(yamlNodes)} {
		nodes, err := parseImportedNodes(input)
		if err != nil || len(nodes) != len(expected) {
			t.Fatalf("node object import: %v %v", nodes, err)
		}
		want, _ := json.Marshal(expected)
		got, _ := json.Marshal(nodes)
		if string(got) != string(want) {
			t.Fatalf("node fields changed: got %s, want %s", got, want)
		}
	}
}

func TestImportSSPluginAndIPv6(t *testing.T) {
	credentials := base64.RawURLEncoding.EncodeToString([]byte("aes-128-gcm:test-password"))
	link := "ss://" + credentials + "@[2001:db8::1]:443?plugin=" + url.QueryEscape("obfs-local;obfs=http;obfs-host=cdn.example.com") + "#ipv6-plugin"
	nodes, err := parseImportedNodes(link)
	if err != nil || len(nodes) != 1 || nodes[0]["server"] != "2001:db8::1" || nodes[0]["plugin"] != "obfs" {
		t.Fatalf("SS IPv6/plugin: %v %v", nodes, err)
	}
	testImportNodeObjects(t, nodes)
}
