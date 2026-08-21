package fileid

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestWeakETagHasTheWeakForm: de W/ ervoor is geen opsmuk maar de reden dat een
// client er geen deelantwoord op mag vragen (RFC 9110 §13.1.5).
func TestWeakETagHasTheWeakForm(t *testing.T) {
	tag := Stat{Dev: 1, Ino: 2, Size: 3, MtimeNs: 4, CtimeNs: 5}.WeakETag(1)
	if !strings.HasPrefix(tag, `W/"`) || !strings.HasSuffix(tag, `"`) {
		t.Fatalf("validator is %q", tag)
	}
	if strings.Contains(tag, "1:2:3") {
		t.Fatal("de tupel staat leesbaar in de header; inodes horen niet naar buiten")
	}
}

// TestWeakETagChangesWithEveryInput: elk veld van de tupel telt mee, anders
// draagt de validator minder informatie dan hij belooft.
func TestWeakETagChangesWithEveryInput(t *testing.T) {
	base := Stat{Dev: 1, Ino: 2, Size: 3, MtimeNs: 4, CtimeNs: 5}
	reference := base.WeakETag(1)

	variants := map[string]struct {
		stat Stat
		gen  int64
	}{
		"andere dev":        {Stat{Dev: 9, Ino: 2, Size: 3, MtimeNs: 4, CtimeNs: 5}, 1},
		"andere inode":      {Stat{Dev: 1, Ino: 9, Size: 3, MtimeNs: 4, CtimeNs: 5}, 1},
		"andere grootte":    {Stat{Dev: 1, Ino: 2, Size: 9, MtimeNs: 4, CtimeNs: 5}, 1},
		"andere mtime":      {Stat{Dev: 1, Ino: 2, Size: 3, MtimeNs: 9, CtimeNs: 5}, 1},
		"andere ctime":      {Stat{Dev: 1, Ino: 2, Size: 3, MtimeNs: 4, CtimeNs: 9}, 1},
		"andere generation": {base, 2},
	}
	for name, v := range variants {
		if got := v.stat.WeakETag(v.gen); got == reference {
			t.Errorf("%s leverde dezelfde validator", name)
		}
	}
}

// TestOfReadsARealFile bewijst dat de tupel van schijf komt en niet uit een
// veronderstelling. De grootte en de mtime zijn overal te lezen; dev, inode en
// ctime hangen aan het platform en mogen nul zijn.
func TestOfReadsARealFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "media.mkv")
	if err := os.WriteFile(path, []byte("twaalf bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}

	st := Of(info)
	if st.Size != 12 {
		t.Fatalf("grootte is %d", st.Size)
	}
	if st.MtimeNs != info.ModTime().UnixNano() {
		t.Fatalf("mtime is %d", st.MtimeNs)
	}

	before := st.WeakETag(1)

	// Andere inhoud met een andere lengte, en een mtime die vooruit gaat.
	if err := os.WriteFile(path, []byte("een heel andere inhoud"), 0o644); err != nil {
		t.Fatal(err)
	}
	stamp := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(path, stamp, stamp); err != nil {
		t.Fatal(err)
	}
	info, err = os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if after := Of(info).WeakETag(1); after == before {
		t.Fatal("de validator bewoog niet mee met de bytes")
	}
}
