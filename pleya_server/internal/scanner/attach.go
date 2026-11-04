package scanner

import (
	"context"
	"fmt"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

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

		// Een aflevering zonder nummer heeft geen volgnummer en geen "Episode N" als
		// terugval: de titel is wat haar onderscheidt, en de sortering zet haar
		// achter de genummerde.
		var episodeIndex *int
		title := ep.Title
		if ep.Numbered {
			number := ep.Number
			episodeIndex = &number
			if title == "" {
				title = fmt.Sprintf("Episode %d", number)
			}
		}
		episodeID, created, err := s.store.ResolveItem(ctx, catalog.ItemRef{
			LibraryID:   lib.ID,
			ParentID:    &seasonID,
			Kind:        "episode",
			GroupingKey: ep.GroupingKey(),
			Title:       title,
			SortTitle:   nameparse.SortTitle(title),
			Year:        yearPtr(ep.ShowYear),
			Index:       episodeIndex,
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
