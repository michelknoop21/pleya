package backup

import (
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"io"
	"strings"
	"testing"
)

func TestValidateDumpPreservesReadErrorsAndCancellation(t *testing.T) {
	sourceErr := errors.New("synthetische leesfout")
	if err := validateDump(context.Background(), failingDumpReader{sourceErr}); !errors.Is(err, sourceErr) || !errors.Is(err, ErrNotRestorable) {
		t.Fatalf("leesfout niet behouden: %v", err)
	}
	var dump bytes.Buffer
	zw := gzip.NewWriter(&dump)
	if _, err := io.Copy(zw, strings.NewReader(strings.Repeat("SELECT 1;\n", 100000))); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if err := validateDump(ctx, cancellingDumpReader{r: bytes.NewReader(dump.Bytes()), cancel: cancel}); !errors.Is(err, context.Canceled) {
		t.Fatalf("annulering tijdens het lezen genegeerd: %v", err)
	}
	if err := validateDump(context.Background(), bytes.NewReader(dump.Bytes())); err != nil {
		t.Fatalf("geldige gzip geweigerd: %v", err)
	}
}

func TestValidateDumpRejectsAnEmptyGzip(t *testing.T) {
	var dump bytes.Buffer
	if err := gzip.NewWriter(&dump).Close(); err != nil {
		t.Fatal(err)
	}
	if err := validateDump(context.Background(), &dump); !errors.Is(err, ErrNotRestorable) {
		t.Fatalf("lege dump toegelaten: %v", err)
	}
}

type failingDumpReader struct{ err error }

func (r failingDumpReader) Read([]byte) (int, error) { return 0, r.err }

type cancellingDumpReader struct {
	r      io.Reader
	cancel context.CancelFunc
}

func (r cancellingDumpReader) Read(p []byte) (int, error) {
	n, err := r.r.Read(p)
	r.cancel()
	return n, err
}
