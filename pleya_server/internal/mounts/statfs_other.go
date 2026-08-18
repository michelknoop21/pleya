//go:build !linux

package mounts

// De server draait in een Linux-container. Op andere platformen compileert de
// code wel, zodat een ontwikkelaar de tests lokaal kan draaien, maar de
// mountgegevens zijn daar niet betekenisvol.
func statfs(_ string) (fsType string, readOnly bool, free uint64, err error) {
	return "onbekend", false, 0, nil
}
