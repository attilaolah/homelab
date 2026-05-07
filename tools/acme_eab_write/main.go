package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/pkg/errors"
	"github.com/smallstep/nosql"
)

var (
	externalAccountKeyTable                   = []byte("acme_external_account_keys")
	externalAccountKeyIDsByReferenceTable     = []byte("acme_external_account_keyID_reference_index")
	externalAccountKeyIDsByProvisionerIDTable = []byte("acme_external_account_keyID_provisionerID_index")
)

type externalAccountKey struct {
	ID            string    `json:"id"`
	ProvisionerID string    `json:"provisionerID"`
	Reference     string    `json:"reference"`
	AccountID     string    `json:"accountID,omitempty"`
	HmacKey       []byte    `json:"key"`
	CreatedAt     time.Time `json:"createdAt"`
	BoundAt       time.Time `json:"boundAt"`
}

type externalAccountKeyReference struct {
	Reference            string `json:"reference"`
	ExternalAccountKeyID string `json:"externalAccountKeyID"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "acme-eab-write: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		dbPath        string
		hmacKey       string
		kid           string
		provisionerID string
		reference     string
	)

	flag.StringVar(&dbPath, "db", "", "path to the Step CA Badger DB")
	flag.StringVar(&hmacKey, "hmac-key", "", "base64url-encoded ACME EAB HMAC key")
	flag.StringVar(&kid, "kid", "", "ACME EAB key ID")
	flag.StringVar(&provisionerID, "provisioner-id", "", "ACME provisioner ID")
	flag.StringVar(&reference, "reference", "", "human-readable EAB reference")
	flag.Parse()

	if dbPath == "" {
		return errors.New("--db is required")
	}
	if hmacKey == "" {
		return errors.New("--hmac-key is required")
	}
	if kid == "" {
		return errors.New("--kid is required")
	}

	rawHmacKey, err := base64.RawURLEncoding.DecodeString(hmacKey)
	if err != nil {
		return errors.Wrap(err, "decoding --hmac-key")
	}

	db, err := nosql.New("badgerv2", dbPath)
	if err != nil {
		return errors.Wrap(err, "opening DB")
	}
	defer db.Close()

	for _, table := range [][]byte{
		externalAccountKeyTable,
		externalAccountKeyIDsByReferenceTable,
		externalAccountKeyIDsByProvisionerIDTable,
	} {
		if err := db.CreateTable(table); err != nil {
			return errors.Wrapf(err, "creating table %s", table)
		}
	}

	key := &externalAccountKey{
		ID:            kid,
		ProvisionerID: provisionerID,
		Reference:     reference,
		HmacKey:       rawHmacKey,
		CreatedAt:     time.Now().UTC().Truncate(time.Second),
	}
	if err := createJSON(db, externalAccountKeyTable, kid, key); err != nil {
		return err
	}

	if err := addProvisionerIndex(db, provisionerID, kid); err != nil {
		return err
	}

	if reference != "" {
		ref := &externalAccountKeyReference{
			Reference:            reference,
			ExternalAccountKeyID: kid,
		}
		if err := createJSON(db, externalAccountKeyIDsByReferenceTable, referenceKey(provisionerID, reference), ref); err != nil {
			return err
		}
	}

	return nil
}

func createJSON(db nosql.DB, table []byte, key string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return errors.Wrap(err, "marshaling value")
	}

	_, swapped, err := db.CmpAndSwap(table, []byte(key), nil, data)
	switch {
	case err != nil:
		return errors.Wrapf(err, "writing %s/%s", table, key)
	case !swapped:
		return errors.Errorf("%s/%s already exists", table, key)
	default:
		return nil
	}
}

func addProvisionerIndex(db nosql.DB, provisionerID string, kid string) error {
	var oldIDs []string
	oldRaw, err := db.Get(externalAccountKeyIDsByProvisionerIDTable, []byte(provisionerID))
	if err == nil {
		if err := json.Unmarshal(oldRaw, &oldIDs); err != nil {
			return errors.Wrap(err, "unmarshaling provisioner index")
		}
	} else if !nosql.IsErrNotFound(err) {
		return errors.Wrap(err, "reading provisioner index")
	}

	for _, id := range oldIDs {
		if id == kid {
			return errors.Errorf("provisioner index already contains %s", kid)
		}
	}

	newIDs := append(append([]string{}, oldIDs...), kid)
	newRaw, err := json.Marshal(newIDs)
	if err != nil {
		return errors.Wrap(err, "marshaling provisioner index")
	}

	var expected []byte
	if len(oldIDs) > 0 {
		expected = oldRaw
	}

	_, swapped, err := db.CmpAndSwap(externalAccountKeyIDsByProvisionerIDTable, []byte(provisionerID), expected, newRaw)
	switch {
	case err != nil:
		return errors.Wrap(err, "writing provisioner index")
	case !swapped:
		return errors.New("provisioner index changed while writing")
	default:
		return nil
	}
}

func referenceKey(provisionerID string, reference string) string {
	return provisionerID + "." + reference
}
