package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func testPaths(t *testing.T) StorePaths {
	t.Helper()
	dir := t.TempDir()
	return DefaultStorePaths(dir)
}

func TestInitRefuseOverwrite(t *testing.T) {
	paths := testPaths(t)
	if err := InitStore(paths, false); err != nil {
		t.Fatal(err)
	}
	if err := InitStore(paths, false); err == nil {
		t.Fatal("expected refuse overwrite")
	}
	if err := InitStore(paths, true); err != nil {
		t.Fatal(err)
	}
}

func TestSetListUnsetRoundTrip(t *testing.T) {
	paths := testPaths(t)
	if err := InitStore(paths, false); err != nil {
		t.Fatal(err)
	}
	v, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	if err := SetKeys(v, "navi", map[string]string{
		"NAVIDROME_PASSWORD": "s3cret",
		"API_TOKEN":          "tok",
	}); err != nil {
		t.Fatal(err)
	}
	if err := SaveVault(paths, v); err != nil {
		t.Fatal(err)
	}
	v2, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	keys, err := InstanceKeys(v2, "navi")
	if err != nil {
		t.Fatal(err)
	}
	if len(keys) != 2 || keys[0] != "API_TOKEN" || keys[1] != "NAVIDROME_PASSWORD" {
		t.Fatalf("keys = %v", keys)
	}
	if !HasSecrets(v2, "navi") {
		t.Fatal("expected has secrets")
	}
	if err := UnsetKey(v2, "navi", "API_TOKEN"); err != nil {
		t.Fatal(err)
	}
	if err := SaveVault(paths, v2); err != nil {
		t.Fatal(err)
	}
	v3, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	keys, _ = InstanceKeys(v3, "navi")
	if len(keys) != 1 || keys[0] != "NAVIDROME_PASSWORD" {
		t.Fatalf("keys after unset = %v", keys)
	}
}

func TestExportACLIsolation(t *testing.T) {
	paths := testPaths(t)
	if err := InitStore(paths, false); err != nil {
		t.Fatal(err)
	}
	v, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	_ = SetKeys(v, "alpha", map[string]string{"A_KEY": "alpha-secret"})
	_ = SetKeys(v, "beta", map[string]string{"B_KEY": "beta-secret"})
	if err := SaveVault(paths, v); err != nil {
		t.Fatal(err)
	}
	v2, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	out, err := ExportMMDS(v2, "alpha")
	if err != nil {
		t.Fatal(err)
	}
	s := string(out)
	if !strings.Contains(s, "A_KEY") || !strings.Contains(s, "alpha-secret") {
		t.Fatalf("missing alpha secrets: %s", s)
	}
	if strings.Contains(s, "B_KEY") || strings.Contains(s, "beta-secret") {
		t.Fatalf("leaked beta secrets: %s", s)
	}
	if _, err := ExportMMDS(v2, "missing"); err == nil {
		t.Fatal("expected error for missing instance")
	}
}

func TestExportMMDSShape(t *testing.T) {
	v := emptyVault()
	_ = SetKeys(v, "mcx", map[string]string{"TOKEN": "x"})
	out, err := ExportMMDS(v, "mcx")
	if err != nil {
		t.Fatal(err)
	}
	var payload map[string]any
	if err := json.Unmarshal(out, &payload); err != nil {
		t.Fatal(err)
	}
	latest, ok := payload["latest"].(map[string]any)
	if !ok {
		t.Fatalf("latest missing: %v", payload)
	}
	secrets, ok := latest["secrets"].(map[string]any)
	if !ok {
		t.Fatalf("secrets missing: %v", latest)
	}
	if secrets["TOKEN"] != "x" {
		t.Fatalf("TOKEN = %v", secrets["TOKEN"])
	}
}

func TestParseEnvFile(t *testing.T) {
	in := "# comment\nFOO=bar\nBAZ='qux'\n\n"
	kv, err := ParseEnvFile(bytes.NewBufferString(in))
	if err != nil {
		t.Fatal(err)
	}
	if kv["FOO"] != "bar" || kv["BAZ"] != "qux" {
		t.Fatalf("kv = %#v", kv)
	}
}

func TestCLIExistsAndExport(t *testing.T) {
	shared := t.TempDir()
	paths := DefaultStorePaths(shared)
	if err := InitStore(paths, false); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"set", "demo", "K=v", "--shared-dir", shared}); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"exists", "demo", "--shared-dir", shared}); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"exists", "other", "--shared-dir", shared}); err != errNotExists {
		t.Fatalf("expected errNotExists got %v", err)
	}
	v, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	out, err := ExportMMDS(v, "demo")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out, []byte(`"K"`)) {
		t.Fatalf("export missing key: %s", out)
	}
}

func TestValidNames(t *testing.T) {
	if ValidInstanceName("") == nil {
		t.Fatal("empty instance")
	}
	if ValidInstanceName("a/b") == nil {
		t.Fatal("slash instance")
	}
	if ValidKeyName("1BAD") == nil {
		t.Fatal("digit start")
	}
	if ValidKeyName("GOOD_KEY") != nil {
		t.Fatal("GOOD_KEY should pass")
	}
}
