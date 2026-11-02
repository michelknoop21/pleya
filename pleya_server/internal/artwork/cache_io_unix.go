//go:build unix

package artwork

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/sys/unix"
)

const cacheAdminSupported = true

type cacheDir = os.File

func duplicateCacheDir(dir *cacheDir) (*cacheDir, error) {
	fd, err := unix.Openat(int(dir.Fd()), ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	return os.NewFile(uintptr(fd), dir.Name()), nil
}

// openCache loopt vanaf een directory-FD zonder symlinks te volgen. Ook een
// vervangen cachemap kan een reeds geopende operatie niet omleiden. Geen
// Lstat→join: alle latere toegang blijft relatief aan deze descriptor.
func (r *Resizer) openCache(create bool) (*os.File, error) {
	if r.boundaryErr != nil {
		return nil, r.boundaryErr
	}
	path, err := filepath.Abs(r.dir)
	if err != nil {
		return nil, err
	}
	fd, err := unix.Open("/", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	for _, part := range strings.Split(strings.TrimPrefix(path, "/"), "/") {
		next, e := unix.Openat(fd, part, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
		if create && errors.Is(e, unix.ENOENT) {
			if e = unix.Mkdirat(fd, part, 0755); e == nil || errors.Is(e, unix.EEXIST) {
				next, e = unix.Openat(fd, part, unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
			}
		}
		unix.Close(fd)
		if e != nil {
			return nil, &os.PathError{Op: "cachemap openen", Path: path, Err: e}
		}
		fd = next
	}
	return os.NewFile(uintptr(fd), path), nil
}

func openArtifact(dir *os.File, name string) (*os.File, error) {
	fd, err := unix.Openat(int(dir.Fd()), name, unix.O_RDONLY|unix.O_NONBLOCK|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, &os.PathError{Op: "ladder openen", Path: name, Err: err}
	}
	f := os.NewFile(uintptr(fd), name)
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	if !info.Mode().IsRegular() {
		f.Close()
		return nil, fmt.Errorf("ladder is geen gewoon bestand")
	}
	return f, nil
}

func (r *Resizer) StatsContext(ctx context.Context) (bytes int64, files int, err error) {
	if err = r.gate.acquire(ctx, false); err != nil {
		return
	}
	defer r.gate.release(false)
	dir, err := r.openCache(false)
	if errors.Is(err, os.ErrNotExist) {
		return 0, 0, nil
	}
	if err != nil {
		return 0, 0, err
	}
	defer dir.Close()
	entries, err := dir.ReadDir(-1)
	if err != nil {
		return 0, 0, err
	}
	for _, entry := range entries {
		if err = ctx.Err(); err != nil {
			return 0, 0, err
		}
		if !artifactName(entry.Name()) {
			continue
		}
		// Fstatat met NOFOLLOW leest de huidige entry onder dezelfde directory-FD;
		// DirEntry.Info zou bij een hernoemde directory zijn pad kunnen heropenen.
		var st unix.Stat_t
		if err = unix.Fstatat(int(dir.Fd()), entry.Name(), &st, unix.AT_SYMLINK_NOFOLLOW); err != nil {
			return 0, 0, err
		}
		if st.Mode&unix.S_IFMT != unix.S_IFREG {
			continue
		}
		if st.Size < 0 || bytes > int64(^uint64(0)>>1)-st.Size {
			return 0, 0, errors.New("cacheomvang buiten bereik")
		}
		bytes += st.Size
		files++
	}
	return bytes, files, ctx.Err()
}
func (r *Resizer) PurgeContext(ctx context.Context) error {
	if r.purgeBoundaryErr != nil {
		return r.purgeBoundaryErr
	}
	if err := r.gate.acquire(ctx, true); err != nil {
		return err
	}
	defer r.gate.release(true)
	dir, err := r.openCache(false)
	if errors.Is(err, os.ErrNotExist) {
		return ctx.Err()
	}
	if err != nil {
		return err
	}
	defer dir.Close()
	entries, err := dir.ReadDir(-1)
	if err != nil {
		return err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return err
		}
		if !artifactName(entry.Name()) {
			continue
		}
		var st unix.Stat_t
		if err := unix.Fstatat(int(dir.Fd()), entry.Name(), &st, unix.AT_SYMLINK_NOFOLLOW); err != nil {
			return err
		}
		if st.Mode&unix.S_IFMT != unix.S_IFREG {
			continue
		}
		if err := unix.Unlinkat(int(dir.Fd()), entry.Name(), 0); err != nil {
			return err
		}
	}
	return ctx.Err()
}
func (r *Resizer) run(ctx context.Context, src string, dir *cacheDir, name string, step int) error {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return err
	}
	tmpName := fmt.Sprintf(".incoming-%x.jpg", random)
	fd, err := unix.Openat(int(dir.Fd()), tmpName, unix.O_WRONLY|unix.O_CREAT|unix.O_EXCL|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
	if err != nil {
		return err
	}
	tmp := os.NewFile(uintptr(fd), tmpName)
	defer tmp.Close()
	defer unix.Unlinkat(int(dir.Fd()), tmpName, 0)
	// ffmpeg schrijft naar een al geopend tijdelijk bestand, dus ook een
	// cachemapswap kan zijn uitvoer niet naar bron/pins/config omleiden.
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
	return unix.Renameat(int(dir.Fd()), tmpName, int(dir.Fd()), name)
}
