package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"filippo.io/age"
	"golang.org/x/term"
)

const protectVersion = 1

// ProtectMode describes how the age identity private key is stored.
type ProtectMode string

const (
	ProtectPlain      ProtectMode = "plain"
	ProtectPassphrase ProtectMode = "passphrase"
	ProtectTPM        ProtectMode = "tpm"
	ProtectTPMPass    ProtectMode = "tpm+passphrase"
)

// ProtectMeta is written next to the vault for status and unlock hints.
type ProtectMeta struct {
	Version    int         `json:"version"`
	Mode       ProtectMode `json:"mode"`
	TPMPath    string      `json:"tpm_path,omitempty"`
	Passphrase bool        `json:"passphrase"`
	TPM        bool        `json:"tpm"`
}

// ProtectOpts controls identity protection during init.
type ProtectOpts struct {
	Passphrase string
	TryTPM     bool
	RequireTPM bool
	NoTPM      bool
}

func (p StorePaths) protectMetaPath() string {
	return p.Dir + "/protect.json"
}

func (p StorePaths) identityAgePath() string {
	return p.Dir + "/identity.txt.age"
}

func (p StorePaths) identityTPMPath() string {
	return p.Dir + "/identity.tpm"
}

func writeProtectMeta(paths StorePaths, meta ProtectMeta) error {
	meta.Version = protectVersion
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return writeStoreFile(paths.Dir, "protect.json", data)
}

func readProtectMeta(paths StorePaths) (ProtectMeta, error) {
	data, err := readStoreFile(paths.Dir, "protect.json")
	if err != nil {
		return ProtectMeta{}, err
	}
	var meta ProtectMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return ProtectMeta{}, err
	}
	return meta, nil
}

// ProtectStatus summarizes how the identity is protected.
func ProtectStatus(paths StorePaths) (ProtectMeta, error) {
	meta, err := readProtectMeta(paths)
	if err == nil {
		return meta, nil
	}
	if !os.IsNotExist(err) {
		return ProtectMeta{}, err
	}
	// Infer from files for stores created before protect.json.
	meta = ProtectMeta{Version: protectVersion, Mode: ProtectPlain}
	if _, err := os.Stat(paths.Identity); err == nil {
		meta.Mode = ProtectPlain
	}
	if _, err := os.Stat(paths.identityAgePath()); err == nil {
		meta.Passphrase = true
		meta.Mode = ProtectPassphrase
	}
	if _, err := os.Stat(paths.identityTPMPath()); err == nil {
		meta.TPM = true
		if meta.Passphrase {
			meta.Mode = ProtectTPMPass
		} else {
			meta.Mode = ProtectTPM
		}
	}
	return meta, nil
}

func wrapIdentityPassphrase(identityPEM []byte, passphrase string) ([]byte, error) {
	if passphrase == "" {
		return nil, fmt.Errorf("passphrase required")
	}
	recipient, err := age.NewScryptRecipient(passphrase)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	w, err := age.Encrypt(&buf, recipient)
	if err != nil {
		return nil, err
	}
	if _, err := w.Write(identityPEM); err != nil {
		return nil, err
	}
	if err := w.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func unwrapIdentityPassphrase(blob []byte, passphrase string) ([]byte, error) {
	if passphrase == "" {
		return nil, fmt.Errorf("passphrase required to unlock identity")
	}
	id, err := age.NewScryptIdentity(passphrase)
	if err != nil {
		return nil, err
	}
	r, err := age.Decrypt(bytes.NewReader(blob), id)
	if err != nil {
		return nil, fmt.Errorf("passphrase unlock failed: %w", err)
	}
	return io.ReadAll(r)
}

// ResolvePassphrase returns a passphrase from env, file, or interactive prompt.
func ResolvePassphrase(passphraseFile string, allowPrompt bool) (string, error) {
	if pw := os.Getenv("MVM_SECRETS_PASSPHRASE"); pw != "" {
		return pw, nil
	}
	file := passphraseFile
	if file == "" {
		file = os.Getenv("MVM_SECRETS_PASSPHRASE_FILE")
	}
	if file != "" {
		data, err := readOperatorFile(file)
		if err != nil {
			return "", err
		}
		return strings.TrimRight(string(data), "\r\n"), nil
	}
	if !allowPrompt {
		return "", fmt.Errorf("passphrase required set MVM_SECRETS_PASSPHRASE or MVM_SECRETS_PASSPHRASE_FILE")
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("passphrase required set MVM_SECRETS_PASSPHRASE or MVM_SECRETS_PASSPHRASE_FILE")
	}
	fmt.Fprint(os.Stderr, "Secrets passphrase: ")
	pw, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", err
	}
	if len(pw) == 0 {
		return "", fmt.Errorf("empty passphrase")
	}
	return string(pw), nil
}

// loadIdentityPEM loads the age identity PEM bytes using plain, TPM, or passphrase.
func loadIdentityPEM(paths StorePaths, passphrase string) ([]byte, error) {
	if data, err := readStoreFile(paths.Dir, "identity.txt"); err == nil {
		return data, nil
	} else if !os.IsNotExist(err) {
		return nil, err
	}

	if _, err := os.Stat(paths.identityTPMPath()); err == nil {
		plain, err := tpmUnsealFile(paths.Dir, "identity.tpm")
		if err == nil {
			return plain, nil
		}
		// Fall through to passphrase backup when TPM unseal fails.
		if _, ageErr := os.Stat(paths.identityAgePath()); ageErr != nil {
			return nil, fmt.Errorf("tpm unseal failed: %w", err)
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}

	if data, err := readStoreFile(paths.Dir, "identity.txt.age"); err == nil {
		pw := passphrase
		if pw == "" {
			var err error
			pw, err = ResolvePassphrase("", true)
			if err != nil {
				return nil, err
			}
		}
		return unwrapIdentityPassphrase(data, pw)
	} else if !os.IsNotExist(err) {
		return nil, err
	}

	return nil, fmt.Errorf("no identity found under %s (run mvmsec init)", paths.Dir)
}

func storeExists(paths StorePaths) bool {
	for _, p := range []string{paths.Identity, paths.identityAgePath(), paths.identityTPMPath(), paths.VaultAge, paths.IdentityPub} {
		if _, err := os.Stat(p); err == nil {
			return true
		}
	}
	return false
}
