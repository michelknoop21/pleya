package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func (s *Server) handleLibraries(w http.ResponseWriter, r *http.Request) {
	libs, err := s.opts.Catalog.Libraries(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	// Een lege lijst is [] en nooit null.
	out := LibraryList{Items: make([]Library, 0, len(libs))}
	for _, l := range libs {
		out.Items = append(out.Items, Library{
			ID:        l.ID.String(),
			Title:     l.Title,
			Kind:      l.Kind,
			ItemCount: l.ItemCount,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleLibraryItems(w http.ResponseWriter, r *http.Request) {
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}

	lib, err := s.opts.Catalog.Library(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}

	sort, ok := catalog.ParseSort(r.URL.Query().Get("sort"), catalog.SortTitle)
	if !ok {
		writeError(w, s.log, CodeCursorInvalid, "unknown sort order", nil)
		return
	}

	cursor, err := catalog.DecodeCursor(r.URL.Query().Get("cursor"), sort)
	if err != nil {
		writeError(w, s.log, CodeCursorInvalid, err.Error(), nil)
		return
	}

	// Een bibliotheek van soort shows levert uitsluitend items met kind show.
	// Seizoenen en afleveringen bereikt u via /items/{id}/children.
	kinds := []string{"movie"}
	if lib.Kind == "shows" {
		kinds = []string{"show"}
	}

	limit, _ := queryInt(r, "limit")
	page, err := s.opts.Catalog.Items(r.Context(), catalog.Query{
		LibraryID: &libraryID,
		Kinds:     kinds,
		Sort:      sort,
		Cursor:    cursor,
		Limit:     limit,
	})
	if err != nil {
		s.writeStoreError(w, err)
		return
	}

	total, err := s.opts.Catalog.ItemCount(r.Context(), &libraryID, kinds)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, &total)))
}

func (s *Server) handleItem(w http.ResponseWriter, r *http.Request) {
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}

	item, err := s.opts.Catalog.Item(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	// hydrateItems werkt op een slice omdat elke andere aanroeper er een heeft;
	// een detailscherm is de uitzondering van één.
	single := []Item{mapItem(item)}
	s.hydrateItems(r, single)
	writeJSON(w, http.StatusOK, single[0])
}

func (s *Server) handleChildren(w http.ResponseWriter, r *http.Request) {
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}

	// Bestaat het item niet, dan is dat een 404. Voor een film is het antwoord
	// een lege lijst en geen fout: die heeft geen kinderen, maar hij bestaat wel.
	if _, err := s.opts.Catalog.Item(r.Context(), itemID); err != nil {
		s.writeStoreError(w, err)
		return
	}

	cursor, err := catalog.DecodeCursor(r.URL.Query().Get("cursor"), catalog.SortIndex)
	if err != nil {
		writeError(w, s.log, CodeCursorInvalid, err.Error(), nil)
		return
	}

	limit, _ := queryInt(r, "limit")
	page, err := s.opts.Catalog.Items(r.Context(), catalog.Query{
		ParentID: &itemID,
		Sort:     catalog.SortIndex,
		Cursor:   cursor,
		Limit:    limit,
	})
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, nil)))
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	term := strings.TrimSpace(r.URL.Query().Get("q"))
	if term == "" {
		writeError(w, s.log, CodeSearchQueryEmpty, "q is required", nil)
		return
	}

	// Zonder kind levert zoeken movie, show en episode. Een seizoen heet
	// "Season 3" en draagt niets van wat iemand intypt, dus het matcht alleen op
	// termen die toevallig in het woord Season zitten, en dan komen ze met
	// honderden tegelijk. Wie ze wil vraagt er met kind=season om; verder staan
	// ze in de kinderen van hun serie. Zie DEC-045.
	kinds := searchDefaultKinds
	if kind := strings.TrimSpace(r.URL.Query().Get("kind")); kind != "" {
		if !isItemKind(kind) {
			// Een onbekende soort levert geen treffers op, en dat is geen fout.
			writeJSON(w, http.StatusOK, ItemPage{Items: []Item{}})
			return
		}
		kinds = []string{kind}
	}

	cursor, err := catalog.DecodeCursor(r.URL.Query().Get("cursor"), catalog.SortTitle)
	if err != nil {
		writeError(w, s.log, CodeCursorInvalid, err.Error(), nil)
		return
	}

	limit, _ := queryInt(r, "limit")
	page, err := s.opts.Catalog.Items(r.Context(), catalog.Query{
		Search: term,
		Kinds:  kinds,
		Sort:   catalog.SortTitle,
		Cursor: cursor,
		Limit:  limit,
	})
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	// Geen total_estimate bij zoeken: dat zou een telling over de hele
	// bibliotheek per pagina vragen, en een schatting die duurder is dan de
	// pagina zelf is geen schatting meer.
	writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, nil)))
}

func (s *Server) handleHub(w http.ResponseWriter, r *http.Request) {
	hub := r.PathValue("hub_id")

	var libraryID *id.ID
	if raw := strings.TrimSpace(r.URL.Query().Get("library_id")); raw != "" {
		parsed, err := id.Parse(raw)
		if err != nil {
			writeError(w, s.log, CodeNotFound, "library not found", nil)
			return
		}
		if _, err := s.opts.Catalog.Library(r.Context(), parsed); err != nil {
			s.writeStoreError(w, err)
			return
		}
		libraryID = &parsed
	}

	switch hub {
	case "recently_added":
		cursor, err := catalog.DecodeCursor(r.URL.Query().Get("cursor"), catalog.SortAddedAtDesc)
		if err != nil {
			writeError(w, s.log, CodeCursorInvalid, err.Error(), nil)
			return
		}
		limit, _ := queryInt(r, "limit")
		page, err := s.opts.Catalog.Items(r.Context(), catalog.Query{
			LibraryID: libraryID,
			Kinds:     []string{"movie", "episode"},
			Sort:      catalog.SortAddedAtDesc,
			Cursor:    cursor,
			Limit:     limit,
		})
		if err != nil {
			s.writeStoreError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, nil)))

	case "continue_watching", "next_up":
		// Een server zonder kijkstatus levert lege lijsten, geen fout. Dat is de
		// normale toestand van een catalogusserver die nog niet kan afspelen, en
		// de specificatie zegt dat met zoveel woorden.
		writeJSON(w, http.StatusOK, ItemPage{Items: []Item{}})

	default:
		writeError(w, s.log, CodeNotFound, "unknown hub", nil)
	}
}

// searchDefaultKinds is de verzameling die een zoekopdracht zonder kind levert.
var searchDefaultKinds = []string{"movie", "show", "episode"}

func isItemKind(kind string) bool {
	switch kind {
	case "movie", "show", "season", "episode":
		return true
	default:
		return false
	}
}

// pathID leest een id uit het pad. Een id is voor de client ondoorzichtig, maar
// hij komt hier terug en dan moet hij kloppen.
func (s *Server) pathID(w http.ResponseWriter, r *http.Request, name string) (id.ID, bool) {
	parsed, err := id.Parse(r.PathValue(name))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return id.Nil, false
	}
	return parsed, true
}

func (s *Server) writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, catalog.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case errors.Is(err, catalog.ErrCursorInvalid):
		writeError(w, s.log, CodeCursorInvalid, err.Error(), nil)
	default:
		writeInternal(w, s.log, err)
	}
}
