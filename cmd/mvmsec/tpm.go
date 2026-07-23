package main

import (
	"fmt"
	"os"

	"github.com/google/go-tpm-tools/client"
	pb "github.com/google/go-tpm-tools/proto/tpm"
	"github.com/google/go-tpm/legacy/tpm2"
	"google.golang.org/protobuf/proto"
)

// TPMDevicePath returns the preferred TPM character device, or empty.
func TPMDevicePath() string {
	for _, p := range []string{"/dev/tpmrm0", "/dev/tpm0"} {
		if st, err := os.Stat(p); err == nil && (st.Mode()&os.ModeCharDevice) != 0 {
			return p
		}
	}
	return ""
}

// TPMAvailable reports whether a usable TPM device node exists.
func TPMAvailable() bool {
	return TPMDevicePath() != ""
}

func tpmSeal(plaintext []byte) (blob []byte, tpmPath string, err error) {
	path := TPMDevicePath()
	if path == "" {
		return nil, "", fmt.Errorf("no TPM device found")
	}
	rwc, err := tpm2.OpenTPM(path)
	if err != nil {
		return nil, path, fmt.Errorf("open TPM %s: %w", path, err)
	}
	defer rwc.Close()

	srk, err := client.StorageRootKeyECC(rwc)
	if err != nil {
		srk, err = client.StorageRootKeyRSA(rwc)
		if err != nil {
			return nil, path, fmt.Errorf("create SRK: %w", err)
		}
	}
	defer srk.Close()

	// Seal to this TPM only. No PCR binding so reboot still unseals.
	sealed, err := srk.Seal(plaintext, client.SealOpts{})
	if err != nil {
		return nil, path, fmt.Errorf("tpm seal: %w", err)
	}
	out, err := proto.Marshal(sealed)
	if err != nil {
		return nil, path, err
	}
	return out, path, nil
}

func tpmUnsealFile(dir, name string) ([]byte, error) {
	data, err := readStoreFile(dir, name)
	if err != nil {
		return nil, err
	}
	return tpmUnseal(data)
}

func tpmUnseal(blob []byte) ([]byte, error) {
	path := TPMDevicePath()
	if path == "" {
		return nil, fmt.Errorf("no TPM device found")
	}
	var sealed pb.SealedBytes
	if err := proto.Unmarshal(blob, &sealed); err != nil {
		return nil, fmt.Errorf("parse tpm blob: %w", err)
	}
	rwc, err := tpm2.OpenTPM(path)
	if err != nil {
		return nil, fmt.Errorf("open TPM %s: %w", path, err)
	}
	defer rwc.Close()

	var srk *client.Key
	switch sealed.GetSrk() {
	case pb.ObjectType_ECC:
		srk, err = client.StorageRootKeyECC(rwc)
	case pb.ObjectType_RSA:
		srk, err = client.StorageRootKeyRSA(rwc)
	default:
		srk, err = client.StorageRootKeyECC(rwc)
		if err != nil {
			srk, err = client.StorageRootKeyRSA(rwc)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("create SRK: %w", err)
	}
	defer srk.Close()

	plain, err := srk.Unseal(&sealed, client.UnsealOpts{})
	if err != nil {
		return nil, fmt.Errorf("tpm unseal: %w", err)
	}
	return plain, nil
}
