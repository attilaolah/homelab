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
		replace       bool
	)

	flag.StringVar(&dbPath, "db", "", "path to the Step CA Badger DB")
	flag.StringVar(&hmacKey, "hmac-key", "", "base64url-encoded ACME EAB HMAC key")
	flag.StringVar(&kid, "kid", "", "ACME EAB key ID")
	flag.StringVar(&provisionerID, "provisioner-id", "", "ACME provisioner ID")
	flag.StringVar(&reference, "reference", "", "human-readable EAB reference")
	flag.BoolVar(&replace, "replace", false, "replace any existing EAB key for the same provisioner/reference")
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

	if replace && reference != "" {
		if err := replaceReference(db, provisionerID, reference); err != nil {
			return err
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

func replaceReference(db nosql.DB, provisionerID string, reference string) error {
	refRaw, err := db.Get(externalAccountKeyIDsByReferenceTable, []byte(referenceKey(provisionerID, reference)))
	if nosql.IsErrNotFound(err) {
		return nil
	}
	if err != nil {
		return errors.Wrap(err, "reading existing reference")
	}

	var ref externalAccountKeyReference
	if err := json.Unmarshal(refRaw, &ref); err != nil {
		return errors.Wrap(err, "unmarshaling existing reference")
	}

	keyRaw, err := db.Get(externalAccountKeyTable, []byte(ref.ExternalAccountKeyID))
	if nosql.IsErrNotFound(err) {
		return deleteReference(db, provisionerID, reference)
	}
	if err != nil {
		return errors.Wrap(err, "reading existing key")
	}

	var key externalAccountKey
	if err := json.Unmarshal(keyRaw, &key); err != nil {
		return errors.Wrap(err, "unmarshaling existing key")
	}
	if key.ProvisionerID != provisionerID {
		return errors.New("existing key has a different provisioner")
	}

	if key.Reference != "" {
		if err := deleteReference(db, provisionerID, key.Reference); err != nil {
			return err
		}
	}
	if err := deleteKey(db, key.ID); err != nil {
		return err
	}
	if err := removeProvisionerIndex(db, provisionerID, key.ID); err != nil {
		return err
	}

	return nil
}

func deleteReference(db nosql.DB, provisionerID string, reference string) error {
	err := db.Del(externalAccountKeyIDsByReferenceTable, []byte(referenceKey(provisionerID, reference)))
	if nosql.IsErrNotFound(err) {
		return nil
	}
	return errors.Wrap(err, "deleting existing reference")
}

func deleteKey(db nosql.DB, kid string) error {
	err := db.Del(externalAccountKeyTable, []byte(kid))
	if nosql.IsErrNotFound(err) {
		return nil
	}
	return errors.Wrap(err, "deleting existing key")
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

func removeProvisionerIndex(db nosql.DB, provisionerID string, kid string) error {
	var oldIDs []string
	oldRaw, err := db.Get(externalAccountKeyIDsByProvisionerIDTable, []byte(provisionerID))
	if nosql.IsErrNotFound(err) {
		return nil
	}
	if err != nil {
		return errors.Wrap(err, "reading provisioner index")
	}
	if err := json.Unmarshal(oldRaw, &oldIDs); err != nil {
		return errors.Wrap(err, "unmarshaling provisioner index")
	}

	newIDs := make([]string, 0, len(oldIDs))
	for _, id := range oldIDs {
		if id != kid {
			newIDs = append(newIDs, id)
		}
	}

	if len(newIDs) == len(oldIDs) {
		return nil
	}

	newRaw, err := json.Marshal(newIDs)
	if err != nil {
		return errors.Wrap(err, "marshaling provisioner index")
	}

	_, swapped, err := db.CmpAndSwap(externalAccountKeyIDsByProvisionerIDTable, []byte(provisionerID), oldRaw, newRaw)
	switch {
	case err != nil:
		return errors.Wrap(err, "writing provisioner index")
	case !swapped:
		return errors.New("provisioner index changed while writing")
	default:
		return nil
	}
}

func addProvisionerIndex(db nosql.DB, provisionerID string, kid string) error {
	if provisionerID == "" {
		return nil
	}

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
