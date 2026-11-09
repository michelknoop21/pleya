//go:build linux || darwin || freebsd || netbsd || openbsd || dragonfly

package artwork

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

func lockCacheFD(ctx context.Context, fd int, mode int) (func(), error) {
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		err := unix.Flock(fd, mode|unix.LOCK_NB)
		if err == nil {
			return func() { _ = unix.Flock(fd, unix.LOCK_UN) }, nil
		}
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if !errors.Is(err, unix.EWOULDBLOCK) {
			return nil, err
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}

func lockCacheRead(ctx context.Context, dir *cacheDir) (func(), error) {
	return lockCacheFD(ctx, int(dir.Fd()), unix.LOCK_SH)
}

func lockCacheDir(ctx context.Context, dir *cacheDir) (func(), error) {
	return lockCacheFD(ctx, int(dir.Fd()), unix.LOCK_EX)
}

func lockCacheRender(ctx context.Context, dir *cacheDir, name string) (func(), error) {
	releaseDirectory, err := lockCacheFD(ctx, int(dir.Fd()), unix.LOCK_SH)
	if err != nil {
		return nil, err
	}
	// 64 vaste slots begrenzen de lockbestanden; verschillende treden blijven parallel renderen.
	digest := sha256.Sum256([]byte(name))
	slot := fmt.Sprintf(".lock-%02x", digest[0]%64)
	fd, err := unix.Openat(int(dir.Fd()), slot, unix.O_RDWR|unix.O_CREAT|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
	if err != nil {
		releaseDirectory()
		return nil, err
	}
	file := os.NewFile(uintptr(fd), slot)
	var info unix.Stat_t
	if err = unix.Fstat(fd, &info); err != nil || info.Mode&unix.S_IFMT != unix.S_IFREG || info.Nlink != 1 {
		file.Close()
		releaseDirectory()
		if err == nil {
			err = errors.New("cachelock is geen zelfstandig gewoon bestand")
		}
		return nil, err
	}
	releaseSlot, err := lockCacheFD(ctx, fd, unix.LOCK_EX)
	if err != nil {
		file.Close()
		releaseDirectory()
		return nil, err
	}
	return func() { releaseSlot(); file.Close(); releaseDirectory() }, nil
}

func (r *Resizer) lockCachePurge(ctx context.Context, dir *cacheDir) (func(), error) {
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		if err := r.gate.acquire(ctx, true); err != nil {
			return nil, err
		}
		err := unix.Flock(int(dir.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return func() { _ = unix.Flock(int(dir.Fd()), unix.LOCK_UN); r.gate.release(true) }, nil
		}
		r.gate.release(true)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if !errors.Is(err, unix.EWOULDBLOCK) {
			return nil, err
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}
