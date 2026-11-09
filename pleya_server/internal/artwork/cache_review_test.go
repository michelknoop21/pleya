//go:build linux || darwin || freebsd || netbsd || openbsd || dragonfly

package artwork

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestForeignRenderCannotFreezeWarmArtworkDuringPurge(t *testing.T) {
	testsupport.HasFFmpeg(t)
	root := t.TempDir()
	parent := cacheFixture(t)
	source := filepath.Join(root, "source.jpg")
	testsupport.MakeImage(t, source, 1200, 1800)
	started, release := filepath.Join(root, "render-started"), filepath.Join(root, "render-release")
	wrapper := filepath.Join(root, "blocked-ffmpeg")
	script := fmt.Sprintf("#!/bin/sh\nprintf ready > %q\nwhile [ ! -e %q ]; do sleep 0.02; done\nexec ffmpeg \"$@\"\n", started, release)
	if err := os.WriteFile(wrapper, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	ready := filepath.Join(root, "ready")
	if err := os.Mkdir(ready, 0700); err != nil {
		t.Fatal(err)
	}
	barrier := filepath.Join(root, "start")
	if err := os.WriteFile(barrier, []byte("start"), 0600); err != nil {
		t.Fatal(err)
	}
	fixture := cacheProcessFixture{Source: source, Cache: filepath.Dir(parent.dir), FFmpeg: wrapper, Barrier: barrier, Ready: ready}
	encoded, _ := json.Marshal(fixture)
	config := filepath.Join(root, "fixture.json")
	if err := os.WriteFile(config, encoded, 0600); err != nil {
		t.Fatal(err)
	}
	slot := sha256.Sum256([]byte(cacheTestName))
	warmKey := ""
	for n := 1; n < 10000; n++ {
		key := fmt.Sprintf("019a0000-0000-7000-8000-%012d_1", n)
		name := key + "_480.jpg"
		candidate := sha256.Sum256([]byte(name))
		if name != cacheTestName && candidate[0]%64 == slot[0]%64 {
			warmKey = key
			break
		}
	}
	if warmKey == "" {
		t.Fatal("no colliding slot")
	}
	if err := os.WriteFile(filepath.Join(parent.dir, warmKey+"_480.jpg"), []byte("warm"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestArtworkCacheProcessHelper$", "-test.v")
	cmd.Env = append(os.Environ(), "PLEYA_ARTWORK_PROCESS_FIXTURE="+config, "PLEYA_ARTWORK_PROCESS_INDEX=foreign")
	output := &bytes.Buffer{}
	cmd.Stdout = output
	cmd.Stderr = output
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.WriteFile(release, []byte("release"), 0600)
		if cmd.ProcessState == nil {
			done := make(chan error, 1)
			go func() { done <- cmd.Wait() }()
			select {
			case <-done:
			case <-time.After(time.Second):
				cancel()
				<-done
			}
		}
		cancel()
	}()
	for {
		if _, err := os.Stat(started); err == nil {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal("foreign render never started", output.String())
		case <-time.After(time.Millisecond):
		}
	}
	parent.gate.mu.Lock()
	before := parent.gate.changed
	parent.gate.mu.Unlock()
	purgeCtx, stopPurge := context.WithCancel(ctx)
	defer stopPurge()
	purged := make(chan error, 1)
	go func() { purged <- parent.PurgeContext(purgeCtx) }()
	for {
		parent.gate.mu.Lock()
		attempted := parent.gate.writing || parent.gate.changed != before
		parent.gate.mu.Unlock()
		if attempted {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(time.Millisecond):
		}
	}
	warmCtx, stopWarm := context.WithTimeout(ctx, time.Second)
	defer stopWarm()
	file, err := parent.Open(warmCtx, source, warmKey, 480)
	if err != nil {
		t.Fatalf("foreign SH froze warm colliding-slot Open: %v", err)
	}
	file.Close()
	stopPurge()
	if err := <-purged; !errors.Is(err, context.Canceled) {
		t.Fatalf("purge cancellation: %v", err)
	}
	if err := os.WriteFile(release, []byte("release"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := cmd.Wait(); err != nil {
		t.Fatal(err, output.String())
	}
	if err := parent.PurgeContext(ctx); err != nil {
		t.Fatal(err)
	}
}

func TestOpenFallbackWarningsAreBounded(t *testing.T) {
	var output bytes.Buffer
	resizer := New("", t.TempDir(), slog.New(slog.NewTextHandler(&output, nil)))
	for n := 0; n < 100; n++ {
		_, _ = resizer.Open(context.Background(), "", "invalid", 480)
	}
	if count := strings.Count(output.String(), "afbeelding verkleinen mislukt"); count != 1 {
		t.Fatalf("warnings %d", count)
	}
	resizer.lastWarning = time.Now().Add(-time.Minute - time.Second)
	_, _ = resizer.Open(context.Background(), "", "invalid", 480)
	if count := strings.Count(output.String(), "afbeelding verkleinen mislukt"); count != 2 {
		t.Fatalf("warning not renewed: %d", count)
	}
}
