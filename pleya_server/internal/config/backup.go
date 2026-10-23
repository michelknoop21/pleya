package config

import (
	"fmt"
	"strconv"
	"strings"
)

// Back-upinstellingen (S25, RB-26). Doel, tijdstip en bewaartermijn komen uit
// de omgeving en zijn bewust geen instelling achter PATCH /settings. Het doel
// is een pad, en paden zijn geen instelling (internal/settings). De bewaartermijn
// volgt dezelfde redenering als die van admin_audit (S1.5): een termijn die een
// beheerder over de API kan verlagen, kan een aanvaller met beheerrechten ook
// verlagen, en dan ruimt de server zelf de back-ups op die hem hadden moeten
// redden.
const (
	DefaultBackupDir = "/backups"
	// 03:30 in de tijdzone van de container (TZ in compose.yaml): na de nachtelijke
	// scanronde en ruim vóór iemand weer kijkt.
	DefaultBackupTime          = "03:30"
	DefaultBackupRetentionDays = 14
	MaxBackupRetentionDays     = 365

	// MinBackupKeyLength is de ondergrens voor de wachtzin waarmee de geheimen
	// in een back-up versleuteld worden. Argon2id maakt raden duur, maar een
	// wachtzin van vier tekens blijft er vier.
	MinBackupKeyLength = 16
)

// Backup is de back-upconfiguratie.
type Backup struct {
	Dir           string
	Hour, Minute  int
	RetentionDays int

	// Key is de wachtzin voor de geheimen in een back-up (de ondertekensleutel
	// uit /config). Leeg betekent dat een back-up de geheimen weglaat in plaats
	// van ze leesbaar mee te nemen; een restore houdt dan de sleutel die er staat.
	// De naam eindigt op KEY, zodat GET /server/environment hem maskeert.
	Key string

	// PgDump en Psql zijn de binaries uit de image (Dockerfile). Overschrijfbaar
	// voor een opstelling buiten de container.
	PgDump string
	Psql   string
}

// Schedule geeft het tijdstip als HH:MM.
func (b Backup) Schedule() string { return fmt.Sprintf("%02d:%02d", b.Hour, b.Minute) }

func loadBackup(getenv Getenv) (Backup, error) {
	b := Backup{
		Dir:    valueOr(getenv, "PLEYA_SERVER_BACKUP_DIR", DefaultBackupDir),
		Key:    strings.TrimSpace(getenv("PLEYA_SERVER_BACKUP_KEY")),
		PgDump: valueOr(getenv, "PLEYA_SERVER_PG_DUMP_PATH", "pg_dump"),
		Psql:   valueOr(getenv, "PLEYA_SERVER_PSQL_PATH", "psql"),
	}
	h, m, err := parseClock(valueOr(getenv, "PLEYA_SERVER_BACKUP_TIME", DefaultBackupTime))
	if err != nil {
		return b, fmt.Errorf("PLEYA_SERVER_BACKUP_TIME: %w", err)
	}
	b.Hour, b.Minute = h, m

	raw := valueOr(getenv, "PLEYA_SERVER_BACKUP_RETENTION_DAYS", strconv.Itoa(DefaultBackupRetentionDays))
	days, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || days < 1 || days > MaxBackupRetentionDays {
		return b, fmt.Errorf("PLEYA_SERVER_BACKUP_RETENTION_DAYS: %q is geen getal van 1 tot en met %d", raw, MaxBackupRetentionDays)
	}
	b.RetentionDays = days

	if b.Key != "" && len(b.Key) < MinBackupKeyLength {
		return b, fmt.Errorf("PLEYA_SERVER_BACKUP_KEY: korter dan %d tekens", MinBackupKeyLength)
	}
	return b, nil
}

// parseClock leest HH:MM op een 24-uursklok.
func parseClock(raw string) (int, int, error) {
	hh, mm, ok := strings.Cut(strings.TrimSpace(raw), ":")
	h, errH := strconv.Atoi(hh)
	m, errM := strconv.Atoi(mm)
	if !ok || errH != nil || errM != nil || len(mm) != 2 || h < 0 || h > 23 || m < 0 || m > 59 {
		return 0, 0, fmt.Errorf("%q is geen tijdstip als 03:30", raw)
	}
	return h, m, nil
}
