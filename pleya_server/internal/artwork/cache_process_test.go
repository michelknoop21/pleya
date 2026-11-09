//go:build linux || darwin || freebsd || netbsd || openbsd || dragonfly

package artwork

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type cacheProcessFixture struct{ Source, Cache, FFmpeg, Barrier, Ready string }

func TestArtworkCacheProcessHelper(t *testing.T) {
	path := os.Getenv("PLEYA_ARTWORK_PROCESS_FIXTURE")
	if path == "" {
		return
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var f cacheProcessFixture
	if err := json.Unmarshal(body, &f); err != nil {
		t.Fatal(err)
	}
	ready := filepath.Join(f.Ready, os.Getenv("PLEYA_ARTWORK_PROCESS_INDEX"))
	if err := os.WriteFile(ready, []byte("ready"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	for {
		if _, err := os.Stat(f.Barrier); err == nil {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
	r := New(f.FFmpeg, f.Cache, quiet())
	opened, err := r.Open(ctx, f.Source, cacheTestKey, 480)
	if err != nil {
		t.Fatal(err)
	}
	defer opened.Close()
	info, err := opened.Stat()
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() == 0 {
		t.Fatal("lege ladder")
	}
}

func TestArtworkCacheSingleFlightAcrossProcesses(t *testing.T) {
	testsupport.HasFFmpeg(t)
	root := t.TempDir()
	source := filepath.Join(root, "source.jpg")
	testsupport.MakeImage(t, source, 1200, 1800)
	count := filepath.Join(root, "render-count")
	wrapper := filepath.Join(root, "ffmpeg-count")
	script := "#!/bin/sh\nprintf 'render\\n' >> \"$PLEYA_ARTWORK_PROCESS_COUNT\"\nsleep 1\nexec ffmpeg \"$@\"\n"
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	ready := filepath.Join(root, "ready")
	if err := os.Mkdir(ready, 0700); err != nil {
		t.Fatal(err)
	}
	fixture := cacheProcessFixture{Source: source, Cache: filepath.Join(root, "cache"), FFmpeg: wrapper, Barrier: filepath.Join(root, "start"), Ready: ready}
	encoded, _ := json.Marshal(fixture)
	config := filepath.Join(root, "fixture.json")
	if err := os.WriteFile(config, encoded, 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	commands := []*exec.Cmd{}
	outputs := []*bytes.Buffer{}
	defer func() {
		cancel()
		for _, cmd := range commands {
			if cmd.ProcessState == nil {
				_ = cmd.Wait()
			}
		}
	}()
	for n := 0; n < 2; n++ {
		cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestArtworkCacheProcessHelper$", "-test.v")
		cmd.Env = append(os.Environ(), "PLEYA_ARTWORK_PROCESS_FIXTURE="+config, "PLEYA_ARTWORK_PROCESS_INDEX="+fmt.Sprint(n), "PLEYA_ARTWORK_PROCESS_COUNT="+count)
		out := &bytes.Buffer{}
		cmd.Stdout = out
		cmd.Stderr = out
		if err := cmd.Start(); err != nil {
			t.Fatal(err)
		}
		commands = append(commands, cmd)
		outputs = append(outputs, out)
	}
	for {
		entries, err := os.ReadDir(ready)
		if err == nil && len(entries) == 2 {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
	if err := os.WriteFile(fixture.Barrier, []byte("start"), 0600); err != nil {
		t.Fatal(err)
	}
	for n, cmd := range commands {
		if err := cmd.Wait(); err != nil {
			t.Fatalf("proces %d: %v\n%s", n, err, outputs[n])
		}
	}
	renders, err := os.ReadFile(count)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(string(renders), "render\n") != 1 {
		t.Fatalf("dezelfde koude trede werd %d keer gerenderd", strings.Count(string(renders), "render\n"))
	}
	if got := widthOf(t, filepath.Join(fixture.Cache, "artwork-sizes", cacheTestKey+"_480.jpg")); got != 480 {
		t.Fatalf("breedte %d", got)
	}
}

func TestCachePurgeWaitsForIndependentDirectoryLockAndCanCancel(t *testing.T) {
	r := cacheFixture(t)
	if err := os.WriteFile(filepath.Join(r.dir, cacheTestName), []byte("preserve"), 0600); err != nil {
		t.Fatal(err)
	}
	dir, err := r.openCache(false)
	if err != nil {
		t.Fatal(err)
	}
	defer dir.Close()
	unlock, err := lockCacheDir(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	other := New("", filepath.Dir(r.dir), quiet())
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if err := other.PurgeContext(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("purge wachtte niet annuleerbaar op andere directorylease: %v", err)
	}
	if body, err := os.ReadFile(filepath.Join(r.dir, cacheTestName)); err != nil || string(body) != "preserve" {
		t.Fatalf("wachtende purge wijzigde artifact: %v", err)
	}
	unlock()
	if err := other.PurgeContext(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(r.dir, cacheTestName)); !os.IsNotExist(err) {
		t.Fatalf("purge na vrijgave: %v", err)
	}
}

func TestCacheRenderLocksStayBoundedAndOutsideArtifactAccounting(t *testing.T) {
	r := cacheFixture(t)
	dir, err := r.openCache(false)
	if err != nil {
		t.Fatal(err)
	}
	defer dir.Close()
	for n := 1; n <= 256; n++ {
		unlock, err := lockCacheRender(context.Background(), dir, fmt.Sprintf("019a0000-0000-7000-8000-%012d_1_480.jpg", n))
		if err != nil {
			t.Fatal(err)
		}
		unlock()
	}
	entries, err := os.ReadDir(r.dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) > 64 || len(entries) == 0 {
		t.Fatalf("onbegrensde lockbestanden: %d", len(entries))
	}
	size, files, err := r.Stats()
	if err != nil || size != 0 || files != 0 {
		t.Fatalf("locks geteld als ladderbytes: %d/%d %v", size, files, err)
	}
	if err := r.Purge(); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadDir(r.dir)
	if err != nil || len(after) != len(entries) {
		t.Fatalf("purge verwijderde gedeelde slotbestanden: %v", err)
	}
}

func TestCacheRenderLocksRefuseSymlinksAndHardlinks(t *testing.T) {
	for _, hardlink := range []bool{false, true} {
		t.Run(fmt.Sprint("hardlink=", hardlink), func(t *testing.T) {
			r := cacheFixture(t)
			outside := filepath.Join(t.TempDir(), "source")
			if err := os.WriteFile(outside, []byte("protected"), 0600); err != nil {
				t.Fatal(err)
			}
			for n := 0; n < 64; n++ {
				path := filepath.Join(r.dir, fmt.Sprintf(".lock-%02x", n))
				var err error
				if hardlink {
					err = os.Link(outside, path)
				} else {
					err = os.Symlink(outside, path)
				}
				if err != nil {
					t.Fatal(err)
				}
			}
			dir, err := r.openCache(false)
			if err != nil {
				t.Fatal(err)
			}
			defer dir.Close()
			unlock, err := lockCacheRender(context.Background(), dir, cacheTestName)
			if unlock != nil {
				unlock()
			}
			if err == nil {
				t.Fatal("cachelock volgde een alias naar beschermd bestand")
			}
			body, err := os.ReadFile(outside)
			if err != nil || string(body) != "protected" {
				t.Fatalf("beschermde bron gewijzigd: %v", err)
			}
		})
	}
}

func TestCacheOpenKeepsDirectoryLeaseUntilResultDescriptor(t *testing.T) {
	r := newResizer(t)
	if err := os.MkdirAll(r.dir, 0755); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "prepared.jpg")
	testsupport.MakeImage(t, source, 480, 720)
	prepared, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	publish := make(chan struct{})
	published := make(chan struct{})
	finish := make(chan struct{})
	defer func() {
		select {
		case <-publish:
		default:
			close(publish)
		}
		select {
		case <-finish:
		default:
			close(finish)
		}
	}()
	// De renderer mag zijn eigen lease al vrijgeven vóór de wachtende Open wordt hervat.
	pending := r.sf.DoChan(cacheTestName, func() (any, error) {
		<-publish
		err := os.WriteFile(filepath.Join(r.dir, cacheTestName), prepared, 0600)
		close(published)
		<-finish
		return nil, err
	})
	result := make(chan *os.File, 1)
	failure := make(chan error, 1)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	go func() { f, err := r.Open(ctx, "unused", cacheTestKey, 480); result <- f; failure <- err }()
	for {
		r.gate.mu.Lock()
		readers := r.gate.readers
		r.gate.mu.Unlock()
		if readers == 1 {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(time.Millisecond):
		}
	}
	time.Sleep(20 * time.Millisecond)
	close(publish)
	select {
	case <-published:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	select {
	case f := <-result:
		if f != nil {
			f.Close()
		}
		t.Fatal("fixture mist wachtende Open")
	default:
	}
	other := New("", filepath.Dir(r.dir), quiet())
	purgeCtx, stop := context.WithTimeout(ctx, 50*time.Millisecond)
	defer stop()
	if err := other.PurgeContext(purgeCtx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("purge passeerde render-naar-open-grens: %v", err)
	}
	close(finish)
	select {
	case <-pending:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	var opened *os.File
	select {
	case opened = <-result:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if err := <-failure; err != nil {
		t.Fatal(err)
	}
	if opened == nil {
		t.Fatal("geen descriptor")
	}
	defer opened.Close()
	if err := other.PurgeContext(ctx); err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(opened)
	if err != nil || !bytes.Equal(body, prepared) {
		t.Fatalf("geopende response verloor bytes na purge: %v", err)
	}
}
