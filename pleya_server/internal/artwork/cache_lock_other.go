//go:build !linux && !darwin && !freebsd && !netbsd && !openbsd && !dragonfly

package artwork

import "context"

// shortcut: niet-Unix behoudt single-flight binnen het proces; procescoördinatie vraagt platformbewijs.
func lockCacheRender(ctx context.Context, _ *cacheDir, _ string) (func(), error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return func() {}, nil
}

func lockCacheRead(ctx context.Context, _ *cacheDir) (func(), error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return func() {}, nil
}
