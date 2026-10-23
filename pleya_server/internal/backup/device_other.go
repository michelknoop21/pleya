//go:build !unix

package backup

// sameDevice kan buiten unix niet meten en waarschuwt dus niet.
func sameDevice(_, _ string) bool { return false }
