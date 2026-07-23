package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// readStoreFile reads name under the secrets directory using a rooted filesystem.
func readStoreFile(dir, name string) ([]byte, error) {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	f, err := root.Open(filepath.Base(name))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

// writeStoreFile writes name under the secrets directory with mode 0600.
func writeStoreFile(dir, name string, data []byte) error {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer root.Close()
	f, err := root.OpenFile(filepath.Base(name), os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	_, werr := f.Write(data)
	cerr := f.Close()
	if werr != nil {
		return werr
	}
	return cerr
}

// openOperatorFile opens a path chosen by the operator (CLI flag or env).
func openOperatorFile(path string) (*os.File, error) {
	clean := filepath.Clean(path)
	abs, err := filepath.Abs(clean)
	if err != nil {
		return nil, err
	}
	if abs != filepath.Clean(abs) {
		return nil, fmt.Errorf("invalid path")
	}
	// Operator-supplied path from --env-file / passphrase file / env.
	return os.Open(abs) // #nosec G304,G703 -- intentional operator path
}

// readOperatorFile reads a path chosen by the operator (CLI flag or env).
func readOperatorFile(path string) ([]byte, error) {
	f, err := openOperatorFile(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}
