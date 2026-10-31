package transcode

import (
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/fileid"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

const maxSubtitleBytes int64 = 4 << 20

// maxBitmapSubtitleBytes is one image track; a film's PGS track easily passes the text limit.
const maxBitmapSubtitleBytes int64 = 64 << 20

// maxSubtitleCacheBytes holds several full bitmap tracks, so one of them never pushes out the rest.
const maxSubtitleCacheBytes int64 = 512 << 20

// subtitleDirName is the cache inside the transcode directory; a restart keeps it.
const subtitleDirName = "subtitles"

// subtitleTempPrefix marks an extraction in progress.
const subtitleTempPrefix = ".subtitle-"

// subtitleFailureMemory spans one Retry-After of 5 s plus the round trip around it.
const subtitleFailureMemory = 15 * time.Second

// subtitleInUse protects a track that was just handed out: a burn links it into its session
// dir right after, and a hardware failure links it again after up to one StartTimeout.
const subtitleInUse = 5 * time.Minute

// SubtitleParams contains only catalog-validated source properties.
type SubtitleParams struct {
	// User is who asked; the queue is fair between users and bounds each of them.
	User        id.ID
	InputPath   string
	StreamIndex int
	Format      string
	Generation  int64
}

func subtitleMuxer(format string) string {
	switch format {
	case "srt":
		return "srt"
	case "ass", "ssa":
		return "ass"
	case "vtt":
		return "webvtt"
	case "pgs", "dvdsub":
		return "matroska"
	default:
		return ""
	}
}

// ExtractSubtitle returns the cached track, or waits at most SubtitleWait for it.
//
// The extraction runs on one worker, detached from the request: a Matroska file has
// no index of its subtitle blocks, so ffmpeg reads the whole file, and that can take
// longer than a proxy keeps a silent request open. ErrBusy means "ask again": this track
// is still queued or being prepared, and the repeat joins it, or this user already has
// his share of the queue. See subtitle_queue.go for who gets the worker and when a job stops.
func (m *Manager) ExtractSubtitle(ctx context.Context, p SubtitleParams) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if !m.Enabled() || p.StreamIndex < 0 || subtitleMuxer(p.Format) == "" {
		return "", ErrFailed
	}
	limit := maxSubtitleBytes
	// Bitmap tracks are images; the text limit would reject ordinary ones.
	if p.Format == "pgs" || p.Format == "dvdsub" {
		limit = maxBitmapSubtitleBytes
	}
	info, err := os.Stat(p.InputPath)
	if err != nil || !info.Mode().IsRegular() {
		return "", fmt.Errorf("%w: subtitle source unavailable", ErrFailed)
	}
	fingerprint := fileid.Of(info).WeakETag(p.Generation)
	key := fmt.Sprintf("%x", sha256.Sum256(fmt.Appendf(nil, "%s:%s:%d:%s", p.InputPath, fingerprint, p.StreamIndex, p.Format)))
	dir := filepath.Join(m.o.Dir, subtitleDirName)
	ext := p.Format
	if p.Format == "pgs" || p.Format == "dvdsub" {
		ext = "mks"
	}
	target := filepath.Join(dir, key+"."+ext)
	// Before the worker: a finished track never waits for somebody else's extraction.
	if m.subtitleCached(target, limit) {
		return target, nil
	}
	if m.subtitleFailedRecently(key) {
		return "", fmt.Errorf("%w: subtitle extraction failed moments ago", ErrFailed)
	}
	job, err := m.joinSubtitleJob(&subtitleJob{
		key: key, target: target, dir: dir, fingerprint: fingerprint, limit: limit,
		params: p, done: make(chan struct{}),
	})
	if err != nil {
		return "", err
	}
	wait := time.NewTimer(m.o.SubtitleWait)
	defer wait.Stop()
	select {
	case <-ctx.Done():
		m.leaveSubtitleJob(job)
		return "", ctx.Err()
	case <-wait.C:
		m.leaveSubtitleJob(job)
		return "", ErrBusy
	case <-job.done:
		if job.err != nil {
			return "", job.err
		}
		return target, nil
	}
}

// subtitleCached reports a finished track and marks it recently used.
func (m *Manager) subtitleCached(target string, limit int64) bool {
	m.subtitleCache.Lock()
	defer m.subtitleCache.Unlock()
	st, err := os.Stat(target)
	if err != nil || !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > limit {
		return false
	}
	now := time.Now()
	_ = os.Chtimes(target, now, now)
	return true
}

// extractSubtitleFile writes the track to a temporary file and only renames a complete result.
func (m *Manager) extractSubtitleFile(ctx context.Context, p SubtitleParams, fingerprint, dir, target string, limit int64) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	temp, err := os.CreateTemp(dir, subtitleTempPrefix)
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	defer temp.Close()
	jobCtx, cancel := context.WithTimeout(ctx, m.o.SubtitleTimeout)
	defer cancel()
	go func() {
		select {
		case <-m.stop:
			cancel()
		case <-jobCtx.Done():
		}
	}()
	cmd := exec.CommandContext(jobCtx, m.o.FFmpegPath, "-nostdin", "-hide_banner", "-loglevel", "error",
		"-i", p.InputPath, "-map", "0:"+strconv.Itoa(p.StreamIndex), "-vn", "-an", "-dn", "-c:s", "copy", "-f", subtitleMuxer(p.Format), "pipe:1")
	var stderr tailBuffer
	cmd.Stderr = &stderr
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("%w: %v", ErrFailed, err)
	}
	written, copyErr := io.Copy(temp, io.LimitReader(pipe, limit+1))
	if copyErr != nil || written > limit {
		_ = cmd.Process.Kill()
	}
	waitErr := cmd.Wait()
	select {
	case <-m.stop:
		return ErrStopped
	default:
	}
	// Abandoned, not failed: a repeat may start it again without hearing about a failure.
	if err := ctx.Err(); err != nil {
		return err
	}
	if copyErr != nil || waitErr != nil || written == 0 || written > limit {
		return fmt.Errorf("%w: subtitle extraction failed: %s", ErrFailed, stderr.String())
	}
	latest, err := os.Stat(p.InputPath)
	if err != nil || fileid.Of(latest).WeakETag(p.Generation) != fingerprint {
		return fmt.Errorf("%w: subtitle source changed", ErrFailed)
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), target)
}

// subtitleFailedRecently keeps a failure readable for the repeat that follows Retry-After.
// Without it, a job that fails between two polls is started again and the client never hears 502.
func (m *Manager) subtitleFailedRecently(key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	failed, ok := m.subtitleFailed[key]
	return ok && time.Since(failed) < subtitleFailureMemory
}

func (m *Manager) rememberSubtitleFailure(key string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for other, failed := range m.subtitleFailed {
		if time.Since(failed) >= subtitleFailureMemory {
			delete(m.subtitleFailed, other)
		}
	}
	m.subtitleFailed[key] = time.Now()
}

// trimSubtitleCache removes the least recently used tracks until the cache fits its budget.
// A track handed out moments ago stays, even over budget: a burn is about to link it.
func (m *Manager) trimSubtitleCache(dir string) {
	m.subtitleCache.Lock()
	defer m.subtitleCache.Unlock()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	type cached struct {
		path string
		info os.FileInfo
	}
	var files []cached
	var total int64
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		total += info.Size()
		files = append(files, cached{filepath.Join(dir, entry.Name()), info})
	}
	slices.SortFunc(files, func(a, b cached) int { return a.info.ModTime().Compare(b.info.ModTime()) })
	inUse := time.Now().Add(-subtitleInUse)
	for _, file := range files {
		if total <= m.o.SubtitleCacheBytes {
			return
		}
		if file.info.ModTime().After(inUse) {
			continue
		}
		if os.Remove(file.path) == nil {
			total -= file.info.Size()
		}
	}
}

// removeSubtitleTemps clears what a stopped process left behind in the cache.
func removeSubtitleTemps(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), subtitleTempPrefix) {
			_ = os.Remove(filepath.Join(dir, entry.Name()))
		}
	}
}
