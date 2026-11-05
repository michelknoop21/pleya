package metadata

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// episodeStore en episodeProvider zijn optioneel: een store of provider zonder
// afleveringen (de nep-implementaties in oudere tests, een tweede provider)
// laat de serieronde zoals hij was.
type episodeStore interface {
	ShowEpisodes(ctx context.Context, showID id.ID) ([]catalog.ShowEpisode, error)
}

type episodeProvider interface {
	SeasonEpisodes(ctx context.Context, showID, season int) ([]SeasonEpisode, error)
}

// showEpisodes haalt bij een gematchte serie per seizoen de stills en titels van
// haar afleveringen. Alle provider-I/O gebeurt hier, vóór de publicatie; die
// loopt onder de itemlock en generatieguard van de serie (CommitMetadata).
//
// Een aflevering met een eigen -thumb.jpg of pin krijgt geen providerstill. Een
// seizoen dat niet te lezen was ontbreekt in de uitkomst en blijft dus staan
// zoals het was. retry is het vroegste moment voor een nieuwe poging: snel na
// een fout, na een week als de provider nog geen still of titel heeft.
func (r *Runner) showEpisodes(ctx context.Context, t catalog.MetadataTarget, tmdbID int) ([]catalog.EpisodeMetadata, []preparedArtwork, *time.Time) {
	es, okStore := r.store.(episodeStore)
	ep, okProvider := r.provider.(episodeProvider)
	if !okStore || !okProvider || tmdbID <= 0 {
		return nil, nil, nil
	}
	var retry *time.Time
	later := func(d time.Duration) {
		if n := time.Now().Add(d); retry == nil || n.Before(*retry) {
			retry = &n
		}
	}
	list, err := es.ShowEpisodes(ctx, t.ID)
	if err != nil {
		r.log.Warn("afleveringen lezen mislukt", slog.String("title", t.Title), slog.String("error", err.Error()))
		later(r.retryArtwork)
		return nil, nil, retry
	}

	var out []catalog.EpisodeMetadata
	var prepared []preparedArtwork
	for start := 0; start < len(list); {
		season := list[start].Season
		end := start
		for end < len(list) && list[end].Season == season {
			end++
		}
		eps := list[start:end]
		start = end
		if ctx.Err() != nil {
			break
		}

		got, err := withBackoff(ctx, r, func() ([]SeasonEpisode, error) {
			return ep.SeasonEpisodes(ctx, tmdbID, season)
		})
		if err != nil && !errors.Is(err, catalog.ErrNotFound) {
			r.log.Warn("seizoen ophalen mislukt", slog.String("title", t.Title),
				slog.Int("season", season), slog.String("error", err.Error()))
			later(r.retryArtwork)
			continue
		}
		// Een seizoen dat de provider niet kent, heeft daar ook geen stills.
		byNumber := map[int]SeasonEpisode{}
		for _, g := range got {
			byNumber[g.Number] = g
		}
		for _, e := range eps {
			found := byNumber[e.Number]
			u := catalog.EpisodeMetadata{ItemID: e.ID, PreviousTitle: e.Title}
			if titleCorrectable(e) && found.Name != "" && !placeholderEpisodeTitle(found.Name, e.Number) {
				u.Title = found.Name
			} else if titleCorrectable(e) && placeholderEpisodeTitle(e.Title, e.Number) {
				later(r.retryUnmatch)
			}
			if !e.LocalPoster {
				u.StillRef = found.StillRef
				if u.StillRef == "" {
					later(r.retryUnmatch)
				}
			}
			if u.StillRef != "" {
				saved, err := r.prepareImageAs(ctx, e.ID, "poster", "still", u.StillRef)
				if err != nil {
					r.log.Warn("still ophalen mislukt", slog.String("title", t.Title),
						slog.String("episode", e.Title), slog.String("error", err.Error()))
					later(r.retryArtwork)
				} else if saved != nil {
					prepared = append(prepared, *saved)
				}
			}
			out = append(out, u)
		}
	}
	return out, prepared, retry
}

// titleCorrectable: een handmatige titel blijft altijd staan (S22.5). Een titel
// die de provider eerder zette, volgt de provider; een titel uit de bestandsnaam
// alleen als het een plaatshouder is.
func titleCorrectable(e catalog.ShowEpisode) bool {
	switch e.TitleSource {
	case catalog.SourceManual:
		return false
	case ProviderTMDB:
		return true
	}
	return placeholderEpisodeTitle(e.Title, e.Number)
}

// placeholderEpisodeTitle herkent een titel die nog niets zegt: "TBA" van Sonarr
// bij een aflevering die nog geen naam heeft, of de terugval "Episode N" van de
// scanner (die TMDB zelf ook geeft zolang er geen naam is).
func placeholderEpisodeTitle(title string, number int) bool {
	t := strings.ToLower(strings.TrimSpace(title))
	switch t {
	case "", "tba", "tbd", "tba.", "to be announced":
		return true
	}
	return t == fmt.Sprintf("episode %d", number) || t == fmt.Sprintf("aflevering %d", number)
}
