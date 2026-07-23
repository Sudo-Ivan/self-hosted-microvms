package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"filippo.io/age"
)

const vaultVersion = 1

// Vault is the decrypted in-memory secret store.
type Vault struct {
	Version   int                          `json:"version"`
	Instances map[string]map[string]string `json:"instances"`
}

// StorePaths holds on-disk locations for identity and vault.
type StorePaths struct {
	Dir         string
	Identity    string
	IdentityPub string
	VaultAge    string
}

// DefaultStorePaths returns the standard layout under sharedDir/secrets.
func DefaultStorePaths(sharedDir string) StorePaths {
	dir := filepath.Join(sharedDir, "secrets")
	return StorePaths{
		Dir:         dir,
		Identity:    filepath.Join(dir, "identity.txt"),
		IdentityPub: filepath.Join(dir, "identity.pub"),
		VaultAge:    filepath.Join(dir, "vault.json.age"),
	}
}

func emptyVault() *Vault {
	return &Vault{
		Version:   vaultVersion,
		Instances: map[string]map[string]string{},
	}
}

// InitStore creates identity and empty vault. Tries TPM when available.
func InitStore(paths StorePaths, force bool) error {
	return InitStoreWithProtect(paths, force, ProtectOpts{TryTPM: true})
}

// InitStoreWithProtect creates identity protected per opts.
func InitStoreWithProtect(paths StorePaths, force bool, opts ProtectOpts) error {
	if !force && storeExists(paths) {
		return fmt.Errorf("refusing to overwrite existing secrets store under %s (pass --force)", paths.Dir)
	}
	if err := os.MkdirAll(paths.Dir, 0o700); err != nil {
		return err
	}
	// Clear previous identity material on force reinit.
	for _, p := range []string{paths.Identity, paths.identityAgePath(), paths.identityTPMPath(), paths.protectMetaPath()} {
		_ = os.Remove(p)
	}

	identity, err := age.GenerateX25519Identity()
	if err != nil {
		return err
	}
	pem := []byte(identity.String() + "\n")
	if err := writeStoreFile(paths.Dir, "identity.pub", []byte(identity.Recipient().String()+"\n")); err != nil {
		return err
	}

	meta := ProtectMeta{Version: protectVersion, Mode: ProtectPlain}
	useTPM := !opts.NoTPM && (opts.TryTPM || opts.RequireTPM)
	if useTPM {
		if !TPMAvailable() {
			if opts.RequireTPM {
				return fmt.Errorf("TPM required but no usable device under /dev/tpmrm0 or /dev/tpm0")
			}
		} else {
			blob, tpmPath, err := tpmSeal(pem)
			if err != nil {
				if opts.RequireTPM {
					return err
				}
				fmt.Fprintf(os.Stderr, "warning: TPM seal failed (%v) falling back\n", err)
			} else {
				if err := writeStoreFile(paths.Dir, "identity.tpm", blob); err != nil {
					return err
				}
				meta.TPM = true
				meta.TPMPath = tpmPath
				meta.Mode = ProtectTPM
			}
		}
	}

	if opts.Passphrase != "" {
		wrapped, err := wrapIdentityPassphrase(pem, opts.Passphrase)
		if err != nil {
			return err
		}
		if err := writeStoreFile(paths.Dir, "identity.txt.age", wrapped); err != nil {
			return err
		}
		meta.Passphrase = true
		if meta.TPM {
			meta.Mode = ProtectTPMPass
		} else {
			meta.Mode = ProtectPassphrase
		}
	}

	if !meta.TPM && !meta.Passphrase {
		if err := writeStoreFile(paths.Dir, "identity.txt", pem); err != nil {
			return err
		}
		meta.Mode = ProtectPlain
	}

	if err := writeProtectMeta(paths, meta); err != nil {
		return err
	}
	return SaveVault(paths, emptyVault())
}

// LoadVault decrypts and parses the vault.
func LoadVault(paths StorePaths) (*Vault, error) {
	return LoadVaultWithPassphrase(paths, "")
}

// LoadVaultWithPassphrase decrypts the vault using an optional passphrase.
func LoadVaultWithPassphrase(paths StorePaths, passphrase string) (*Vault, error) {
	identities, err := loadIdentities(paths, passphrase)
	if err != nil {
		return nil, err
	}
	data, err := readStoreFile(paths.Dir, "vault.json.age")
	if err != nil {
		return nil, err
	}
	r, err := age.Decrypt(bytes.NewReader(data), identities...)
	if err != nil {
		return nil, fmt.Errorf("decrypt vault: %w", err)
	}
	plain, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	var v Vault
	if err := json.Unmarshal(plain, &v); err != nil {
		return nil, err
	}
	if v.Instances == nil {
		v.Instances = map[string]map[string]string{}
	}
	if v.Version == 0 {
		v.Version = vaultVersion
	}
	return &v, nil
}

// SaveVault encrypts and writes the vault atomically.
func SaveVault(paths StorePaths, v *Vault) error {
	recipient, err := loadRecipient(paths.IdentityPub)
	if err != nil {
		return err
	}
	if v.Version == 0 {
		v.Version = vaultVersion
	}
	if v.Instances == nil {
		v.Instances = map[string]map[string]string{}
	}
	plain, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	plain = append(plain, '\n')
	var buf bytes.Buffer
	w, err := age.Encrypt(&buf, recipient)
	if err != nil {
		return err
	}
	if _, err := w.Write(plain); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	tmp := "vault.json.age.tmp"
	if err := writeStoreFile(paths.Dir, tmp, buf.Bytes()); err != nil {
		return err
	}
	return os.Rename(filepath.Join(paths.Dir, tmp), paths.VaultAge)
}

func loadIdentities(paths StorePaths, passphrase string) ([]age.Identity, error) {
	pem, err := loadIdentityPEM(paths, passphrase)
	if err != nil {
		return nil, err
	}
	return age.ParseIdentities(bytes.NewReader(pem))
}

func loadRecipient(path string) (age.Recipient, error) {
	dir := filepath.Dir(path)
	name := filepath.Base(path)
	data, err := readStoreFile(dir, name)
	if err != nil {
		return nil, err
	}
	line := strings.TrimSpace(string(data))
	if line == "" {
		return nil, fmt.Errorf("empty recipient file %s", path)
	}
	return age.ParseX25519Recipient(line)
}

// ValidInstanceName rejects empty or path-like names.
func ValidInstanceName(name string) error {
	if name == "" {
		return fmt.Errorf("instance name required")
	}
	if strings.ContainsAny(name, "/\\ \t\n") {
		return fmt.Errorf("invalid instance name")
	}
	return nil
}

// ValidKeyName rejects empty or unsafe env key names.
func ValidKeyName(key string) error {
	if key == "" {
		return fmt.Errorf("key name required")
	}
	for i, c := range key {
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' {
			continue
		}
		if i > 0 && c >= '0' && c <= '9' {
			continue
		}
		return fmt.Errorf("invalid key name %q", key)
	}
	return nil
}

// SetKeys upserts keys for one instance.
func SetKeys(v *Vault, instance string, kv map[string]string) error {
	if err := ValidInstanceName(instance); err != nil {
		return err
	}
	if len(kv) == 0 {
		return fmt.Errorf("no keys to set")
	}
	for k := range kv {
		if err := ValidKeyName(k); err != nil {
			return err
		}
	}
	m := v.Instances[instance]
	if m == nil {
		m = map[string]string{}
		v.Instances[instance] = m
	}
	maps.Copy(m, kv)
	return nil
}

// UnsetKey removes one key. Errors if missing.
func UnsetKey(v *Vault, instance, key string) error {
	if err := ValidInstanceName(instance); err != nil {
		return err
	}
	if err := ValidKeyName(key); err != nil {
		return err
	}
	m := v.Instances[instance]
	if m == nil {
		return fmt.Errorf("no secrets for instance %s", instance)
	}
	if _, ok := m[key]; !ok {
		return fmt.Errorf("key %s not set for instance %s", key, instance)
	}
	delete(m, key)
	if len(m) == 0 {
		delete(v.Instances, instance)
	}
	return nil
}

// InstanceKeys returns sorted key names for an instance.
func InstanceKeys(v *Vault, instance string) ([]string, error) {
	if err := ValidInstanceName(instance); err != nil {
		return nil, err
	}
	m := v.Instances[instance]
	if m == nil {
		return nil, nil
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys, nil
}

// ListInstances returns sorted instance names that have secrets.
func ListInstances(v *Vault) []string {
	names := make([]string, 0, len(v.Instances))
	for name, m := range v.Instances {
		if len(m) > 0 {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

// HasSecrets reports whether the instance has any keys.
func HasSecrets(v *Vault, instance string) bool {
	m := v.Instances[instance]
	return len(m) > 0
}

// ExportMMDS builds Firecracker MMDS JSON for one instance only.
// Returns an error when the instance has no secrets.
func ExportMMDS(v *Vault, instance string) ([]byte, error) {
	if err := ValidInstanceName(instance); err != nil {
		return nil, err
	}
	m := v.Instances[instance]
	if len(m) == 0 {
		return nil, fmt.Errorf("no secrets for instance %s", instance)
	}
	// Copy so callers cannot mutate vault through the export map.
	secrets := make(map[string]string, len(m))
	maps.Copy(secrets, m)
	payload := map[string]any{
		"latest": map[string]any{
			"secrets": secrets,
		},
	}
	return json.MarshalIndent(payload, "", "  ")
}

// ParseKVArgs parses KEY=VALUE arguments.
func ParseKVArgs(args []string) (map[string]string, error) {
	out := map[string]string{}
	for _, a := range args {
		k, v, ok := strings.Cut(a, "=")
		if !ok || k == "" {
			return nil, fmt.Errorf("expected KEY=VALUE got %q", a)
		}
		out[k] = v
	}
	return out, nil
}

// ParseEnvFile reads KEY=VALUE lines. Skips blank lines and # comments.
func ParseEnvFile(r io.Reader) (map[string]string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	out := map[string]string{}
	for line := range strings.SplitSeq(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok || k == "" {
			return nil, fmt.Errorf("invalid env line %q", line)
		}
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if len(v) >= 2 {
			if (v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'') {
				v = v[1 : len(v)-1]
			}
		}
		out[k] = v
	}
	return out, nil
}
