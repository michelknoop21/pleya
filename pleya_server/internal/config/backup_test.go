package config

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/logging"
)

func TestBackupDefaultsAreDirTimeAndRetentionFromRB26(t *testing.T) {
	cfg, err := Load(env(map[string]string{"DATABASE_URL": validDSN}))
	if err != nil {
		t.Fatal(err)
	}
	b := cfg.Backup
	if b.Dir != "/backups" || b.Schedule() != "03:30" || b.RetentionDays != 14 || b.Key != "" {
		t.Fatalf("defaults %+v, verwacht /backups, 03:30, 14 en geen sleutel", b)
	}
}

func TestBackupSettingsRejectNonsense(t *testing.T) {
	for _, tc := range []map[string]string{
		{"PLEYA_SERVER_BACKUP_TIME": "3.30"},
		{"PLEYA_SERVER_BACKUP_TIME": "24:00"},
		{"PLEYA_SERVER_BACKUP_TIME": "03:3"},
		{"PLEYA_SERVER_BACKUP_RETENTION_DAYS": "0"},
		{"PLEYA_SERVER_BACKUP_RETENTION_DAYS": "veertien"},
		{"PLEYA_SERVER_BACKUP_KEY": "te-kort"},
	} {
		tc["DATABASE_URL"] = validDSN
		if _, err := Load(env(tc)); err == nil {
			t.Errorf("%v werd geaccepteerd", tc)
		}
	}
	cfg, err := Load(env(map[string]string{
		"DATABASE_URL": validDSN, "PLEYA_SERVER_BACKUP_TIME": "23:05", "PLEYA_SERVER_BACKUP_RETENTION_DAYS": "30",
	}))
	if err != nil || cfg.Backup.Schedule() != "23:05" || cfg.Backup.RetentionDays != 30 {
		t.Fatalf("geldige waarden: %+v, %v", cfg, err)
	}
}

// De sleutel staat in de omgeving, en GET /server/environment toont de
// omgeving. Hij moet dus gemaskeerd zijn op grond van zijn naam.
func TestBackupKeyIsMaskedInTheEnvironmentListing(t *testing.T) {
	if masked, changed := logging.MaskEnvironment("PLEYA_SERVER_BACKUP_KEY", "een-wachtzin-van-genoeg-tekens"); !changed || masked != "[REDACTED]" {
		t.Fatalf("de back-upsleutel lekt: %q", masked)
	}
}
