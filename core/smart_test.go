package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/smart"
	"github.com/metacubex/mihomo/component/smart/lightgbm"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

func TestSmartConfigAndSelection(t *testing.T) {
	constant.SetHomeDir(t.TempDir())
	t.Cleanup(func() { _ = cachefile.Cache().Close() })
	cfg, err := config.Parse([]byte(`
mode: rule
proxy-groups:
  - name: Smart
    type: smart
    proxies: [DIRECT, REJECT]
    lazy: true
    uselightgbm: false
    collectdata: false
    prefer-asn: false
    policy-priority: "DIRECT:1.2"
    tolerance: 50
rules:
  - MATCH,Smart
`))
	if err != nil {
		t.Fatalf("Smart configuration rejected: %v", err)
	}
	group, ok := cfg.Proxies["Smart"].Adapter().(*outboundgroup.Smart)
	if !ok {
		t.Fatalf("expected Smart adapter, got %T", cfg.Proxies["Smart"].Adapter())
	}
	t.Cleanup(func() { _ = group.Close() })

	if err := group.Set("DIRECT"); err != nil {
		t.Fatal(err)
	}
	if group.Now() != "DIRECT" {
		t.Fatal("manual selection was not applied")
	}
	if err := group.Set("missing"); err == nil {
		t.Fatal("invalid proxy selection was accepted")
	}
	// A Smart card in another group probes its selected route once; it must not
	// health-check every member or clear the manually fixed selection.
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		time.Sleep(10 * time.Millisecond)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	previousHook := adapter.UrlTestHook
	adapter.UrlTestHook = nil
	t.Cleanup(func() { adapter.UrlTestHook = previousHook })
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if delay, err := cfg.Proxies["Smart"].URLTest(ctx, server.URL, nil); err != nil || delay == 0 {
		t.Fatalf("single Smart route probe failed: delay=%d, err=%v", delay, err)
	}
	if requests.Load() != 1 || group.Now() != "DIRECT" {
		t.Fatalf("route probe changed selection or sent extra probes: count=%d, now=%q", requests.Load(), group.Now())
	}
	// Bettbox clears computed selections through SelectAble.ForceSet.
	var selectable outboundgroup.SelectAble = group
	selectable.ForceSet("")
	data, err := json.Marshal(group)
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	if result["type"] != "Smart" || result["fixed"] != "" {
		t.Fatalf("unexpected automatic group state: %s", data)
	}
	if len(result["all"].([]any)) != 2 {
		t.Fatalf("Smart members missing from client JSON: %s", data)
	}
}

func TestMissingDelayTargetKeepsRequestURL(t *testing.T) {
	params := TestDelayParams{ProxyName: "missing-smart-target", TestUrl: "https://example.com/generate_204", Timeout: 1000}
	data, _ := json.Marshal(params)
	response := make(chan string, 1)
	handleAsyncTestDelay(string(data), func(value string) { response <- value })
	select {
	case value := <-response:
		var delay Delay
		if err := json.Unmarshal([]byte(value), &delay); err != nil {
			t.Fatal(err)
		}
		if delay.Url != params.TestUrl || delay.Name != params.ProxyName || delay.Value != -1 {
			t.Fatalf("failure cannot clear the requested card's spinner: %+v", delay)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("missing target did not return")
	}
}

func TestLightGBMUpdateRejectsInvalidModel(t *testing.T) {
	constant.SetHomeDir(t.TempDir())
	previousURL := lightgbm.LgbmUrl()
	t.Cleanup(func() { lightgbm.SetLgbmUrl(previousURL) })
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("invalid model"))
	}))
	defer server.Close()
	lightgbm.SetLgbmUrl(server.URL)
	oldModel := []byte("existing model")
	if err := os.WriteFile(constant.Path.SmartModel(), oldModel, 0600); err != nil {
		t.Fatal(err)
	}
	result := make(chan string, 1)
	handleUpdateGeoData("LightGBM", "Model.bin", func(value string) { result <- value })
	select {
	case message := <-result:
		if !strings.Contains(message, "invalid LightGBM model") {
			t.Fatalf("expected model validation failure, got %q", message)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("model update did not return its result")
	}
	saved, err := os.ReadFile(constant.Path.SmartModel())
	if err != nil || string(saved) != string(oldModel) {
		t.Fatalf("failed update replaced the old model: %q, %v", saved, err)
	}
}

func TestLightGBMUpdateReloadsModel(t *testing.T) {
	constant.SetHomeDir(t.TempDir())
	previousURL := lightgbm.LgbmUrl()
	t.Cleanup(func() { lightgbm.SetLgbmUrl(previousURL) })
	// A valid single-leaf LightGBM model makes reloading observable without
	// depending on GitHub or the size and contents of its published model.
	model := "tree\nversion=v4\nnum_class=1\nnum_tree_per_iteration=1\nmax_feature_idx=29\ntree_sizes=1\n\nTree=0\nnum_leaves=1\nnum_cat=0\nleaf_value=0.4\n\n"
	if err := os.WriteFile(constant.Path.SmartModel(), []byte(model), 0600); err != nil {
		t.Fatal(err)
	}
	predictor := lightgbm.GetModel()
	input := &smart.ModelInput{Success: 100}
	if weight, ok := predictor.PredictWeight(input, 1); !ok || weight != 0.4 {
		t.Fatalf("initial model was not loaded: %v, %v", weight, ok)
	}
	updated := strings.Replace(model, "leaf_value=0.4", "leaf_value=0.8", 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(updated))
	}))
	defer server.Close()
	lightgbm.SetLgbmUrl(server.URL)
	result := make(chan string, 1)
	handleUpdateGeoData("LightGBM", "Model.bin", func(value string) { result <- value })
	select {
	case message := <-result:
		if message != "" {
			t.Fatal(message)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("model update timed out")
	}
	if weight, ok := predictor.PredictWeight(input, 1); !ok || weight != 0.8 {
		t.Fatalf("updated model was not reloaded: %v, %v", weight, ok)
	}
	saved, err := os.ReadFile(constant.Path.SmartModel())
	if err != nil || string(saved) != updated {
		t.Fatalf("model not saved to HomeDir/Model.bin: %v", err)
	}
}

func TestSmartKeepsGeoDatabasesActive(t *testing.T) {
	previous := currentRawConfig
	t.Cleanup(func() { currentRawConfig = previous })
	currentRawConfig = &config.RawConfig{
		ProxyGroup: []map[string]any{{"name": "Smart", "type": "smart"}},
	}
	hasMMDB, _, hasASN := checkActiveGeoUsage()
	if !hasMMDB || !hasASN {
		t.Fatal("Smart databases would be unloaded while in use")
	}
}
