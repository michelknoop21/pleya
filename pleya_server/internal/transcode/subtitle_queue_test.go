package transcode_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// orderedSubtitleTool is a fake ffmpeg that logs which stream it runs, records its pid and
// holds until the proceed file exists.
func orderedSubtitleTool(t *testing.T, dir string) (tool, order, pid, proceed string) {
	t.Helper()
	tool, order, pid, proceed = filepath.Join(dir, "ffmpeg"), filepath.Join(dir, "order"), filepath.Join(dir, "pid"), filepath.Join(dir, "proceed")
	script := "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in 0:*) printf '%s\\n' \"${a#0:}\" >> '" + order + "';; esac; done\n" +
		"printf $$ > '" + pid + "'\nwhile [ ! -f '" + proceed + "' ]; do sleep 0.01; done\n" +
		"printf '1\\n00:00:00,000 --> 00:00:01,000\\nCaption\\n'\n"
	if err := os.WriteFile(tool, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	return
}

func subtitleOrder(t *testing.T, path string) []string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Fields(string(data))
}

// awaitTrack repeats until the track is cached, the way a client does after a 503.
func awaitTrack(t *testing.T, m *transcode.Manager, p transcode.SubtitleParams) string {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		path, err := m.ExtractSubtitle(context.Background(), p)
		if err == nil {
			return path
		}
		if !errors.Is(err, transcode.ErrBusy) || time.Now().After(deadline) {
			t.Fatalf("track %d: %v", p.StreamIndex, err)
		}
	}
}

func awaitFinished(t *testing.T, m *transcode.Manager, tracks ...transcode.SubtitleParams) {
	t.Helper()
	for _, p := range tracks {
		awaitTrack(t, m, p)
	}
}

func queueManager(t *testing.T, dir, tool string, o transcode.Options) *transcode.Manager {
	t.Helper()
	o.FFmpegPath, o.Dir, o.Max = tool, filepath.Join(dir, "work"), 1
	if o.SubtitleWait == 0 {
		o.SubtitleWait = 10 * time.Millisecond
	}
	m, err := transcode.New(o)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	return m
}

func TestTheNextTrackGoesToAnotherUser(t *testing.T) {
	dir := t.TempDir()
	tool, order, pid, proceed := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleGrace: time.Minute})
	input := subtitleSource(t, dir)
	alice, bob := id.New(), id.New()
	track := func(user id.ID, index int) transcode.SubtitleParams {
		return transcode.SubtitleParams{User: user, InputPath: input, StreamIndex: index, Format: "srt", Generation: 1}
	}
	busy := func(p transcode.SubtitleParams) {
		t.Helper()
		if _, err := m.ExtractSubtitle(context.Background(), p); !errors.Is(err, transcode.ErrBusy) {
			t.Fatalf("track %d: %v", p.StreamIndex, err)
		}
	}
	busy(track(alice, 1))
	waitForFile(t, pid)
	busy(track(alice, 2))
	busy(track(bob, 4))
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	awaitFinished(t, m, track(alice, 1), track(bob, 4), track(alice, 2))
	if got, want := subtitleOrder(t, order), []string{"1", "4", "2"}; !slices.Equal(got, want) {
		t.Fatalf("order %v, want %v", got, want)
	}
}

// A request that gets a place waits for the track, so the deadline ends it. Over the share
// there is no place, and the answer comes at once.
func TestAUserOverHisShareGetsNoPlaceInTheQueue(t *testing.T) {
	dir := t.TempDir()
	tool, _, pid, _ := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: time.Minute, SubtitleGrace: time.Minute})
	input := subtitleSource(t, dir)
	alice, bob := id.New(), id.New()
	ask := func(user id.ID, index int) error {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()
		_, err := m.ExtractSubtitle(ctx, transcode.SubtitleParams{User: user, InputPath: input, StreamIndex: index, Format: "srt", Generation: 1})
		return err
	}
	if err := ask(alice, 1); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("first track: %v", err)
	}
	waitForFile(t, pid)
	if err := ask(alice, 2); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("second track: %v", err)
	}
	if err := ask(alice, 3); !errors.Is(err, transcode.ErrBusy) {
		t.Fatalf("third track of one user: %v", err)
	}
	if err := ask(bob, 3); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("somebody else's first track: %v", err)
	}
}

func TestAnAbandonedExtractionFreesTheWorkerWithoutCountingAsAFailure(t *testing.T) {
	dir := t.TempDir()
	tool, order, pid, proceed := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: time.Minute, SubtitleGrace: 20 * time.Millisecond})
	p := transcode.SubtitleParams{User: id.New(), InputPath: subtitleSource(t, dir), StreamIndex: 2, Format: "srt", Generation: 1}
	ctx, cancel := context.WithCancel(context.Background())
	first := make(chan error, 1)
	go func() { _, err := m.ExtractSubtitle(ctx, p); first <- err }()
	waitForFile(t, pid)
	raw, err := os.ReadFile(pid)
	if err != nil {
		t.Fatal(err)
	}
	process, err := strconv.Atoi(string(raw))
	if err != nil {
		t.Fatal(err)
	}
	cancel()
	if err := <-first; !errors.Is(err, context.Canceled) {
		t.Fatalf("aborted request: %v", err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(process, 0) == nil {
		if time.Now().After(deadline) {
			t.Fatal("ffmpeg kept running without anybody waiting")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	// Somebody else gets the worker, and a stopped job is no failure to remember.
	other := p
	other.User, other.StreamIndex = id.New(), 3
	awaitFinished(t, m, other, p)
	if got, want := subtitleOrder(t, order), []string{"2", "3", "2"}; !slices.Equal(got, want) {
		t.Fatalf("order %v, want %v", got, want)
	}
}

func TestAnExtractionKeepsRunningWhileSomebodyElseWaits(t *testing.T) {
	dir := t.TempDir()
	tool, order, pid, proceed := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: time.Minute, SubtitleGrace: 300 * time.Millisecond})
	p := transcode.SubtitleParams{User: id.New(), InputPath: subtitleSource(t, dir), StreamIndex: 2, Format: "srt", Generation: 1}
	ctx, cancel := context.WithCancel(context.Background())
	first := make(chan error, 1)
	go func() { _, err := m.ExtractSubtitle(ctx, p); first <- err }()
	waitForFile(t, pid)
	second := make(chan error, 1)
	other := p
	other.User = id.New()
	go func() { _, err := m.ExtractSubtitle(context.Background(), other); second <- err }()
	time.Sleep(50 * time.Millisecond) // the second request has joined
	cancel()
	<-first
	time.Sleep(450 * time.Millisecond) // past the grace of a job nobody waits for
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := <-second; err != nil {
		t.Fatal(err)
	}
	if got := subtitleOrder(t, order); len(got) != 1 {
		t.Fatalf("the job restarted: %v", got)
	}
}

// The client that polls is the same interest as the one that waited: every repeat
// replaces the grace of the one before, however often the wait runs out.
func TestRepeatsKeepAnExtractionAliveLongerThanItsGrace(t *testing.T) {
	dir := t.TempDir()
	tool, order, pid, proceed := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: 20 * time.Millisecond, SubtitleGrace: 500 * time.Millisecond})
	p := transcode.SubtitleParams{User: id.New(), InputPath: subtitleSource(t, dir), StreamIndex: 2, Format: "srt", Generation: 1}
	if _, err := m.ExtractSubtitle(context.Background(), p); !errors.Is(err, transcode.ErrBusy) {
		t.Fatalf("first request: %v", err)
	}
	waitForFile(t, pid)
	for range 40 { // together well past one grace
		if _, err := m.ExtractSubtitle(context.Background(), p); !errors.Is(err, transcode.ErrBusy) {
			t.Fatalf("repeat: %v", err)
		}
	}
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	awaitFinished(t, m, p)
	if got := subtitleOrder(t, order); len(got) != 1 {
		t.Fatalf("the job restarted: %v", got)
	}
}

func TestAQueuedTrackNobodyAsksForAnymoreNeverStarts(t *testing.T) {
	dir := t.TempDir()
	tool, order, pid, proceed := orderedSubtitleTool(t, dir)
	m := queueManager(t, dir, tool, transcode.Options{SubtitleGrace: 200 * time.Millisecond})
	input := subtitleSource(t, dir)
	running := transcode.SubtitleParams{User: id.New(), InputPath: input, StreamIndex: 1, Format: "srt", Generation: 1}
	queued := transcode.SubtitleParams{User: id.New(), InputPath: input, StreamIndex: 2, Format: "srt", Generation: 1}
	keepAsking := func(stop <-chan struct{}) {
		for {
			select {
			case <-stop:
				return
			default:
				_, _ = m.ExtractSubtitle(context.Background(), running)
			}
		}
	}
	stop := make(chan struct{})
	defer close(stop)
	go keepAsking(stop)
	waitForFile(t, pid)
	if _, err := m.ExtractSubtitle(context.Background(), queued); !errors.Is(err, transcode.ErrBusy) {
		t.Fatalf("queued track: %v", err)
	}
	time.Sleep(500 * time.Millisecond)
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	awaitFinished(t, m, running)
	time.Sleep(100 * time.Millisecond)
	if got := subtitleOrder(t, order); !slices.Equal(got, []string{"1"}) {
		t.Fatalf("started %v", got)
	}
}

func TestSubtitleCacheSurvivesARestartAndOnlyTheLeftoversGo(t *testing.T) {
	dir := t.TempDir()
	tool, order, _, proceed := orderedSubtitleTool(t, dir)
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	work := filepath.Join(dir, "work")
	o := transcode.Options{FFmpegPath: tool, Dir: work, Max: 1}
	m, err := transcode.New(o)
	if err != nil {
		t.Fatal(err)
	}
	p := transcode.SubtitleParams{InputPath: subtitleSource(t, dir), StreamIndex: 2, Format: "srt", Generation: 1}
	path, err := m.ExtractSubtitle(context.Background(), p)
	if err != nil {
		t.Fatal(err)
	}
	m.Close()
	temp := filepath.Join(work, "subtitles", ".subtitle-123")
	session := filepath.Join(work, "afgebroken-sessie")
	if err := os.WriteFile(temp, []byte("half"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(session, 0700); err != nil {
		t.Fatal(err)
	}

	again, err := transcode.New(o)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(again.Close)
	if _, err := os.Stat(temp); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("half a track survived: %v", err)
	}
	if _, err := os.Stat(session); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a session directory survived: %v", err)
	}
	if got, err := again.ExtractSubtitle(context.Background(), p); err != nil || got != path {
		t.Fatalf("after restart: %s %v", got, err)
	}
	if got := subtitleOrder(t, order); len(got) != 1 {
		t.Fatalf("the restart extracted again: %v", got)
	}
}

func TestSubtitleCacheEvictsTheLeastRecentlyUsedAndNothingInUse(t *testing.T) {
	dir := t.TempDir()
	tool, _, _, proceed := orderedSubtitleTool(t, dir)
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	// One caption is 40 bytes: three fit, the fourth pushes something out.
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: 10 * time.Second, SubtitleCacheBytes: 3*40 + 10})
	input := subtitleSource(t, dir)
	track := func(index int) transcode.SubtitleParams {
		return transcode.SubtitleParams{InputPath: input, StreamIndex: index, Format: "srt", Generation: 1}
	}
	paths := map[int]string{}
	for _, index := range []int{1, 2, 3} {
		path, err := m.ExtractSubtitle(context.Background(), track(index))
		if err != nil {
			t.Fatal(err)
		}
		paths[index] = path
	}
	// All three long unused; 1 is the oldest, but a hit makes it the newest.
	old := time.Now().Add(-time.Hour)
	for i, index := range []int{1, 2, 3} {
		stamp := old.Add(time.Duration(i) * time.Minute)
		if err := os.Chtimes(paths[index], stamp, stamp); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := m.ExtractSubtitle(context.Background(), track(1)); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(paths[1])
	if err != nil || time.Since(info.ModTime()) > time.Minute {
		t.Fatalf("a cache hit did not refresh the track: %v %v", info, err)
	}

	fresh, err := m.ExtractSubtitle(context.Background(), track(4))
	if err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]bool{paths[1]: true, paths[2]: false, paths[3]: true, fresh: true} {
		if _, err := os.Stat(path); (err == nil) != want {
			t.Fatalf("%s: present %v, want %v", path, err == nil, want)
		}
	}
}

func TestATrackHandedOutMomentsAgoStaysEvenOverBudget(t *testing.T) {
	dir := t.TempDir()
	tool, _, _, proceed := orderedSubtitleTool(t, dir)
	if err := os.WriteFile(proceed, nil, 0600); err != nil {
		t.Fatal(err)
	}
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: 10 * time.Second, SubtitleCacheBytes: 10})
	input := subtitleSource(t, dir)
	first, err := m.ExtractSubtitle(context.Background(), transcode.SubtitleParams{InputPath: input, StreamIndex: 1, Format: "srt", Generation: 1})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := m.ExtractSubtitle(context.Background(), transcode.SubtitleParams{InputPath: input, StreamIndex: 2, Format: "srt", Generation: 1}); err != nil {
		t.Fatal(err)
	}
	// What a burn does right after ExtractSubtitle: the cache must not have pulled it away.
	if err := os.Link(first, filepath.Join(dir, "session-subtitle")); err != nil {
		t.Fatal(err)
	}
}

// A rename keeps the mtime of ffmpeg's last write. A track that ends in a long silent stretch
// is therefore already old when it lands in the cache, and the trim right behind it must not
// take it away before the request gets its path.
func TestATrackWithASilentTailSurvivesTheTrimRightBehindIt(t *testing.T) {
	dir := t.TempDir()
	tool := filepath.Join(dir, "ffmpeg")
	temps := filepath.Join(dir, "work", "subtitles", ".subtitle-*")
	script := "#!/bin/sh\nprintf '1\\n00:00:00,000 --> 00:00:01,000\\nCaption\\n'\n" +
		"while :; do for f in " + temps + "; do if [ -s \"$f\" ]; then touch -t 200001010000 \"$f\"; exit 0; fi; done; sleep 0.01; done\n"
	if err := os.WriteFile(tool, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	m := queueManager(t, dir, tool, transcode.Options{SubtitleWait: 10 * time.Second, SubtitleCacheBytes: 10})

	path, err := m.ExtractSubtitle(context.Background(), transcode.SubtitleParams{
		InputPath: subtitleSource(t, dir), StreamIndex: 1, Format: "srt", Generation: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("the trim took the track: %v", err)
	}
	if time.Since(info.ModTime()) > time.Minute {
		t.Fatalf("the track still carries the age of its last write: %v", info.ModTime())
	}
}
