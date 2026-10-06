package files

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Store keeps file bytes. LocalStore is the only implementation today; an S3-style store
// only needs these three methods.
type Store interface {
	Put(key string, r io.Reader) error
	Open(key string) (io.ReadSeekCloser, error)
	Delete(key string) error
}

type LocalStore struct{ root string }

func NewLocalStore(root string) (*LocalStore, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	return &LocalStore{root: abs}, os.MkdirAll(abs, 0o750)
}

// path maps a key to a file under root, refusing anything that escapes it.
func (s *LocalStore) path(key string) (string, error) {
	p := filepath.Join(s.root, filepath.FromSlash(key))
	if key == "" || !strings.HasPrefix(p, s.root+string(filepath.Separator)) {
		return "", errors.New("invalid storage key")
	}
	return p, nil
}

func (s *LocalStore) Put(key string, r io.Reader) error {
	p, err := s.path(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	tmp := p + ".part"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, r); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, p)
}

func (s *LocalStore) Open(key string) (io.ReadSeekCloser, error) {
	p, err := s.path(key)
	if err != nil {
		return nil, err
	}
	return os.Open(p)
}

func (s *LocalStore) Delete(key string) error {
	p, err := s.path(key)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}
