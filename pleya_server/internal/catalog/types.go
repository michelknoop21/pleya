// Package catalog is de opslaglaag van de bibliotheek.
//
// Het domeinmodel volgt hoofdstuk 7.1: een item is niet een bestand. Een film
// die in 1080p en in 4K op schijf staat is één item met twee versies, en een
// versie die over twee bestanden is gesplitst is één versie met twee bestanden.
// Een pad is nooit een identiteit; een item dat verhuist houdt zijn id, want
// alleen de bestandsrij verandert.
package catalog

import (
	"time"

	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Library is één bibliotheek.
type Library struct {
	ID        id.ID
	Slug      string
	Title     string
	Kind      string // movies of shows
	ItemCount int
}

// StorageLocation is één geconfigureerde root van een bibliotheek.
type StorageLocation struct {
	ID           id.ID
	LibraryID    id.ID
	RootPath     string
	FSType       string
	InodeTrusted bool
	TrustSource  string
}

// FileRole zegt wat voor bestand een rij beschrijft.
type FileRole string

const (
	RoleMedia    FileRole = "media"
	RoleSubtitle FileRole = "subtitle"
	RoleArtwork  FileRole = "artwork"
)

// File is één pad op schijf met zijn verandersdetectie.
type File struct {
	ID                id.ID
	StorageLocationID id.ID
	RelativePath      string
	Role              FileRole
	VersionID         *id.ID
	ItemID            *id.ID
	PartIndex         int
	ArtworkKind       string

	SizeBytes  int64
	MtimeUnix  int64
	Inode      *int64
	Signature  string
	Generation int64

	MissingSince *time.Time
}

// IsAttached zegt of dit bestand aan een versie of een item hangt.
//
// Een net ontdekt bestand hangt nergens aan, en een sidecar waarvan de eigenaar
// nog niet gescand was ook niet. Dat is een tussenstand en geen fout: de
// volgende ronde krijgt hem alsnog te pakken.
func (f *File) IsAttached() bool { return f.VersionID != nil || f.ItemID != nil }

// Item is één rij uit media_items, zonder zijn versies.
type Item struct {
	ID        id.ID
	LibraryID id.ID
	ParentID  *id.ID
	Kind      string
	Title     string
	SortTitle string
	Year      *int
	Index     *int
	AddedAt   time.Time

	// Afgeleid en niet opgeslagen. Ze staan hier omdat het wire-type ze draagt
	// en de leeslaag ze per pagina in één keer ophaalt.
	DurationMs          *int64
	ChildCount          *int
	EpisodeCount        *int
	WatchedEpisodeCount *int
	PosterID            *id.ID
	BackdropID          *id.ID
	Versions            []Version
}

// Version is één versie van een item.
type Version struct {
	ID         id.ID
	ItemID     id.ID
	Container  string
	DurationMs int64
	Edition    string
	BitrateBps *int64
	FileCount  int
	Streams    []Stream
}

// Stream is één spoor, ingebed of los.
type Stream struct {
	ID        id.ID
	VersionID id.ID
	FileID    id.ID
	Kind      string
	Index     *int
	Ordinal   int

	Codec     string
	Profile   string
	Width     *int
	Height    *int
	BitDepth  *int
	FrameRate *float64

	Channels      *int
	ChannelLayout string

	Language string
	Title    string

	IsDefault         bool
	IsForced          bool
	IsHearingImpaired bool
	IsExternal        bool

	SubtitleFormat string
}

// ProbedVersion is wat de scanner na een geslaagde analyse wegschrijft.
type ProbedVersion struct {
	Container  string
	DurationMs int64
	BitrateBps int64
	Detection  ffprobe.DetectionMap
	Streams    []ffprobe.Stream
}
