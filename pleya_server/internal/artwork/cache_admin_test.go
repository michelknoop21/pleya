//go:build linux || darwin || freebsd || netbsd || openbsd || dragonfly

package artwork

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"image"
	"image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

const cacheTestName = cacheTestKey + "_480.jpg"

func cacheFixture(t *testing.T) *Resizer {
	t.Helper()
	r := New("", t.TempDir(), quiet())
	if err := os.MkdirAll(r.dir, 0755); err != nil {
		t.Fatal(err)
	}
	return r
}

func TestCacheStatsOnlyExactRegularLadderArtifacts(t *testing.T) {
	r := cacheFixture(t)
	for _, name := range []string{cacheTestName, ".incoming-123.jpg", "original.jpg", cacheTestKey + "_481.jpg", cacheTestKey + "_0480.jpg", "abc_1_480.jpg", cacheTestKey + "_480.png"} {
		if err := os.WriteFile(filepath.Join(r.dir, name), []byte("abc"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(filepath.Join(r.dir, cacheTestKey+"_960.jpg"), 0755); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "source.jpg")
	if err := os.WriteFile(outside, []byte("outside"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(r.dir, cacheTestKey+"_240.jpg")); err != nil {
		t.Fatal(err)
	}
	bytes, files, err := r.Stats()
	if err != nil || bytes != 3 || files != 1 {
		t.Fatalf("Stats = %d/%d/%v; verwacht uitsluitend 3/1", bytes, files, err)
	}
}

func TestCachePurgePreservesIncomingUnknownAndSources(t *testing.T) {
	r := cacheFixture(t)
	for _, name := range []string{cacheTestName, ".incoming-active.jpg", "original.jpg", cacheTestKey + "_481.jpg"} {
		if err := os.WriteFile(filepath.Join(r.dir, name), []byte("bewaar"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	outside := filepath.Join(t.TempDir(), "source.jpg")
	if err := os.WriteFile(outside, []byte("source"), 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(r.dir, cacheTestKey+"_240.jpg")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	if err := r.Purge(); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{filepath.Join(r.dir, ".incoming-active.jpg"), filepath.Join(r.dir, "original.jpg"), filepath.Join(r.dir, cacheTestKey+"_481.jpg"), link, outside} {
		if _, err := os.Lstat(path); err != nil {
			t.Errorf("behouden bestand ontbreekt: %s: %v", path, err)
		}
	}
	if _, err := os.Stat(filepath.Join(r.dir, cacheTestName)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("ladder niet verwijderd: %v", err)
	}
}

func TestCacheDirectorySymlinkCannotReachSource(t *testing.T) {
	r := cacheFixture(t)
	outside := t.TempDir()
	path := filepath.Join(outside, cacheTestName)
	if err := os.WriteFile(path, []byte("source"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(r.dir); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, r.dir); err != nil {
		t.Fatal(err)
	}
	if _, _, err := r.Stats(); err == nil {
		t.Error("Stats accepteerde symlink-cachemap")
	}
	if err := r.Purge(); err == nil {
		t.Error("Purge accepteerde symlink-cachemap")
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "source" {
		t.Fatalf("bron geraakt: %q %v", got, err)
	}
}

func TestCachePurgeWaitsForActiveRender(t *testing.T) {
	r := newResizer(t)
	src := filepath.Join(t.TempDir(), "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	control := t.TempDir()
	ready, release := filepath.Join(control, "ready"), filepath.Join(control, "release")
	wrapper := filepath.Join(control, "ffmpeg")
	script := "#!/bin/sh\ntouch '" + ready + "'\nwhile ! test -f '" + release + "'; do sleep .01; done\nexec ffmpeg \"$@\"\n"
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	r.ffmpeg = wrapper
	made := make(chan bool, 1)
	go func() { _, ok := r.Make(context.Background(), src, cacheTestKey, 480); made <- ok }()
	deadline := time.After(5 * time.Second)
	for {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		select {
		case <-deadline:
			t.Fatal("render startte niet")
		case <-time.After(5 * time.Millisecond):
		}
	}
	purged := make(chan error, 1)
	go func() { purged <- r.Purge() }()
	early := false
	select {
	case err := <-purged:
		early = true
		t.Errorf("Purge keerde terug tijdens actieve render: %v", err)
	case <-time.After(75 * time.Millisecond):
	}
	if err := os.WriteFile(release, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if !<-made {
		t.Error("actieve render kapotgemaakt")
	}
	if !early {
		select {
		case err := <-purged:
			if err != nil {
				t.Error(err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("purge bleef wachten")
		}
	}
	if _, files, err := r.Stats(); err != nil || files != 0 {
		t.Errorf("stale publicatie na purge: %d %v", files, err)
	}
}

func TestCacheOpenDescriptorSurvivesPurgeAndRebuilds(t *testing.T) {
	r := newResizer(t)
	src := filepath.Join(t.TempDir(), "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	f, err := r.Open(context.Background(), src, cacheTestKey, 480)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	before, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	if err := r.PurgeContext(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, files, err := r.Stats(); err != nil || files != 0 {
		t.Fatalf("purge niet klaar: %d %v", files, err)
	}
	f.Seek(0, 0)
	after, err := io.ReadAll(f)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("open response beschadigd: %v", err)
	}
	rebuilt, err := r.Open(context.Background(), src, cacheTestKey, 480)
	if err != nil {
		t.Fatal(err)
	}
	defer rebuilt.Close()
	got, err := io.ReadAll(rebuilt)
	if err != nil || !bytes.Equal(before, got) {
		t.Fatalf("nieuwe trede niet identiek: %v", err)
	}
}

func TestCacheWarmOpenDoesNotWaitForTwoColdRenders(t *testing.T) {
	r := newResizer(t)
	dir := t.TempDir()
	release := filepath.Join(dir, "release")
	wrapper := filepath.Join(dir, "ffmpeg")
	script := "#!/bin/sh\nprev=''\nfor arg do\n if test \"$prev\" = '-i'; then touch \"$arg.started\"; fi\n prev=\"$arg\"\ndone\nwhile ! test -f '" + release + "'; do sleep .01; done\nexec ffmpeg \"$@\"\n"
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	r.ffmpeg = wrapper
	if err := os.MkdirAll(r.dir, 0755); err != nil {
		t.Fatal(err)
	}
	testsupport.MakeImage(t, filepath.Join(r.dir, cacheTestName), 480, 720)
	done := make(chan error, 3)
	for i := 2; i <= 4; i++ {
		src := filepath.Join(dir, fmt.Sprintf("source%d.jpg", i))
		testsupport.MakeImage(t, src, 1200, 1800)
		key := fmt.Sprintf("019a0000-0000-7000-8000-%012d_1", i)
		go func() {
			f, err := r.Open(context.Background(), src, key, 480)
			if f != nil {
				f.Close()
			}
			done <- err
		}()
	}
	deadline := time.After(5 * time.Second)
	for {
		entries, _ := filepath.Glob(filepath.Join(dir, "*.started"))
		if len(entries) == 2 {
			break
		}
		select {
		case <-deadline:
			t.Fatal("twee echte renders startten niet")
		case <-time.After(5 * time.Millisecond):
		}
	}
	time.Sleep(50 * time.Millisecond)
	entries, _ := filepath.Glob(filepath.Join(dir, "*.started"))
	if len(entries) != 2 {
		t.Fatalf("max2 cold: %d", len(entries))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 250*time.Millisecond)
	warm, err := r.Open(ctx, "unused", cacheTestKey, 480)
	cancel()
	if err != nil {
		t.Errorf("warme lezer wacht achter cold2: %v", err)
	} else {
		warm.Close()
	}
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Millisecond)
	err = r.PurgeContext(ctx)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("purgewacht niet annuleerbaar: %v", err)
	}
	if err := os.WriteFile(release, nil, 0600); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if err := <-done; err != nil {
			t.Error(err)
		}
	}
	if err := r.Purge(); err != nil {
		t.Fatal(err)
	}
	if _, files, err := r.Stats(); err != nil || files != 0 {
		t.Errorf("oude publicatie na purge: %d %v", files, err)
	}
}

func TestCacheQueuedReadersCancelAndResumeAfterCancelledPurge(t *testing.T) {
	r := cacheFixture(t)
	if err := os.WriteFile(filepath.Join(r.dir, cacheTestName), []byte("warm"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := r.gate.acquire(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	purged := make(chan error, 1)
	go func() { purged <- r.PurgeContext(ctx) }()
	for {
		r.gate.mu.Lock()
		waiting := r.gate.waiting
		r.gate.mu.Unlock()
		if waiting > 0 {
			break
		}
		time.Sleep(time.Millisecond)
	}
	readerCtx, readerCancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	_, err := r.Open(readerCtx, "unused", cacheTestKey, 480)
	readerCancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("queued reader niet geannuleerd: %v", err)
	}
	cancel()
	if err := <-purged; !errors.Is(err, context.Canceled) {
		t.Errorf("purge annulering: %v", err)
	}
	f, err := r.Open(context.Background(), "unused", cacheTestKey, 480)
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
	r.gate.release(false)
}

func TestCacheFilesystemErrorsAreNotSuccess(t *testing.T) {
	if os.Getenv("PLEYA_CACHE_PERMISSION_CHILD") == "1" {
		r := New("", os.Getenv("PLEYA_CACHE_PERMISSION_ROOT"), quiet())
		if err := r.Purge(); !errors.Is(err, syscall.EPERM) {
			t.Fatalf("echte gedeeltelijke unlinkfout niet EPERM: %v", err)
		}
		if _, err := os.Stat(filepath.Join(r.dir, "019a0000-0000-7000-8000-000000000002_1_480.jpg")); err != nil {
			t.Fatalf("beschermd bestand geraakt: %v", err)
		}
		// Een niet-leesbare echte directory mag geen nulstand opleveren.
		r.dir = filepath.Join(os.Getenv("PLEYA_CACHE_PERMISSION_ROOT"), "onleesbaar")
		if _, _, err := r.Stats(); !errors.Is(err, os.ErrPermission) {
			t.Fatalf("echte ReadDir-fout niet permission denied: %v", err)
		}
		return
	}
	root, err := os.MkdirTemp("", "pleya-cache-permissions-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(root)
	if err := os.Chmod(root, 0755); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "artwork-sizes")
	if err := os.Mkdir(dir, 0755); err != nil {
		t.Fatal(err)
	}
	removable := filepath.Join(dir, cacheTestName)
	if err := os.WriteFile(removable, []byte("derived"), 0600); err != nil {
		t.Fatal(err)
	}
	protected := filepath.Join(dir, "019a0000-0000-7000-8000-000000000002_1_480.jpg")
	if err := os.WriteFile(protected, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	unreadable := filepath.Join(root, "onleesbaar")
	if err := os.Mkdir(unreadable, 0000); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(unreadable, 0755)
	if os.Geteuid() != 0 {
		// Zonder root kan de fixture geen vreemde eigenaar maken. Weiger echte
		// unlinks via directoryrechten en behoud beide ladders onder de eigen uid.
		if err := os.Chmod(dir, 0555); err != nil {
			t.Fatal(err)
		}
		defer os.Chmod(dir, 0755)
		r := New("", root, quiet())
		if err := r.Purge(); !errors.Is(err, os.ErrPermission) {
			t.Fatalf("echte unlinkfout niet permission denied: %v", err)
		}
		r.dir = unreadable
		if _, _, err := r.Stats(); !errors.Is(err, os.ErrPermission) {
			t.Fatalf("echte ReadDir-fout niet permission denied: %v", err)
		}
		for path, want := range map[string]string{removable: "derived", protected: "keep"} {
			if got, err := os.ReadFile(path); err != nil || string(got) != want {
				t.Fatalf("ladder geraakt na geweigerde unlink: %q %v", got, err)
			}
		}
		return
	}
	// Sticky directory: uid65534 kan alleen zijn eigen ladder verwijderen.
	if err := os.Chmod(dir, os.ModeSticky|0777); err != nil {
		t.Fatal(err)
	}
	if err := os.Chown(removable, 65534, 65534); err != nil {
		t.Fatal(err)
	}
	executable := filepath.Join(root, "permission-test")
	binary, err := os.ReadFile(os.Args[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(executable, binary, 0755); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(executable, "-test.run=^TestCacheFilesystemErrorsAreNotSuccess$", "-test.v")
	command.Env = append(os.Environ(), "PLEYA_CACHE_PERMISSION_CHILD=1", "PLEYA_CACHE_PERMISSION_ROOT="+root)
	command.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 65534, Gid: 65534}}
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("permissionprobe: %v\n%s", err, output)
	}
	if _, err := os.Stat(removable); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("geen echte partial delete vóór fout: %v", err)
	}
	if got, err := os.ReadFile(protected); err != nil || string(got) != "keep" {
		t.Fatalf("beschermde ladder geraakt na partial delete: %q %v", got, err)
	}
}

func TestCacheRefusesDeclaredMediaConfigBackupOverlap(t *testing.T) {
	testsupport.HasFFmpeg(t)
	for _, kind := range []string{"media", "config", "backups"} {
		t.Run(kind, func(t *testing.T) {
			protected := filepath.Join(t.TempDir(), kind)
			cache := filepath.Join(protected, "configured-cache")
			r := New("ffmpeg", cache, quiet(), protected)
			if err := os.MkdirAll(r.dir, 0755); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(r.dir, cacheTestName)
			if err := os.WriteFile(path, []byte("user-data"), 0600); err != nil {
				t.Fatal(err)
			}
			if r.Available() {
				t.Error("overlappende cache belooft beschikbaarheid")
			}
			if _, _, err := r.Stats(); err == nil {
				t.Error("overlappende media/config/backups als cache geteld")
			}
			if err := r.Purge(); err == nil {
				t.Error("overlappende purge was succes")
			}
			if got, err := os.ReadFile(path); err != nil || string(got) != "user-data" {
				t.Fatalf("behouden bytes geraakt: %q %v", got, err)
			}
		})
	}
}

func TestCacheDirectorySwapDuringRealRenderStaysOnOpenedDirectory(t *testing.T) {
	r := newResizer(t)
	src := filepath.Join(t.TempDir(), "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	control := t.TempDir()
	ready, release := filepath.Join(control, "ready"), filepath.Join(control, "release")
	wrapper := filepath.Join(control, "ffmpeg")
	script := "#!/bin/sh\ntouch '" + ready + "'\nwhile ! test -f '" + release + "'; do sleep .01; done\nexec ffmpeg \"$@\"\n"
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	defer os.WriteFile(release, nil, 0600)
	r.ffmpeg = wrapper
	result := make(chan *os.File, 1)
	fail := make(chan error, 1)
	go func() {
		f, err := r.Open(context.Background(), src, cacheTestKey, 480)
		if err != nil {
			fail <- err
			return
		}
		result <- f
	}()
	deadline := time.After(5 * time.Second)
	for {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		select {
		case <-deadline:
			t.Fatal("render startte niet")
		case <-time.After(5 * time.Millisecond):
		}
	}
	original := r.dir + "-opened"
	if err := os.Rename(r.dir, original); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	protected := filepath.Join(outside, cacheTestName)
	if err := os.WriteFile(protected, []byte("bron"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, r.dir); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(release, nil, 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case f := <-result:
		defer f.Close()
		cfg, _, err := image.DecodeConfig(f)
		if err != nil || cfg.Width != 480 {
			t.Fatalf("open trede niet behouden: %v %v", cfg, err)
		}
	case err := <-fail:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("render bleef wachten")
	}
	if err := r.Purge(); err == nil {
		t.Fatal("swapped symlink werd geaccepteerd")
	}
	if got, err := os.ReadFile(protected); err != nil || string(got) != "bron" {
		t.Fatalf("bron geraakt %q %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(original, cacheTestName)); err != nil {
		t.Fatalf("render publiceerde niet onder geopende FD: %v", err)
	}
}

func TestCacheRealENOSPCCannotPublishOrReturnSuccess(t *testing.T) {
	root := os.Getenv("PLEYA_CACHE_ENOSPC_DIR")
	if root == "" {
		t.Skip("opt-in begrensde tmpfs; task cache-admin runner levert die")
	}
	testsupport.HasFFmpeg(t)
	r := New("ffmpeg", root, quiet())
	if err := os.MkdirAll(r.dir, 0755); err != nil {
		t.Fatal(err)
	}
	filler, err := os.Create(filepath.Join(root, "filler"))
	if err != nil {
		t.Fatal(err)
	}
	block := make([]byte, 64*1024)
	for {
		_, err = filler.Write(block)
		if err != nil {
			break
		}
	}
	filler.Close()
	if !errors.Is(err, syscall.ENOSPC) {
		t.Fatalf("geen echte ENOSPC: %v", err)
	}
	src := filepath.Join(t.TempDir(), "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	if f, err := r.Open(context.Background(), src, cacheTestKey, 480); err == nil {
		f.Close()
		t.Fatal("volle tmpfs leverde trede")
	}
	if _, files, err := r.Stats(); err != nil || files != 0 {
		t.Fatalf("ENOSPC liet publicatie achter: %d %v", files, err)
	}
	entries, err := os.ReadDir(r.dir)
	if err != nil || len(entries) > 1 {
		t.Fatalf("tempbestand achtergebleven: %v %v", entries, err)
	}
	// Een leeg vast lockslot is coördinatiemetadata, geen tijdelijke render of ladderpublicatie.
	for _, entry := range entries {
		info, err := entry.Info()
		if !strings.HasPrefix(entry.Name(), ".lock-") || err != nil || !info.Mode().IsRegular() || info.Size() != 0 {
			t.Fatalf("onverwacht bestand na ENOSPC: %s %v", entry.Name(), err)
		}
	}
}

func TestCacheRendererKeepsExistingJPEGBytesForTheSameValidator(t *testing.T) {
	for _, format := range []string{"jpeg", "png"} {
		t.Run(format, func(t *testing.T) {
			r := newResizer(t)
			dir := t.TempDir()
			src := filepath.Join(dir, "source.jpg")
			testsupport.MakeImage(t, src, 1200, 1800)
			if format == "png" {
				input, err := os.Open(src)
				if err != nil {
					t.Fatal(err)
				}
				img, _, err := image.Decode(input)
				input.Close()
				if err != nil {
					t.Fatal(err)
				}
				src = filepath.Join(dir, "source.png")
				output, err := os.Create(src)
				if err != nil {
					t.Fatal(err)
				}
				if err := png.Encode(output, img); err != nil {
					t.Fatal(err)
				}
				output.Close()
			}
			previous := filepath.Join(dir, "previous.jpg")
			cmd := exec.Command("ffmpeg", "-v", "error", "-y", "-i", src, "-vf", "scale=480:-2:flags=lanczos", "-frames:v", "1", "-q:v", "3", previous)
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("bestaande encoder: %v %s", err, output)
			}
			want, err := os.ReadFile(previous)
			if err != nil {
				t.Fatal(err)
			}
			opened, err := r.Open(t.Context(), src, cacheTestKey, 480)
			if err != nil {
				t.Fatal(err)
			}
			defer opened.Close()
			got, err := io.ReadAll(opened)
			if err != nil || !bytes.Equal(got, want) {
				t.Fatalf("dezelfde source/generation/trede kreeg andere JPEGbytes: %v", err)
			}
		})
	}
}

func TestCacheProtectedSymlinkAncestorCannotAliasTheRealCache(t *testing.T) {
	testsupport.HasFFmpeg(t)
	for _, kind := range []string{"media", "config", "backups"} {
		t.Run(kind, func(t *testing.T) {
			base := t.TempDir()
			realRoot := filepath.Join(base, "real")
			cache := filepath.Join(realRoot, "protected")
			if err := os.MkdirAll(filepath.Join(cache, "artwork-sizes"), 0755); err != nil {
				t.Fatal(err)
			}
			alias := filepath.Join(base, kind+"-link")
			if err := os.Symlink(realRoot, alias); err != nil {
				t.Fatal(err)
			}
			protected := filepath.Join(alias, "protected")
			file := filepath.Join(protected, "artwork-sizes", cacheTestName)
			if err := os.WriteFile(file, []byte("protected-source"), 0600); err != nil {
				t.Fatal(err)
			}
			// Alleen het beschermde pad bevat de bestaande alias, niet de cache.
			r := New("ffmpeg", cache, quiet(), protected)
			if r.CacheAdminAvailable() {
				t.Error("protected-ancestryalias activeerde purge")
			}
			if err := r.Purge(); err == nil {
				t.Error("purge via reële protected-aliasoverlap was succes")
			}
			if got, err := os.ReadFile(file); err != nil || string(got) != "protected-source" {
				t.Fatalf("beschermde bytes geraakt: %q %v", got, err)
			}
		})
	}
}

func TestCacheOfflineProtectedSuffixUnderExistingAliasRemainsUsable(t *testing.T) {
	testsupport.HasFFmpeg(t)
	base := t.TempDir()
	realRoot := filepath.Join(base, "real")
	if err := os.Mkdir(realRoot, 0755); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(base, "media-link")
	if err := os.Symlink(realRoot, alias); err != nil {
		t.Fatal(err)
	}
	protected := filepath.Join(alias, "offline", "old-library")
	r := New("ffmpeg", filepath.Join(base, "separate-cache"), quiet(), protected)
	if !r.Available() || !r.CacheAdminAvailable() {
		t.Fatal("gewone ontbrekende old-root-suffix schakelt niet-overlappende cache uit")
	}
	if err := os.MkdirAll(r.Dir(), 0755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(r.Dir(), cacheTestName)
	if err := os.WriteFile(file, []byte("derived"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := r.Purge(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(file); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("veilige purge werkte niet: %v", err)
	}
}

func TestCacheUnresolvedProtectedAliasDisablesOnlyDestructiveAdministration(t *testing.T) {
	testsupport.HasFFmpeg(t)
	base := t.TempDir()
	alias := filepath.Join(base, "broken-media-link")
	if err := os.Symlink(filepath.Join(base, "offline-target"), alias); err != nil {
		t.Fatal(err)
	}
	r := New("ffmpeg", filepath.Join(base, "cache"), quiet(), filepath.Join(alias, "old-library"))
	if !r.Available() {
		t.Fatal("onzeker protected-pad schakelde bestaande resizing uit")
	}
	if r.CacheAdminAvailable() {
		t.Error("onoplosbare bestaande symlink adverteert veilige purge")
	}
	src := filepath.Join(base, "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	f, err := r.Open(t.Context(), src, cacheTestKey, 480)
	if err != nil {
		t.Fatal(err)
	}
	info, _, err := image.DecodeConfig(f)
	f.Close()
	if err != nil || info.Width != 480 {
		t.Fatalf("bestaande resizing verloor trede: %v %v", info, err)
	}
	path := filepath.Join(r.Dir(), cacheTestName)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := r.Purge(); err == nil {
		t.Error("onzekere beschermde grens werd toch gewist")
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("onzekere purge raakte bytes: %v", err)
	}
}
