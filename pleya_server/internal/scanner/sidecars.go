package scanner

import (
	"context"
	"log/slog"
	"path"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

// mediaAnchor is waar een sidecar aan gehangen kan worden.
type mediaAnchor struct {
	versionID id.ID
	itemID    id.ID
}

// processSidecars hangt losse ondertitels en afbeeldingen aan hun eigenaar.
//
// Ondertitels horen bij een versie, afbeeldingen bij een item. Een bestand
// waarvan de eigenaar niet te bepalen is blijft in media_files staan zonder
// koppeling; het is dan wel bekend, zodat de volgende ronde het niet opnieuw
// als nieuw ziet.
func (s *Scanner) processSidecars(ctx context.Context, root catalog.StorageLocation, media, sidecars []candidate, stats *Stats, log *slog.Logger) error {
	if len(sidecars) == 0 {
		return nil
	}

	anchors, err := s.anchors(ctx, root, media)
	if err != nil {
		return err
	}

	for i := range sidecars {
		c := &sidecars[i]

		if c.action == actionNew {
			if err := s.store.InsertFile(ctx, &catalog.File{
				ID:                c.fileID,
				StorageLocationID: root.ID,
				RelativePath:      c.entry.RelPath,
				Role:              roleFor(c.entry.Kind),
				SizeBytes:         c.entry.Size,
				MtimeUnix:         c.entry.Mtime,
				Inode:             inodePtr(c.entry.Inode),
				Signature:         c.signature,
			}); err != nil {
				return err
			}
		} else if c.renamed {
			if err := s.store.MoveFile(ctx, c.fileID, c.entry.RelPath); err != nil {
				return err
			}
		}

		// Een ongewijzigde sidecar die al gekoppeld is hoeft niets. Een die nog
		// nergens aan hangt krijgt alsnog een kans: de media ernaast kan deze
		// ronde pas zijn binnengekomen.
		if c.action == actionUnchanged && c.prev != nil &&
			(c.prev.VersionID != nil || c.prev.ItemID != nil) {
			continue
		}

		fileName := path.Base(c.entry.RelPath)
		switch c.entry.Kind {
		case nameparse.KindSubtitle:
			if err := s.attachSubtitle(ctx, c, fileName, anchors, stats, log); err != nil {
				return err
			}
		case nameparse.KindImage:
			if err := s.attachArtwork(ctx, c, fileName, anchors); err != nil {
				return err
			}
		}
	}
	return nil
}

// anchorSet is waar sidecars aan gehangen kunnen worden, van precies naar ruim.
type anchorSet struct {
	// byBase: naast het mediabestand met dezelfde naam. Het meest precies.
	byBase map[string]mediaAnchor
	// byDir: in dezelfde map, mits die map precies één item draagt.
	byDir map[string]mediaAnchor
	// byParentDir: een map erboven, voor de serie- of seizoensmap waar geen
	// mediabestand in staat maar wel een poster.
	byParentDir map[string]mediaAnchor
}

// anchors bouwt die drie kaarten uit de mediabestanden van deze ronde.
func (s *Scanner) anchors(ctx context.Context, root catalog.StorageLocation, media []candidate) (*anchorSet, error) {
	set := &anchorSet{
		byBase:      map[string]mediaAnchor{},
		byDir:       map[string]mediaAnchor{},
		byParentDir: map[string]mediaAnchor{},
	}

	ids := make([]id.ID, 0, len(media))
	for _, c := range media {
		ids = append(ids, c.fileID)
	}
	owners, err := s.store.FileOwners(ctx, ids)
	if err != nil {
		return nil, err
	}

	dirItems := map[string]map[id.ID]bool{}
	parentItems := map[string]map[id.ID]bool{}

	for _, c := range media {
		owner, ok := owners[c.fileID]
		if !ok {
			continue
		}
		anchor := mediaAnchor{versionID: owner.VersionID, itemID: owner.ItemID}
		set.byBase[path.Join(c.entry.Dir, c.entry.Base)] = anchor

		if dirItems[c.entry.Dir] == nil {
			dirItems[c.entry.Dir] = map[id.ID]bool{}
		}
		dirItems[c.entry.Dir][owner.ItemID] = true
		set.byDir[c.entry.Dir] = anchor

		// Een aflevering hangt onder een seizoen onder een serie. De map boven de
		// seizoensmap is de seriemap, en daar staat de poster van de serie.
		if owner.GrandID != nil {
			parent := parentDir(c.entry.Dir)
			if parentItems[parent] == nil {
				parentItems[parent] = map[id.ID]bool{}
			}
			parentItems[parent][*owner.GrandID] = true
			set.byParentDir[parent] = mediaAnchor{versionID: owner.VersionID, itemID: *owner.GrandID}
		}
	}

	// Een map met meer dan één item erin kan een losse poster.jpg niet
	// toewijzen. Dan hangt hij nergens aan, en dat is beter dan hem aan een
	// willekeurig item hangen.
	for dir, items := range dirItems {
		if len(items) != 1 {
			delete(set.byDir, dir)
		}
	}
	for dir, items := range parentItems {
		if len(items) != 1 {
			delete(set.byParentDir, dir)
		}
	}
	return set, nil
}

func parentDir(dir string) string {
	if dir == "" {
		return ""
	}
	parent := path.Dir(dir)
	if parent == "." {
		return ""
	}
	return parent
}

func (s *Scanner) attachSubtitle(ctx context.Context, c *candidate, fileName string, anchors *anchorSet, stats *Stats, log *slog.Logger) error {
	parsed, ok := nameparse.ParseSubtitle(fileName)
	if !ok {
		return nil
	}

	anchor, matched, found := anchors.lookup(c.entry.Dir, parsed.MediaBase, parsed.FullBase)
	if !found {
		return nil
	}
	if matched != "" {
		parsed = withFormat(nameparse.SubtitleAttributes(parsed.FullBase, matched), parsed.Format)
	}

	if err := s.store.AttachSidecar(ctx, c.fileID, c.entry.Size, c.entry.Mtime,
		inodePtr(c.entry.Inode), c.signature, &anchor.versionID, nil, ""); err != nil {
		return err
	}

	format, ok := ffprobe.SubtitleFormatForExtension(path.Ext(fileName))
	if !ok {
		return nil
	}

	stream := ffprobe.Stream{
		Kind:              "subtitle",
		SubtitleFormat:    format,
		Language:          parsed.Language,
		IsDefault:         parsed.Default,
		IsForced:          parsed.Forced,
		IsHearingImpaired: parsed.HearingImpaired,
		Detection:         ffprobe.DetectionMap{},
	}
	// De bestandsnaam is hier de bron, en dat staat er ook zo bij. Hoofdstuk 7.4
	// kent filename als bron; een taal uit een bestandsnaam is afgeleid en geen
	// gelezen veld.
	stream.Detection.Set("subtitle_format", ffprobe.Confirmed, ffprobe.SourceFilename)
	if parsed.Language != "" {
		stream.Detection.Set("language", ffprobe.Inferred, ffprobe.SourceFilename)
	} else {
		stream.Detection.Set("language", ffprobe.Unknown, ffprobe.SourceFilename)
	}

	if err := s.store.ReplaceStreams(ctx, anchor.versionID, c.fileID, []ffprobe.Stream{stream}, true); err != nil {
		return err
	}
	_ = log
	_ = stats
	return nil
}

func (s *Scanner) attachArtwork(ctx context.Context, c *candidate, fileName string, anchors *anchorSet) error {
	parsed, ok := nameparse.ParseArtwork(fileName)
	if !ok {
		return nil
	}
	anchor, _, found := anchors.lookup(c.entry.Dir, parsed.MediaBase, parsed.FullBase)
	if !found {
		return nil
	}
	itemID := anchor.itemID
	return s.store.AttachSidecar(ctx, c.fileID, c.entry.Size, c.entry.Mtime,
		inodePtr(c.entry.Inode), c.signature, nil, &itemID, parsed.Kind)
}

// lookup gaat van precies naar ruim: naast het bestand met dezelfde naam, dan op
// een steeds kortere prefix van de naam, dan de map, dan een map erboven. Levert
// geen ervan iets op, dan hangt de sidecar nergens aan.
func (a *anchorSet) lookup(dir, mediaBase, fullBase string) (mediaAnchor, string, bool) {
	if mediaBase != "" {
		if hit, ok := a.byBase[path.Join(dir, mediaBase)]; ok {
			return hit, mediaBase, true
		}
	}

	// De prefix-terugval vangt wat het ontleden niet kan weten. Op deze
	// bibliotheek staan ".nl.synced.srt" en ".nl_2.srt" naast elkaar, en er is
	// geen lijst van markeringen die alle varianten dekt die iemand ooit heeft
	// bedacht. Wat er wel is: de mediabestanden die in deze map staan. Steeds een
	// punt van achteren afhalen en daartegen matchen raadt niets, het vergelijkt
	// met wat er werkelijk ligt.
	for candidate := fullBase; ; {
		idx := strings.LastIndex(candidate, ".")
		if idx <= 0 {
			break
		}
		candidate = candidate[:idx]
		if hit, ok := a.byBase[path.Join(dir, candidate)]; ok {
			return hit, candidate, true
		}
	}

	if hit, ok := a.byDir[dir]; ok {
		return hit, "", true
	}
	hit, ok := a.byParentDir[dir]
	return hit, "", ok
}

// withFormat houdt het formaat vast dat uit de extensie kwam. SubtitleAttributes
// leest alleen wat er achter de mediabestandsnaam staat en kent de extensie niet.
func withFormat(s nameparse.Subtitle, format string) nameparse.Subtitle {
	s.Format = format
	return s
}
