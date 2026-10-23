// Package backup maakt, controleert en herstelt back-ups van Pleya Server (S25,
// RB-26, PS-11B).
//
// Een back-up is één tar in de back-upmap: een manifest, de databasedump van
// pg_dump (gzip), de gewone bestanden uit /config en, versleuteld, de geheime.
// Het bestand is de waarheid; de tabellen uit 0022 zijn het register erbij. Dat
// is geen voorzichtigheid maar een gevolg van restore: wie een back-up terugzet,
// zet ook het register terug naar toen, en dan weet alleen de map nog welke
// back-ups er sindsdien bij kwamen. Sync legt het register na het opstarten
// weer gelijk aan de map.
//
// Drie regels dragen het ontwerp, en elk heeft een test met een negatieve
// controle:
//
//   - De geheimen uit /config (de ondertekensleutel) staan nooit leesbaar in een
//     back-up. Een databasedump mag geen sessies opleveren (auth/key.go), en een
//     tar met de dump én de sleutel naast elkaar zou precies dat doen. Met een
//     sleutel gaan ze versleuteld mee (Argon2id plus AES-256-GCM), zonder
//     sleutel blijven ze weg.
//   - De hersteltest raakt de echte database nooit. Hij laadt de dump in een
//     eigen tijdelijke database die hij zelf aanmaakt en weer weggooit, en de
//     naam daarvan wordt gecontroleerd tegen die van de echte.
//   - Terugzetten gebeurt in één transactie (psql --single-transaction): eerst
//     het schema weg, dan de dump. Faalt er iets, dan is er niets gebeurd. Een
//     afgekapte dump zou psql bij het einde van de invoer laten committen, dus
//     bij een leesfout wordt psql gedood vóór de invoer sluit.
package backup

import (
	"errors"
	"log/slog"
	"os"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/database"
)

// Soorten werk in de jobwachtrij.
const (
	JobCreate = "backup_create"
	JobVerify = "backup_verify"
)

// Status is de toestand van een back-up of hersteltest.
type Status string

const (
	StatusRunning Status = "running"
	StatusOK      Status = "ok"
	StatusFailed  Status = "failed"
	// StatusMissing: het bestand verdween uit de map zonder dat de server het
	// weghaalde. Alleen voor een back-up.
	StatusMissing Status = "missing"
)

// Trigger zegt waarom een back-up gemaakt werd.
type Trigger string

const (
	TriggerSchedule Trigger = "schedule"
	TriggerManual   Trigger = "manual"
	// TriggerUpgrade is de back-up die de server vóór de eerste migratie van een
	// nieuwe versie zelf maakt (S25.4).
	TriggerUpgrade Trigger = "upgrade"
)

// Failure is de soort fout van een mislukte back-up of hersteltest. Elk faalpad
// heeft een eigen foutcode (RB-26); de API vertaalt deze soort naar die code.
type Failure string

const (
	FailureDiskFull Failure = "disk_full"
	FailureDatabase Failure = "database_unavailable"
	FailureOther    Failure = "failed"
)

var (
	// ErrNotFound: de back-up of hersteltest bestaat niet.
	ErrNotFound = errors.New("backup: onbekend")
	// ErrNotRestorable: de back-up is niet te gebruiken. De reden staat erbij.
	ErrNotRestorable = errors.New("backup: niet terug te zetten")
	// ErrNotOK en ErrSchemaNewer zijn de twee redenen naast ErrWrongKey waarom
	// een back-up niet terug te zetten is: hij is niet geslaagd of verdwenen, of
	// hij komt van een nieuwere binary.
	ErrNotOK       = errors.New("backup: de back-up is niet geslaagd of niet meer aanwezig")
	ErrSchemaNewer = errors.New("backup: de back-up is van een nieuwer schema dan deze binary")
	// ErrBusy: er wacht of loopt al een back-up of hersteltest.
	ErrBusy = errors.New("backup: er loopt al een back-up of hersteltest")
	// ErrWrongKey: de geheimen in de back-up gaan niet open met deze sleutel.
	ErrWrongKey = errors.New("backup: de sleutel past niet op de geheimen in deze back-up")
)

// classify leidt de soort fout af. Een volle schijf en een weggevallen
// database zijn de twee faalpaden die hier kunnen optreden; al het andere is
// failed.
func classify(err error) Failure {
	switch {
	case errors.Is(err, syscall.ENOSPC), errors.Is(err, syscall.EDQUOT):
		return FailureDiskFull
	case database.Unavailable(err):
		return FailureDatabase
	default:
		return FailureOther
	}
}

// Options bundelt wat de service nodig heeft.
type Options struct {
	Pool *pgxpool.Pool
	// Dir is de back-upmap (PLEYA_SERVER_BACKUP_DIR), ConfigDir de map met de
	// duurzame state die meegaat.
	Dir       string
	ConfigDir string
	// Key is de wachtzin voor de geheimen. Leeg laat ze weg.
	Key           string
	RetentionDays int
	PgDump        string
	Psql          string
	// Version is de versie van de binary, voor het manifest.
	Version string
	// Schedule is het tijdstip van de geplande back-up als HH:MM, alleen om te
	// tonen: plannen doet de aanroeper.
	Schedule string
	Logger   *slog.Logger

	// Create opent een nieuw bestand in de back-upmap. Nil neemt os.OpenFile met
	// O_EXCL en rechten 0600 (K rij 26). Een test geeft er /dev/full voor, zodat
	// "schijf vol" een echte ENOSPC van de kernel is en geen nagemaakte fout.
	Create func(path string) (*os.File, error)
}

// Service maakt, controleert en herstelt back-ups.
type Service struct {
	o   Options
	log *slog.Logger
	now func() time.Time
}

// New bouwt een Service.
func New(o Options) *Service {
	if o.PgDump == "" {
		o.PgDump = "pg_dump"
	}
	if o.Psql == "" {
		o.Psql = "psql"
	}
	if o.RetentionDays <= 0 {
		o.RetentionDays = 14
	}
	if o.Create == nil {
		o.Create = func(path string) (*os.File, error) {
			return os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		}
	}
	log := o.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Service{o: o, log: log, now: time.Now}
}

// WithCreate geeft een kopie die nieuwe bestanden met create opent, zoals
// metadata.Runner.WithSidecar een bron vervangt. De settest van S25.5 geeft er
// /dev/full aan om een volle schijf echt na te spelen.
func (s *Service) WithCreate(create func(path string) (*os.File, error)) *Service {
	c := *s
	c.o.Create = create
	return &c
}

// Dir is de back-upmap.
func (s *Service) Dir() string { return s.o.Dir }

// Schedule is het tijdstip van de geplande back-up.
func (s *Service) Schedule() string { return s.o.Schedule }

// RetentionDays is de bewaartermijn.
func (s *Service) RetentionDays() int { return s.o.RetentionDays }

// KeyConfigured zegt of de geheimen meegaan.
func (s *Service) KeyConfigured() bool { return s.o.Key != "" }

// SameFailureDomain zegt of de back-upmap op hetzelfde bestandssysteem staat
// als /config. Dan neemt één kapotte schijf de state en de back-up samen mee, en
// dat hoort de beheerder te zien (RB-26). Het is een waarschuwing en geen
// weigering: een tweede schijf is niet overal voorhanden, en een back-up op
// dezelfde schijf beschermt nog altijd tegen een mislukte upgrade of een
// verkeerde handeling.
func (s *Service) SameFailureDomain() bool { return sameDevice(s.o.Dir, s.o.ConfigDir) }
