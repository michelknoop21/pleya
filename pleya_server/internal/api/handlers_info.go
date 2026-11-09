package api

import "net/http"

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	setupRequired, err := s.opts.Auth.SetupRequired(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	writeJSON(w, http.StatusOK, Info{
		Protocol: InfoProtocol{
			Major:        1,
			FeatureLevel: FeatureLevel,
			Profile:      "full",
		},
		Server: InfoServer{
			ID: s.opts.ServerID.String(),
			// SetupAcceptsName hangt aan de opslag en niet aan een constante
			// (J.2 rij 10). server_name bij setup is de instelling server_name,
			// en zonder server_settings-tabel is er niets om hem in te
			// bewaren; dan is "ja, stuur maar" een belofte die de volgende
			// aanvraag alweer kwijt is.
			SetupAcceptsName: s.opts.Settings != nil && s.opts.Settings.HasStore(),
		},
		Capabilities: Capabilities{
			AssistantMemory: s.opts.Memory != nil,
			Browse:          true,
			Search:          true,
			Artwork:         true,
			// ArtworkSizes: de ladder bestaat zodra ffmpeg en een cachemap er zijn.
			ArtworkSizes:      s.opts.Artwork.Available(),
			ArtworkCacheAdmin: s.artworkCacheAdminAvailable(),
			// LibraryMaintenance: legen gaat via de wachtrij, net als de scan.
			LibraryMaintenance: s.opts.Jobs != nil,
			// Filters: D1 is gebouwd, dus de parameters en de facetten bestaan.
			Filters: true,
			// ExternalIDLookup: de filterparameter external_id en het itemveld bestaan.
			ExternalIDLookup:        true,
			AppliedExternalIdentity: true,
			MetadataMatchStatus:     true,
			MetadataSearch:          s.opts.MetadataProvider != nil,
			MetadataOverrides:       s.opts.Catalog != nil,
			ArtworkChoices:          s.pins.Available(),
			// S20: de persoonlijke laag bestaat zodra de opslag er is.
			History:          s.opts.Personal != nil,
			Favorites:        s.opts.Personal != nil,
			Ratings:          s.opts.Personal != nil,
			TrackPreferences: s.opts.Personal != nil,
			PersonalData:     s.opts.Personal != nil,
			// S19: de routes bestaan altijd, de catalogus levert ze.
			Collections: true,
			Playlists:   true,
			// Activiteit van het huishouden, op dezelfde opslag.
			ItemActivity: s.opts.Personal != nil,
			// Vanaf PS-4 staat kijkstatus aan, en met het eigendomsmodel eronder.
			// De vlaggen hangen aan de aanwezigheid van de opslag: een server die
			// zonder watch-store draait zegt dat eerlijk in plaats van een
			// endpoint aan te bieden dat op een nil-pointer klapt.
			WatchState:          s.opts.Watch != nil,
			WatchStateOwnership: s.opts.Watch != nil,
			WatchStateCopy:      s.opts.Watch != nil,
			StreamSessions:      true,
			// PlaybackPlan: S17 is gebouwd, POST /playback/plan bestaat.
			PlaybackPlan:           true,
			PlaybackQuality:        s.transcodeEnabled(),
			EmbeddedSubtitles:      s.transcodeEnabled(),
			PlaybackSubtitles:      s.transcodeEnabled(),
			PlaybackAudioSelection: s.transcodeEnabled(),
			// Transcode: aan zodra er een manager met sessies is (S18).
			Transcode: s.transcodeEnabled(),
			Downloads: s.opts.Downloads != nil && s.opts.Jobs != nil,
			// Backups: S25, zodra de service en de wachtrij er zijn.
			Backups:  s.opts.Backups != nil && s.opts.Jobs != nil,
			LiveTV:   false,
			Realtime: false,
			// Users: de vijf endpoints uit DEC-121 staan er sinds stap 4, en
			// login kent sindsdien elke rij in users en niet alleen de owner.
			Users: true,
			// Sessions: aan sinds stap 6. Het schema en de tokenketen kwamen in
			// stap 2; GET/DELETE /sessions, POST /auth/logout en het
			// intrekkingsregister maken de belofte pas waar.
			Sessions: true,
			// APITokens: aan sinds S1.5. POST en GET /auth/api-tokens bestaan,
			// en Session draagt kind en scope.
			APITokens: true,
			// CookieAuth: aan sinds S1.8. Login en refresh kennen
			// credential_mode en zetten het refreshcredential desgevraagd in een
			// HttpOnly-cookie (RB-29).
			CookieAuth: true,
			// CookieUpgrade: refresh ruilt een token uit localStorage in voor de
			// cookie, zonder nieuwe login (17d.1).
			CookieUpgrade: true,
			// Administration: aan sinds S1.6, voor het oppervlak dat S1.2 tot
			// en met S1.5 hebben gebouwd (J.2 rij 1).
			Administration: true,
			// MCP volgt de lokale instelling; de proef biedt alleen geclassificeerde leestools.
			MCP: s.mcpEnabled(),
		},
		Auth: InfoAuth{
			Methods:       []string{"password"},
			SetupRequired: setupRequired,
		},
	})
}
