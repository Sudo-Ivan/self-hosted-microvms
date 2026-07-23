package main

import (
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/term"
)

var errNotExists = fmt.Errorf("no secrets for instance")

func usage() {
	fmt.Fprintf(os.Stderr, `Usage:
  mvmsec init [--force] [--passphrase] [--tpm] [--no-tpm] [--shared-dir DIR]
  mvmsec protect status [--shared-dir DIR]
  mvmsec set <instance> KEY=VALUE... [--env-file FILE] [--shared-dir DIR]
  mvmsec unset <instance> KEY [--shared-dir DIR]
  mvmsec list [instance] [--shared-dir DIR]
  mvmsec exists <instance> [--shared-dir DIR]
  mvmsec export-mmds <instance> [--shared-dir DIR]

Identity protection:
  --passphrase   wrap age identity with a passphrase (prompt or env)
  --tpm          require TPM seal (fails if no usable TPM)
  --no-tpm       never use TPM (default is try TPM when present)

Passphrase unlock (non-interactive):
  MVM_SECRETS_PASSPHRASE
  MVM_SECRETS_PASSPHRASE_FILE

Encrypted host vault for microVM secrets. Values are never printed by list.
`)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		if err == errNotExists {
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		usage()
		return fmt.Errorf("command required")
	}
	cmd := args[0]
	rest := args[1:]
	sharedDir, rest, err := takeFlag(rest, "--shared-dir")
	if err != nil {
		return err
	}
	passFile, rest, err := takeFlag(rest, "--passphrase-file")
	if err != nil {
		return err
	}
	if sharedDir == "" {
		sharedDir = os.Getenv("MVM_SHARED_DIR")
	}
	if sharedDir == "" {
		sharedDir = defaultSharedDir()
	}
	paths := DefaultStorePaths(sharedDir)

	loadVault := func() (*Vault, error) {
		pw := ""
		meta, _ := ProtectStatus(paths)
		if meta.Passphrase && !meta.TPM {
			var err error
			pw, err = ResolvePassphrase(passFile, true)
			if err != nil {
				return nil, err
			}
		} else if meta.Passphrase {
			// TPM preferred. Passphrase only needed as fallback inside loadIdentityPEM.
			pw, _ = ResolvePassphrase(passFile, false)
		}
		return LoadVaultWithPassphrase(paths, pw)
	}

	switch cmd {
	case "init":
		opts := ProtectOpts{TryTPM: true}
		wantPass := false
		for _, a := range rest {
			switch a {
			case "--force":
				// handled below via force var
			case "--passphrase":
				wantPass = true
			case "--tpm":
				opts.RequireTPM = true
				opts.TryTPM = true
				opts.NoTPM = false
			case "--no-tpm":
				opts.NoTPM = true
				opts.TryTPM = false
				opts.RequireTPM = false
			default:
				return fmt.Errorf("unknown init argument %s", a)
			}
		}
		force := false
		for _, a := range rest {
			if a == "--force" {
				force = true
			}
		}
		if wantPass {
			pw, err := ResolvePassphrase(passFile, true)
			if err != nil {
				return err
			}
			if needsPassphraseConfirm() {
				fmt.Fprint(os.Stderr, "Confirm passphrase: ")
				pw2, err := readTTYPassword()
				fmt.Fprintln(os.Stderr)
				if err != nil {
					return err
				}
				if pw2 != pw {
					return fmt.Errorf("passphrases do not match")
				}
			}
			opts.Passphrase = pw
		}
		if err := InitStoreWithProtect(paths, force, opts); err != nil {
			return err
		}
		meta, _ := ProtectStatus(paths)
		fmt.Fprintf(os.Stderr, "initialized secrets store under %s (mode=%s)\n", paths.Dir, meta.Mode)
		return nil

	case "protect":
		sub := ""
		if len(rest) > 0 {
			sub = rest[0]
		}
		switch sub {
		case "status", "":
			meta, err := ProtectStatus(paths)
			if err != nil {
				return err
			}
			fmt.Printf("mode=%s\n", meta.Mode)
			fmt.Printf("passphrase=%v\n", meta.Passphrase)
			fmt.Printf("tpm=%v\n", meta.TPM)
			if meta.TPMPath != "" {
				fmt.Printf("tpm_path=%s\n", meta.TPMPath)
			}
			fmt.Printf("tpm_available=%v\n", TPMAvailable())
			return nil
		default:
			return fmt.Errorf("usage: mvmsec protect status")
		}

	case "set":
		if len(rest) < 1 {
			return fmt.Errorf("usage: mvmsec set <instance> KEY=VALUE... [--env-file FILE]")
		}
		instance := rest[0]
		rest = rest[1:]
		envFile, rest, err := takeFlag(rest, "--env-file")
		if err != nil {
			return err
		}
		kv := map[string]string{}
		if envFile != "" {
			f, err := openOperatorFile(envFile)
			if err != nil {
				return err
			}
			parsed, err := ParseEnvFile(f)
			_ = f.Close()
			if err != nil {
				return err
			}
			maps.Copy(kv, parsed)
		}
		fromArgs, err := ParseKVArgs(rest)
		if err != nil {
			return err
		}
		maps.Copy(kv, fromArgs)
		v, err := loadVault()
		if err != nil {
			return err
		}
		if err := SetKeys(v, instance, kv); err != nil {
			return err
		}
		return SaveVault(paths, v)

	case "unset":
		if len(rest) != 2 {
			return fmt.Errorf("usage: mvmsec unset <instance> KEY")
		}
		v, err := loadVault()
		if err != nil {
			return err
		}
		if err := UnsetKey(v, rest[0], rest[1]); err != nil {
			return err
		}
		return SaveVault(paths, v)

	case "list":
		v, err := loadVault()
		if err != nil {
			return err
		}
		if len(rest) == 0 {
			for _, name := range ListInstances(v) {
				keys, _ := InstanceKeys(v, name)
				fmt.Printf("%s (%d keys)\n", name, len(keys))
			}
			return nil
		}
		if len(rest) != 1 {
			return fmt.Errorf("usage: mvmsec list [instance]")
		}
		keys, err := InstanceKeys(v, rest[0])
		if err != nil {
			return err
		}
		for _, k := range keys {
			fmt.Println(k)
		}
		return nil

	case "exists":
		if len(rest) != 1 {
			return fmt.Errorf("usage: mvmsec exists <instance>")
		}
		v, err := loadVault()
		if err != nil {
			return err
		}
		if !HasSecrets(v, rest[0]) {
			return errNotExists
		}
		return nil

	case "export-mmds":
		if len(rest) != 1 {
			return fmt.Errorf("usage: mvmsec export-mmds <instance>")
		}
		v, err := loadVault()
		if err != nil {
			return err
		}
		out, err := ExportMMDS(v, rest[0])
		if err != nil {
			return err
		}
		fmt.Println(string(out))
		return nil

	case "-h", "--help", "help":
		usage()
		return nil

	default:
		usage()
		return fmt.Errorf("unknown command %s", cmd)
	}
}

func needsPassphraseConfirm() bool {
	return os.Getenv("MVM_SECRETS_PASSPHRASE") == "" && os.Getenv("MVM_SECRETS_PASSPHRASE_FILE") == ""
}

func readTTYPassword() (string, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("stdin is not a terminal")
	}
	pw, err := term.ReadPassword(int(os.Stdin.Fd()))
	if err != nil {
		return "", err
	}
	if len(pw) == 0 {
		return "", fmt.Errorf("empty passphrase")
	}
	return string(pw), nil
}

func takeFlag(args []string, name string) (string, []string, error) {
	out := make([]string, 0, len(args))
	val := ""
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == name {
			if i+1 >= len(args) {
				return "", nil, fmt.Errorf("%s needs a value", name)
			}
			val = args[i+1]
			i++
			continue
		}
		if after, ok := strings.CutPrefix(a, name+"="); ok {
			val = after
			continue
		}
		out = append(out, a)
	}
	return val, out, nil
}

func defaultSharedDir() string {
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		if filepath.Base(dir) == ".tools" {
			return filepath.Join(filepath.Dir(dir), "shared")
		}
	}
	wd, err := os.Getwd()
	if err != nil {
		return "shared"
	}
	return filepath.Join(wd, "shared")
}
