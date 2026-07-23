package main

import (
	"os"
	"testing"
)

func TestPassphraseWrapRoundTrip(t *testing.T) {
	paths := testPaths(t)
	const pw = "test-passphrase-not-secret"
	if err := InitStoreWithProtect(paths, false, ProtectOpts{
		Passphrase: pw,
		NoTPM:      true,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(paths.Identity); !os.IsNotExist(err) {
		t.Fatal("expected no plaintext identity.txt")
	}
	if _, err := os.Stat(paths.identityAgePath()); err != nil {
		t.Fatal(err)
	}
	meta, err := ProtectStatus(paths)
	if err != nil {
		t.Fatal(err)
	}
	if meta.Mode != ProtectPassphrase || !meta.Passphrase {
		t.Fatalf("meta = %+v", meta)
	}

	v, err := LoadVaultWithPassphrase(paths, pw)
	if err != nil {
		t.Fatal(err)
	}
	if err := SetKeys(v, "navi", map[string]string{"K": "v"}); err != nil {
		t.Fatal(err)
	}
	if err := SaveVault(paths, v); err != nil {
		t.Fatal(err)
	}
	v2, err := LoadVaultWithPassphrase(paths, pw)
	if err != nil {
		t.Fatal(err)
	}
	if !HasSecrets(v2, "navi") {
		t.Fatal("missing secrets after passphrase unlock")
	}
	if _, err := LoadVaultWithPassphrase(paths, "wrong"); err == nil {
		t.Fatal("expected wrong passphrase to fail")
	}
}

func TestProtectStatusPlain(t *testing.T) {
	paths := testPaths(t)
	if err := InitStoreWithProtect(paths, false, ProtectOpts{NoTPM: true}); err != nil {
		t.Fatal(err)
	}
	meta, err := ProtectStatus(paths)
	if err != nil {
		t.Fatal(err)
	}
	if meta.Mode != ProtectPlain {
		t.Fatalf("mode=%s", meta.Mode)
	}
}

func TestRequireTPMWithoutDevice(t *testing.T) {
	if TPMAvailable() {
		t.Skip("TPM present")
	}
	paths := testPaths(t)
	err := InitStoreWithProtect(paths, false, ProtectOpts{RequireTPM: true, TryTPM: true})
	if err == nil {
		t.Fatal("expected require TPM to fail without device")
	}
}

func TestTPMSealIfAvailable(t *testing.T) {
	if !TPMAvailable() {
		t.Skip("no TPM device")
	}
	paths := testPaths(t)
	if err := InitStoreWithProtect(paths, false, ProtectOpts{RequireTPM: true, TryTPM: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(paths.Identity); !os.IsNotExist(err) {
		t.Fatal("expected no plaintext identity")
	}
	if _, err := os.Stat(paths.identityTPMPath()); err != nil {
		t.Fatal(err)
	}
	v, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	_ = SetKeys(v, "x", map[string]string{"A": "1"})
	if err := SaveVault(paths, v); err != nil {
		t.Fatal(err)
	}
	v2, err := LoadVault(paths)
	if err != nil {
		t.Fatal(err)
	}
	if !HasSecrets(v2, "x") {
		t.Fatal("tpm unseal load failed")
	}
}
