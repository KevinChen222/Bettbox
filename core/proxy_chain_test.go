package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// Exercise dialer-proxy through two real local HTTP CONNECT hops. The Dart
// compiler tests verify that generated configs use this same hop direction.
func TestProxyChainConnectDirection(t *testing.T) {
	for _, entryType := range []string{"node", "select", "smart"} {
		t.Run(entryType, func(t *testing.T) { testProxyChainEntry(t, entryType) })
	}
}

func testProxyChainEntry(t *testing.T, entryType string) {
	t.Helper()
	constant.SetHomeDir(t.TempDir())
	t.Cleanup(func() { _ = cachefile.Cache().Close() })
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, "chain reached destination")
	}))
	defer target.Close()

	var firstCount, lastCount atomic.Int32
	last := chainConnectProxy(t, target.Listener.Addr().String(), &lastCount)
	defer last.Close()
	first := chainConnectProxy(t, last.Listener.Addr().String(), &firstCount)
	defer first.Close()
	firstHost, firstPort, _ := net.SplitHostPort(first.Listener.Addr().String())
	lastHost, lastPort, _ := net.SplitHostPort(last.Listener.Addr().String())
	dialer, groupType := "Entry", entryType
	if entryType == "node" {
		dialer, groupType = "First", "select"
	}
	cfg, err := config.Parse([]byte(fmt.Sprintf(`
mode: rule
proxies:
  - name: First
    type: http
    server: %s
    port: %s
  - name: Last via Entry
    type: http
    server: %s
    port: %s
    dialer-proxy: %s
    x-bettbox-chain-id: test
proxy-groups:
  - name: Entry
    type: %s
    proxies: [First]
    uselightgbm: false
    collectdata: false
    x-bettbox-chain-had-proxies: true
  - name: route
    type: select
    proxies: [Last via Entry]
    hidden: true
    x-bettbox-chain-id: test
rules:
  - MATCH,route
`, firstHost, firstPort, lastHost, lastPort, dialer, groupType)))
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(cfg.Proxies["route"])
	if err != nil {
		t.Fatal(err)
	}
	var group map[string]any
	if err := json.Unmarshal(data, &group); err != nil {
		t.Fatal(err)
	}
	if group["hidden"] != true {
		t.Fatalf("hidden chain group is not reported to the client: %s", data)
	}
	// Dialer references use the tunnel's configured proxy registry.
	previous, previousProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	t.Cleanup(func() { tunnel.UpdateProxies(previous, previousProviders) })
	targetHost, targetPort, _ := net.SplitHostPort(target.Listener.Addr().String())
	port, _ := strconv.Atoi(targetPort)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := cfg.Proxies["route"].DialContext(ctx, &constant.Metadata{
		DstIP: netip.MustParseAddr(targetHost), DstPort: uint16(port),
		NetWork: constant.TCP,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	request, _ := http.NewRequest(http.MethodGet, target.URL, nil)
	if err := request.Write(conn); err != nil {
		t.Fatal(err)
	}
	response, err := http.ReadResponse(bufio.NewReader(conn), request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || string(body) != "chain reached destination" {
		t.Fatalf("unexpected destination response: %q, %v", body, err)
	}
	if firstCount.Load() != 1 || lastCount.Load() != 1 {
		t.Fatalf("expected one connection through each hop, got %d / %d", firstCount.Load(), lastCount.Load())
	}
}

func chainConnectProxy(t *testing.T, destination string, count *atomic.Int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect || r.Host != destination {
			http.Error(w, "unexpected hop destination", http.StatusBadGateway)
			return
		}
		outbound, err := net.DialTimeout("tcp", destination, 5*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer outbound.Close()
		inbound, rw, err := w.(http.Hijacker).Hijack()
		if err != nil {
			t.Error(err)
			return
		}
		defer inbound.Close()
		_, _ = rw.WriteString("HTTP/1.1 200 Connection Established\r\n\r\n")
		_ = rw.Flush()
		count.Add(1)
		go func() { _, _ = io.Copy(outbound, rw); _ = outbound.Close() }()
		_, _ = io.Copy(inbound, outbound)
	}))
}
