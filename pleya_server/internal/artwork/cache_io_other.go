//go:build !linux && !darwin && !freebsd && !netbsd && !openbsd && !dragonfly

package artwork

// Bestaande resizing blijft portable via Go's directory-rootvoorzieningen.
// De nieuwe destructieve beheerketen is hier niet bewezen: capability false
// en Purge retourneert een fout, zonder onveilige deletefallback. Secure
// cachebeheer op !unix blijft een open platformimplementatie/-acceptatiegrens.
import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const cacheAdminSupported = false

var errCacheAdminUnsupported = errors.New("veilig artworkcachebeheer is op dit platform niet beschikbaar")

type cacheDir struct{ *os.Root }

func duplicateCacheDir(dir *cacheDir) (*cacheDir, error) {
	root, err := dir.OpenRoot(".")
	if err != nil {
		return nil, err
	}
	return &cacheDir{root}, nil
}

func (r *Resizer) openCache(create bool) (*cacheDir, error) {
	if r.boundaryErr != nil {
		return nil, r.boundaryErr
	}
	path, err := filepath.Abs(r.dir)
	if err != nil {
		return nil, err
	}
	volume := filepath.VolumeName(path) + string(filepath.Separator)
	root, err := os.OpenRoot(volume)
	if err != nil {
		return nil, err
	}
	relative, err := filepath.Rel(volume, path)
	if err != nil {
		root.Close()
		return nil, err
	}
	for _, part := range strings.Split(relative, string(filepath.Separator)) {
		if create {
			if err := root.Mkdir(part, 0755); err != nil && !errors.Is(err, os.ErrExist) {
				root.Close()
				return nil, err
			}
		}
		child, err := root.OpenRoot(part)
		if err != nil {
			root.Close()
			return nil, err
		}
		entry, err := root.Lstat(part)
		anchored, anchoredErr := child.Stat(".")
		if err != nil || anchoredErr != nil || entry.Mode()&os.ModeSymlink != 0 || !entry.IsDir() || !os.SameFile(entry, anchored) {
			child.Close()
			root.Close()
			return nil, errors.New("cachemap is geen stabiele gewone directory")
		}
		root.Close()
		root = child
	}
	return &cacheDir{root}, nil
}
func openArtifact(dir *cacheDir, name string) (*os.File, error) {
	info, err := dir.Lstat(name)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("ladder is geen gewoon bestand")
	}
	f, err := dir.Open(name)
	if err != nil {
		return nil, err
	}
	opened, err := f.Stat()
	current, currentErr := dir.Lstat(name)
	if err != nil || currentErr != nil || !current.Mode().IsRegular() || !os.SameFile(current, opened) {
		f.Close()
		return nil, errors.New("ladder veranderde tijdens openen")
	}
	return f, nil
}
func (r *Resizer) StatsContext(ctx context.Context) (int64, int, error) {
	if err := r.gate.acquire(ctx, false); err != nil {
		return 0, 0, err
	}
	defer r.gate.release(false)
	dir, err := r.openCache(false)
	if errors.Is(err, os.ErrNotExist) {
		return 0, 0, ctx.Err()
	}
	if err != nil {
		return 0, 0, err
	}
	defer dir.Close()
	listing, err := dir.Open(".")
	if err != nil {
		return 0, 0, err
	}
	defer listing.Close()
	entries, err := listing.ReadDir(-1)
	if err != nil {
		return 0, 0, err
	}
	var size int64
	var files int
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return 0, 0, err
		}
		if !artifactName(entry.Name()) {
			continue
		}
		info, err := dir.Lstat(entry.Name())
		if err != nil {
			return 0, 0, err
		}
		if !info.Mode().IsRegular() {
			continue
		}
		if info.Size() < 0 || size > int64(^uint64(0)>>1)-info.Size() {
			return 0, 0, errors.New("cacheomvang buiten bereik")
		}
		size += info.Size()
		files++
	}
	return size, files, ctx.Err()
}
func (r *Resizer) PurgeContext(context.Context) error { return errCacheAdminUnsupported }
func (r *Resizer) run(ctx context.Context, src string, dir *cacheDir, name string, step int) error {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return err
	}
	tmpName := fmt.Sprintf(".incoming-%x.jpg", random)
	tmp, err := dir.OpenFile(tmpName, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer tmp.Close()
	defer dir.Remove(tmpName)
	cmd := exec.CommandContext(ctx, r.ffmpeg, "-v", "error", "-i", src, "-vf", fmt.Sprintf("scale=%d:-2:flags=lanczos", step), "-frames:v", "1", "-q:v", r.quality, "-f", "image2pipe", "-vcodec", "mjpeg", "pipe:1")
	cmd.Stdout = tmp
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg: %w", err)
	}
	info, err := tmp.Stat()
	if err != nil {
		return err
	}
	if info.Size() == 0 {
		return errors.New("ffmpeg leverde niets")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return dir.Rename(tmpName, name)
}
