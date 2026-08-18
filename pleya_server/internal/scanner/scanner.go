package scanner

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path"
	"sync"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

// Prober is wat de scanner van ffprobe nodig heeft.
type Prober interface {
	Probe(ctx context.Context, path string) (*ffprobe.Result, error)
}

// Options bundelt de instellingen van een scanner.
type Options struct {
	Store       *catalog.Store
	Prober      Prober
	Logger      *slog.Logger
	Concurrency int

	// ProgressEvery bepaalt hoe vaak de tellers naar de database gaan. Zonder
	// websocket is dat het antwoord op "hangt de scanner of is de NAS traag".
	ProgressEvery time.Duration
}

// Scanner leest bibliotheken in.
type Scanner struct {
	store         *catalog.Store
	prober        Prober
	log           *slog.Logger
	concurrency   int
	progressEvery time.Duration
}

// New bouwt een scanner.
func New(opts Options) *Scanner {
	if opts.Concurrency < 1 {
		opts.Concurrency = 2
	}
	if opts.ProgressEvery <= 0 {
		opts.ProgressEvery = 5 * time.Second
	}
	return &Scanner{
		store:         opts.Store,
		prober:        opts.Prober,
		log:           opts.Logger,
		concurrency:   opts.Concurrency,
		progressEvery: opts.ProgressEvery,
	}
}

// Stats zijn de tellers van één ronde.
type Stats struct {
	FilesSeen       int64
	FilesNew        int64
	FilesRenamed    int64
	FilesChanged    int64
	FilesProbed     int64
	FilesMissing    int64
	BytesHashed     int64
	ItemsCreated    int64
	VersionsCreated int64
	Errors          int64
	LastError       string

	// De inodemeting die PS-0 aan deze fase heeft doorgegeven. Ze zeggen niets
	// over de catalogus en alles over de vraag of de goedkope laag hier op
	// inodes mag bouwen. Ze worden gerapporteerd en niet automatisch omgezet in
	// vertrouwen: een root op vertrouwen zetten is een besluit, geen bijproduct.
	InodesSeen      int64
	InodesDistinct  int64
	InodeMismatches int64
}

// ScanLibrary leest één bibliotheek volledig in.
func (s *Scanner) ScanLibrary(ctx context.Context, lib catalog.Library, trigger string) (Stats, error) {
	roots, err := s.store.StorageLocations(ctx, lib.ID)
	if err != nil {
		return Stats{}, err
	}

	run, err := s.store.StartScanRun(ctx, lib.ID, trigger)
	if err != nil {
		return Stats{}, err
	}

	var stats Stats
	tracker := newProgress(ctx, s.store, run, &stats, s.progressEvery)
	defer tracker.stop()

	log := s.log.With(slog.String("library", lib.Slug), slog.String("scan_run", run.String()))
	log.Info("scan gestart", slog.String("trigger", trigger), slog.Int("roots", len(roots)))
	started := time.Now()

	var scanErr error
	for _, root := range roots {
		if err := s.scanRoot(ctx, lib, root, &stats, tracker, log); err != nil {
			if ctx.Err() != nil {
				scanErr = err
				break
			}
			stats.Errors++
			stats.LastError = err.Error()
			log.Error("root overgeslagen",
				slog.String("root", root.RootPath), slog.String("error", err.Error()))
		}
	}

	if scanErr == nil {
		if err := s.store.PruneEmpty(ctx, lib.ID); err != nil {
			stats.Errors++
			stats.LastError = err.Error()
		}
	}

	state := "succeeded"
	if scanErr != nil {
		state = "cancelled"
		if !errors.Is(scanErr, context.Canceled) {
			state = "failed"
		}
	}
	tracker.stop()
	if err := s.store.FinishScanRun(ctx, run, state, stats.toCatalog()); err != nil {
		log.Warn("scanronde afsluiten mislukt", slog.String("error", err.Error()))
	}

	log.Info("scan klaar",
		slog.String("state", state),
		slog.Duration("duration", time.Since(started)),
		slog.Int64("files_seen", stats.FilesSeen),
		slog.Int64("files_new", stats.FilesNew),
		slog.Int64("files_renamed", stats.FilesRenamed),
		slog.Int64("files_changed", stats.FilesChanged),
		slog.Int64("files_probed", stats.FilesProbed),
		slog.Int64("files_missing", stats.FilesMissing),
		slog.Int64("bytes_hashed", stats.BytesHashed),
		slog.Int64("errors", stats.Errors),
		slog.Int64("inodes_seen", stats.InodesSeen),
		slog.Int64("inodes_distinct", stats.InodesDistinct),
		slog.Int64("inode_mismatches", stats.InodeMismatches),
	)
	return stats, scanErr
}

// action is wat er met een aangetroffen bestand moet gebeuren.
type action int

const (
	actionUnchanged action = iota
	actionNew
	actionChanged
)

// candidate is een bestand met zijn oordeel uit laag 1 en 2.
type candidate struct {
	entry     Entry
	prev      *catalog.File
	fileID    id.ID
	action    action
	renamed   bool
	signature string
}

func (s *Scanner) scanRoot(ctx context.Context, lib catalog.Library, root catalog.StorageLocation, stats *Stats, tracker *progress, log *slog.Logger) error {
	index, err := s.store.LoadFileIndex(ctx, root.ID)
	if err != nil {
		return err
	}

	// Een root die er niet is levert geen enkele waarneming op. Dan hoort er
	// niets als verdwenen aangemerkt te worden: een USB-schijf die even niet
	// gemount is mag geen halve bibliotheek opruimen.
	var entries []Entry
	walkErr := Walk(ctx, root.RootPath, func(e Entry) error {
		entries = append(entries, e)
		stats.FilesSeen++
		tracker.note(e.RelPath)
		return nil
	}, func(p string, err error) {
		stats.Errors++
		stats.LastError = err.Error()
		log.Warn("pad overgeslagen", slog.String("path", p), slog.String("error", err.Error()))
	})
	if walkErr != nil {
		return fmt.Errorf("root %s: %w", root.RootPath, walkErr)
	}
	if len(entries) == 0 && len(index.ByPath) > 0 {
		return fmt.Errorf("root %s leverde geen enkel bestand terwijl er %d bekend zijn; overgeslagen",
			root.RootPath, len(index.ByPath))
	}

	claimed := map[id.ID]bool{}
	seenPaths := make([]string, 0, len(entries))
	inodes := make(map[int64]struct{}, len(entries))
	var media, sidecars []candidate
	var measure inodeMeasurement

	for _, e := range entries {
		seenPaths = append(seenPaths, e.RelPath)
		measure.observe(e, index, inodes)

		c, err := s.judge(root, index, claimed, e, stats)
		if err != nil {
			stats.Errors++
			stats.LastError = err.Error()
			log.Warn("bestand overgeslagen", slog.String("path", e.RelPath), slog.String("error", err.Error()))
			continue
		}

		switch c.action {
		case actionNew:
			stats.FilesNew++
		case actionChanged:
			stats.FilesChanged++
		}
		if c.renamed {
			stats.FilesRenamed++
		}

		if e.Kind == nameparse.KindVideo {
			media = append(media, c)
		} else {
			sidecars = append(sidecars, c)
		}
	}

	if err := s.processMedia(ctx, lib, root, media, stats, log); err != nil {
		return err
	}
	if err := s.processSidecars(ctx, root, media, sidecars, stats, log); err != nil {
		return err
	}

	if n, err := s.store.ClearMissing(ctx, root.ID, seenPaths); err != nil {
		return err
	} else if n > 0 {
		log.Info("bestanden weer aanwezig", slog.Int64("count", n))
	}

	missing, err := s.store.MarkMissing(ctx, root.ID, seenPaths, time.Now().UTC())
	if err != nil {
		return err
	}
	stats.FilesMissing += missing

	stats.InodesSeen += measure.seen
	stats.InodesDistinct += int64(len(inodes))
	stats.InodeMismatches += measure.mismatches
	measure.report(log, root, len(inodes))
	return nil
}

// inodeMeasurement telt wat er over inodes te zeggen valt op deze root.
type inodeMeasurement struct {
	seen       int64
	mismatches int64
	missing    int64
}

func (m *inodeMeasurement) observe(e Entry, index *catalog.FileIndex, distinct map[int64]struct{}) {
	if e.Inode == 0 {
		m.missing++
		return
	}
	m.seen++
	distinct[e.Inode] = struct{}{}

	// Een bekend pad met een andere inode dan de vorige ronde betekent dat de
	// inode hier niets vasthoudt. Dat is de enige meting die het verschil tussen
	// de twee mounts zichtbaar maakt zonder aannames.
	if prev := index.ByPath[e.RelPath]; prev != nil && prev.Inode != nil && *prev.Inode != e.Inode {
		m.mismatches++
	}
}

// report logt de meting per root. Hij verandert niets aan de instelling: welke
// root vertrouwd wordt staat in storage_locations en is een besluit.
func (m *inodeMeasurement) report(log *slog.Logger, root catalog.StorageLocation, distinct int) {
	level := slog.LevelInfo
	if m.mismatches > 0 || (m.seen > 0 && int64(distinct) != m.seen) {
		level = slog.LevelWarn
	}
	log.Log(context.Background(), level, "inodemeting",
		slog.String("root", root.RootPath),
		slog.String("fstype", root.FSType),
		slog.Bool("inode_trusted", root.InodeTrusted),
		slog.String("trust_source", root.TrustSource),
		slog.Int64("files_with_inode", m.seen),
		slog.Int64("files_without_inode", m.missing),
		slog.Int("distinct_inodes", distinct),
		slog.Int64("mismatches_on_known_paths", m.mismatches),
	)
}

// judge past laag 1 en laag 2 toe en zegt wat er met dit bestand moet gebeuren.
func (s *Scanner) judge(root catalog.StorageLocation, index *catalog.FileIndex, claimed map[id.ID]bool, e Entry, stats *Stats) (candidate, error) {
	c := candidate{entry: e}
	c.prev = index.ByPath[e.RelPath]

	// Hernoemd binnen dezelfde context: hetzelfde bestand op een nieuw pad wordt
	// aan zijn inode herkend en houdt zijn id, zijn versie en zijn item. Dat is
	// precies het scenario waarin Plex vandaag een dubbele entry maakt.
	if c.prev == nil && root.InodeTrusted && e.Inode != 0 {
		if cand, ok := index.ByInode[e.Inode]; ok && cand != nil && !claimed[cand.ID] && cand.Role == roleFor(e.Kind) {
			c.prev, c.renamed = cand, true
		}
	}

	if c.prev == nil {
		c.action = actionNew
		c.fileID = id.New()
		// Op een root zonder betrouwbare inodes is de signature het enige spoor
		// waarlangs een hernoeming nog te herkennen is. Hij wordt daar toch al
		// voor elk bestand berekend, dus dat kost niets extra.
		if !root.InodeTrusted {
			sig, hashed, err := Signature(path.Join(root.RootPath, e.RelPath), e.Size)
			if err != nil {
				return c, err
			}
			stats.BytesHashed += hashed
			c.signature = sig
			if cand := index.BySignature(sig, e.Size); cand != nil && !claimed[cand.ID] && cand.Role == roleFor(e.Kind) {
				c.prev, c.renamed = cand, true
			}
		}
	}

	if c.prev == nil {
		return c, nil
	}

	claimed[c.prev.ID] = true
	c.fileID = c.prev.ID

	layerOneSame := c.prev.SizeBytes == e.Size && c.prev.MtimeUnix == e.Mtime &&
		(c.prev.Inode == nil || e.Inode == 0 || *c.prev.Inode == e.Inode)

	if root.InodeTrusted && layerOneSame && c.prev.IsAttached() {
		c.action = actionUnchanged
		return c, nil
	}

	// Laag 2. De drieslag is veranderd, of de inode is hier niet te vertrouwen.
	// Komt de hash overeen, dan is het bestand *waarschijnlijk* ongewijzigd, en
	// dat woord is het hele punt van hoofdstuk 7.2.
	if c.signature == "" {
		sig, hashed, err := Signature(path.Join(root.RootPath, e.RelPath), e.Size)
		if err != nil {
			return c, err
		}
		stats.BytesHashed += hashed
		c.signature = sig
	}

	// Ongewijzigd betekent hier twee dingen tegelijk: dezelfde bytes voor zover
	// laag 2 dat kan zeggen, én al ergens aan gehangen. Een bestand dat nergens
	// aan hangt hoort elke ronde opnieuw een kans te krijgen, want de media
	// ernaast kan er inmiddels wel zijn.
	if c.prev.Signature != "" && c.prev.Signature == c.signature && c.prev.IsAttached() {
		c.action = actionUnchanged
		return c, nil
	}
	c.action = actionChanged
	return c, nil
}

func roleFor(kind nameparse.Kind) catalog.FileRole {
	switch kind {
	case nameparse.KindVideo:
		return catalog.RoleMedia
	case nameparse.KindSubtitle:
		return catalog.RoleSubtitle
	default:
		return catalog.RoleArtwork
	}
}

// probeResult koppelt een analyse aan het bestand waar hij bij hoort.
type probeResult struct {
	index  int
	result *ffprobe.Result
	err    error
}

func (s *Scanner) processMedia(ctx context.Context, lib catalog.Library, root catalog.StorageLocation, media []candidate, stats *Stats, log *slog.Logger) error {
	todo := make([]int, 0, len(media))
	for i, c := range media {
		if c.action == actionUnchanged {
			continue
		}
		todo = append(todo, i)
	}

	// Analyseren gebeurt parallel en wegschrijven serieel. ffprobe is op een NAS
	// vooral wachten op de schijf; de database is de plek waar volgorde telt.
	results := make([]probeResult, len(media))
	var wg sync.WaitGroup
	work := make(chan int)

	for w := 0; w < s.concurrency; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range work {
				abs := path.Join(root.RootPath, media[i].entry.RelPath)
				res, err := s.prober.Probe(ctx, abs)
				results[i] = probeResult{index: i, result: res, err: err}
			}
		}()
	}

	go func() {
		defer close(work)
		for _, i := range todo {
			select {
			case <-ctx.Done():
				return
			case work <- i:
			}
		}
	}()
	wg.Wait()

	if err := ctx.Err(); err != nil {
		return err
	}

	touchedVersions := map[id.ID]bool{}

	for i := range media {
		c := &media[i]
		if c.action == actionUnchanged {
			if c.renamed {
				if err := s.store.MoveFile(ctx, c.fileID, c.entry.RelPath); err != nil {
					return err
				}
			}
			continue
		}

		if c.action == actionNew {
			if err := s.store.InsertFile(ctx, &catalog.File{
				ID:                c.fileID,
				StorageLocationID: root.ID,
				RelativePath:      c.entry.RelPath,
				Role:              catalog.RoleMedia,
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

		res := results[i]
		if res.err != nil {
			// Een bestand dat tijdens de ronde verdwijnt is geen analysefout. Het
			// wordt zo meteen als verdwenen aangemerkt, net als elk ander pad dat
			// deze ronde niet is gezien.
			if errors.Is(res.err, fs.ErrNotExist) || errors.Is(res.err, os.ErrNotExist) {
				log.Info("bestand verdween tijdens de scan", slog.String("path", c.entry.RelPath))
				continue
			}
			stats.Errors++
			stats.LastError = res.err.Error()
			log.Warn("analyse mislukt",
				slog.String("path", c.entry.RelPath), slog.String("error", res.err.Error()))
			if err := s.store.RecordProbeFailure(ctx, c.fileID, c.entry.Size, c.entry.Mtime,
				inodePtr(c.entry.Inode), c.signature, res.err.Error()); err != nil {
				return err
			}
			continue
		}
		stats.FilesProbed++

		versionID, partIndex, err := s.attach(ctx, lib, c.entry, res.result, stats)
		if err != nil {
			stats.Errors++
			stats.LastError = err.Error()
			log.Warn("koppelen mislukt",
				slog.String("path", c.entry.RelPath), slog.String("error", err.Error()))
			continue
		}

		if err := s.store.RecordProbe(ctx, c.fileID, c.entry.Size, c.entry.Mtime,
			inodePtr(c.entry.Inode), c.signature, res.result.DurationMs, versionID, partIndex); err != nil {
			return err
		}

		// Alleen het eerste deel levert de sporen. Bij een gestapelde versie
		// dragen de delen dezelfde sporen, en ze allemaal wegschrijven zou elk
		// spoor dubbel op de lijn zetten.
		if partIndex == 0 {
			if err := s.store.ReplaceStreams(ctx, versionID, c.fileID, res.result.Streams, false); err != nil {
				return err
			}
		}
		touchedVersions[versionID] = true
	}

	for versionID := range touchedVersions {
		if err := s.store.RecomputeVersionDuration(ctx, versionID); err != nil {
			return err
		}
	}
	return nil
}

// attach maakt of vindt het item en de versie waar dit bestand bij hoort.
func (s *Scanner) attach(ctx context.Context, lib catalog.Library, e Entry, res *ffprobe.Result, stats *Stats) (id.ID, int, error) {
	probed := catalog.ProbedVersion{
		Container:  res.Container,
		DurationMs: res.DurationMs,
		BitrateBps: res.BitrateBps,
		Detection:  res.Detection,
		Streams:    res.Streams,
	}

	switch lib.Kind {
	case "movies":
		m := nameparse.ParseMovie(e.RelPath)
		if m.Title == "" {
			return id.Nil, 0, fmt.Errorf("geen titel af te leiden uit %s", e.RelPath)
		}
		itemID, created, err := s.store.ResolveItem(ctx, catalog.ItemRef{
			LibraryID:   lib.ID,
			Kind:        "movie",
			GroupingKey: nameparse.ItemKey(m.Title, yearKey(m.Year)),
			Title:       m.Title,
			SortTitle:   nameparse.SortTitle(m.Title),
			Year:        yearPtr(m.Year),
		})
		if err != nil {
			return id.Nil, 0, err
		}
		if created {
			stats.ItemsCreated++
		}
		versionID, vCreated, err := s.store.ResolveVersion(ctx, itemID, m.VersionKey, probed, m.Edition)
		if err != nil {
			return id.Nil, 0, err
		}
		if vCreated {
			stats.VersionsCreated++
		}
		return versionID, m.PartIndex, nil

	case "shows":
		ep := nameparse.ParseEpisode(e.RelPath)
		if !ep.OK {
			return id.Nil, 0, fmt.Errorf("geen aflevering af te leiden uit %s", e.RelPath)
		}

		showID, created, err := s.store.ResolveItem(ctx, catalog.ItemRef{
			LibraryID:   lib.ID,
			Kind:        "show",
			GroupingKey: nameparse.ItemKey(ep.Show),
			Title:       ep.Show,
			SortTitle:   nameparse.SortTitle(ep.Show),
			Year:        yearPtr(ep.ShowYear),
		})
		if err != nil {
			return id.Nil, 0, err
		}
		if created {
			stats.ItemsCreated++
		}

		seasonNumber := ep.Season
		seasonID, created, err := s.store.ResolveItem(ctx, catalog.ItemRef{
			LibraryID:   lib.ID,
			ParentID:    &showID,
			Kind:        "season",
			GroupingKey: fmt.Sprintf("%d", seasonNumber),
			Title:       seasonTitle(seasonNumber),
			SortTitle:   seasonTitle(seasonNumber),
			Index:       &seasonNumber,
		})
		if err != nil {
			return id.Nil, 0, err
		}
		if created {
			stats.ItemsCreated++
		}

		number := ep.Number
		title := ep.Title
		if title == "" {
			title = fmt.Sprintf("Episode %d", number)
		}
		episodeID, created, err := s.store.ResolveItem(ctx, catalog.ItemRef{
			LibraryID:   lib.ID,
			ParentID:    &seasonID,
			Kind:        "episode",
			GroupingKey: fmt.Sprintf("%d", number),
			Title:       title,
			SortTitle:   nameparse.SortTitle(title),
			Year:        yearPtr(ep.ShowYear),
			Index:       &number,
		})
		if err != nil {
			return id.Nil, 0, err
		}
		if created {
			stats.ItemsCreated++
		}

		versionID, vCreated, err := s.store.ResolveVersion(ctx, episodeID, ep.VersionKey, probed, ep.Edition)
		if err != nil {
			return id.Nil, 0, err
		}
		if vCreated {
			stats.VersionsCreated++
		}
		return versionID, ep.PartIndex, nil

	default:
		return id.Nil, 0, fmt.Errorf("onbekende bibliotheeksoort %q", lib.Kind)
	}
}

func seasonTitle(n int) string {
	if n == 0 {
		return "Specials"
	}
	return fmt.Sprintf("Season %d", n)
}

func yearKey(year int) string {
	if year == 0 {
		return ""
	}
	return fmt.Sprintf("%d", year)
}

func yearPtr(year int) *int {
	if year == 0 {
		return nil
	}
	return &year
}

func inodePtr(v int64) *int64 {
	if v == 0 {
		return nil
	}
	return &v
}

func (s Stats) toCatalog() catalog.ScanCounters {
	return catalog.ScanCounters{
		FilesSeen:       s.FilesSeen,
		FilesNew:        s.FilesNew,
		FilesRenamed:    s.FilesRenamed,
		FilesChanged:    s.FilesChanged,
		FilesProbed:     s.FilesProbed,
		FilesMissing:    s.FilesMissing,
		BytesHashed:     s.BytesHashed,
		ItemsCreated:    s.ItemsCreated,
		VersionsCreated: s.VersionsCreated,
		Errors:          s.Errors,
		LastError:       s.LastError,
	}
}
