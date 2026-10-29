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

	"github.com/edde746/plezy/pleya_server/internal/fileid"
)

const maxSubtitleBytes int64 = 4 << 20
const maxSubtitleCacheBytes int64 = 64 << 20

// SubtitleParams contains only catalog-validated source properties.
type SubtitleParams struct {
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

// ExtractSubtitle reuses one bounded worker and deduplicates identical requests.
func (m *Manager) ExtractSubtitle(ctx context.Context, p SubtitleParams) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if !m.Enabled() || p.StreamIndex < 0 || subtitleMuxer(p.Format) == "" {
		return "", ErrFailed
	}
	limit := maxSubtitleBytes
	// Bitmap tracks may occupy the full derived-cache budget; the text limit would reject ordinary image tracks.
	if p.Format == "pgs" || p.Format == "dvdsub" {
		limit = maxSubtitleCacheBytes
	}
	info, err := os.Stat(p.InputPath)
	if err != nil || !info.Mode().IsRegular() {
		return "", fmt.Errorf("%w: subtitle source unavailable", ErrFailed)
	}
	fingerprint := fileid.Of(info).WeakETag(p.Generation)
	key := fmt.Sprintf("%x", sha256.Sum256(fmt.Appendf(nil, "%s:%s:%d:%s", p.InputPath, fingerprint, p.StreamIndex, p.Format)))
	result := m.subtitleSF.DoChan(key, func() (any, error) {
		select {
		case m.subtitleSem <- struct{}{}:
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-m.stop:
			return nil, ErrStopped
		default:
			return nil, ErrBusy
		}
		defer func() { <-m.subtitleSem }()
		m.mu.Lock()
		if m.closed {
			m.mu.Unlock()
			return nil, ErrStopped
		}
		m.wg.Add(1)
		m.mu.Unlock()
		defer m.wg.Done()
		dir := filepath.Join(m.o.Dir, "subtitles")
		ext := p.Format
		if p.Format == "pgs" || p.Format == "dvdsub" {
			ext = "mks"
		}
		target := filepath.Join(dir, key+"."+ext)
		if st, err := os.Stat(target); err == nil && st.Mode().IsRegular() && st.Size() > 0 && st.Size() <= limit {
			return target, nil
		}
		if err := os.MkdirAll(dir, 0700); err != nil {
			return nil, err
		}
		temp, err := os.CreateTemp(dir, ".subtitle-")
		if err != nil {
			return nil, err
		}
		defer os.Remove(temp.Name())
		defer temp.Close()
		jobCtx, cancel := context.WithTimeout(ctx, m.o.StartTimeout)
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
			return nil, err
		}
		if err := cmd.Start(); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrFailed, err)
		}
		written, copyErr := io.Copy(temp, io.LimitReader(pipe, limit+1))
		if copyErr != nil || written > limit {
			_ = cmd.Process.Kill()
		}
		waitErr := cmd.Wait()
		if copyErr != nil || waitErr != nil || written == 0 || written > limit {
			return nil, fmt.Errorf("%w: subtitle extraction failed: %s", ErrFailed, stderr.String())
		}
		latest, err := os.Stat(p.InputPath)
		if err != nil || fileid.Of(latest).WeakETag(p.Generation) != fingerprint {
			return nil, fmt.Errorf("%w: subtitle source changed", ErrFailed)
		}
		if err := temp.Close(); err != nil {
			return nil, err
		}
		if err := os.Rename(temp.Name(), target); err != nil {
			return nil, err
		}
		trimSubtitleCache(dir, target)
		return target, nil
	})
	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case r := <-result:
		if r.Err != nil {
			return "", r.Err
		}
		return r.Val.(string), nil
	}
}

func trimSubtitleCache(dir, keep string) {
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
	for _, file := range files {
		if total <= maxSubtitleCacheBytes {
			return
		}
		if file.path == keep {
			continue
		}
		if os.Remove(file.path) == nil {
			total -= file.info.Size()
		}
	}
}
