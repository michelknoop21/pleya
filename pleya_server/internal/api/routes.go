package api

import (
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/web"
)

// route is één registratie in de mux: het patroon en de handler die erachter
// hangt.
//
// De mux wordt uitsluitend uit deze tabel gevuld (routes() hieronder is de
// enige plek in dit pakket die s.mux.Handle aanroept), en dat is de reden dat
// het type bestaat. K rij 1 van het securityplan eist een test die *alle*
// routes langsloopt en vaststelt dat alleen de publieke lijst zonder token
// antwoordt. http.ServeMux geeft zijn patronen niet terug, dus zonder deze
// tabel zou zo'n test een eigen lijst moeten bijhouden, en dan toetst hij
// alleen de routes waar iemand aan gedacht heeft: precies de routes die geen
// probleem zijn. Nu valt een nieuwe route er vanzelf in.
type route struct {
	pattern string
	handler http.Handler
}

// publicPatterns is de lijst uit K rij 1: de patronen die zonder credential
// antwoorden, met per patroon de reden. Alles wat er niet in staat hoort 401 te
// geven, en routes_internal_test.go loopt de tabel hierboven langs om dat te
// toetsen.
//
// Eén plek in server.go en één test, zoals het securityplan het beschrijft. Een
// route hieraan toevoegen is daarmee een zichtbare handeling in een review, en
// niet iets dat volgt uit het weglaten van middleware.
//
// De laatste twee zijn geen endpoint en staan er daarom met hun reden bij. "/"
// is de meegeleverde webclient: statische bestanden die per definitie vóór het
// inloggen geladen worden. "/pleya/v1/" is de terugval voor een onbekend
// protocolpad; hij voert niets uit en antwoordt library.not_found, zodat een
// client de foutvorm van het protocol krijgt in plaats van HTML.
var publicPatterns = map[string]string{
	"GET /healthz":                "leefbaarheid, buiten het protocol",
	"GET /readyz":                 "gereedheid, buiten het protocol",
	"GET /pleya/v1/info":          "klasse public: wat deze server is en of setup nog moet",
	"POST /pleya/v1/auth/setup":   "klasse public: de eerste eigenaar bestaat nog niet",
	"POST /pleya/v1/auth/login":   "klasse public: het credential wordt hier gemaakt",
	"POST /pleya/v1/auth/refresh": "klasse public: het refreshtoken is zelf het bewijs",
	"/":                           "de meegeleverde webclient; statische bestanden, geen handeling",
	"/pleya/v1/":                  "terugval voor een onbekend protocolpad; voert niets uit",
}

// routes vult de mux uit routeTable en doet verder niets.
//
// De splitsing is er zodat een test dezelfde tabel kan lezen die de mux heeft
// gevuld. Wie hier een tweede s.mux.Handle bijzet haalt die route uit de
// enumeratie van K rij 1, en daarmee uit de test die bewijst dat hij een token
// vraagt.
func (s *Server) routes() {
	for _, rt := range s.routeTable() {
		s.mux.Handle(rt.pattern, rt.handler)
	}
}

func (s *Server) routeTable() []route {
	const p = "/pleya/v1"

	table := []route{
		// Operationeel, buiten het protocol. /healthz zegt of het proces leeft en
		// wordt niet rood van een database die even weg is; /readyz wordt pas groen
		// als de migraties gedraaid zijn.
		{"GET /healthz", http.HandlerFunc(s.handleHealthz)},
		{"GET /readyz", http.HandlerFunc(s.handleReadyz)},

		// Klasse public.
		{"GET " + p + "/info", http.HandlerFunc(s.handleInfo)},
		{"POST " + p + "/auth/setup", http.HandlerFunc(s.handleSetup)},
		{"POST " + p + "/auth/login", http.HandlerFunc(s.handleLogin)},
		{"POST " + p + "/auth/refresh", http.HandlerFunc(s.handleRefresh)},

		// Klasse authenticated.
		{"POST " + p + "/auth/stream-token", s.authenticated(s.handleStreamToken)},
		{"POST " + p + "/auth/stream-session", s.authenticated(s.handleStreamSession)},
		{"GET " + p + "/server", s.authenticated(s.handleServer)},
		{"GET " + p + "/libraries", s.authenticated(s.handleLibraries)},

		// Bibliotheekbeheer (S2.2, J.3 venster 2, matrixregels 28 tot en met
		// 30). Klasse admin, en net als bij instellingen en gebruikersbeheer
		// staat die klasse in de handler: requireAdmin schrijft de 404 die een
		// niet-beheerder hoort te zien.
		{"POST " + p + "/libraries", s.authenticated(s.handleCreateLibrary)},
		{"PATCH " + p + "/libraries/{library_id}", s.authenticated(s.handleUpdateLibrary)},
		{"DELETE " + p + "/libraries/{library_id}", s.authenticated(s.handleDeleteLibrary)},
		{"POST " + p + "/libraries/{library_id}/adopt", s.authenticated(s.handleAdoptLibrary)},

		// Opslag (S2.3, J.3 venster 2, matrixregels 31 en 32). Klasse admin,
		// zelfde vorm als hierboven.
		{"GET " + p + "/storage/roots", s.authenticated(s.handleStorageRoots)},
		{"POST " + p + "/storage/roots/recheck", s.authenticated(s.handleRecheckStorageRoots)},

		// Scans en jobs (S2.4, J.3 venster 2, matrixregels 33 tot en met 38).
		// Klasse admin, in de handler zoals hierboven.
		{"POST " + p + "/libraries/{library_id}/scan", s.authenticated(s.handleStartScan)},
		{"GET " + p + "/scans", s.authenticated(s.handleListScans)},
		{"GET " + p + "/scans/{scan_id}", s.authenticated(s.handleGetScan)},
		{"GET " + p + "/jobs", s.authenticated(s.handleListJobs)},
		{"POST " + p + "/jobs/{job_id}/cancel", s.authenticated(s.handleCancelJob)},
		{"POST " + p + "/jobs/{job_id}/retry", s.authenticated(s.handleRetryJob)},

		// Metadata (venster 3, B5 en S22.5, matrixregels 41 tot en met 44). Klasse
		// admin, in de handler zoals hierboven.
		{"GET " + p + "/libraries/{library_id}/metadata-coverage", s.authenticated(s.handleMetadataCoverage)},
		{"GET " + p + "/metadata/attention", s.authenticated(s.handleMetadataAttention)},
		{"PUT " + p + "/items/{item_id}/metadata-match", s.authenticated(s.handleSetMetadataMatch)},
		{"DELETE " + p + "/items/{item_id}/metadata-match", s.authenticated(s.handleClearMetadataMatch)},

		{"GET " + p + "/libraries/{library_id}/items", s.authenticated(s.handleLibraryItems)},
		{"GET " + p + "/libraries/{library_id}/facets", s.authenticated(s.handleLibraryFacets)},

		// Afspeelplan (venster 5 deel 1, S17, matrixregel 46). Klasse
		// authenticated met dezelfde bibliotheekautorisatie als het item.
		{"POST " + p + "/playback/plan", s.authenticated(s.handlePlaybackPlan)},

		// Omzetsessies (venster 5 deel 2, S18, matrixregels 47 tot en met 49).
		// De hartslag en het stoppen horen bij de eigenaar van de sessie; de
		// bestanden gaan als de bytes van een stream: bearer, streamtoken of
		// browser-streamsessie.
		{"POST " + p + "/playback/sessions/{session_id}/heartbeat", s.authenticated(s.handlePlaybackHeartbeat)},
		{"DELETE " + p + "/playback/sessions/{session_id}", s.authenticated(s.handlePlaybackStop)},
		{"GET " + p + "/playback/sessions/{session_id}/{file}", s.streamAuthorized(s.handlePlaybackFile)},

		// BP-08b: alleen het eigen account, uitsluitend een sessiebearer.
		{"GET " + p + "/users/me/memory", s.authenticated(s.handleGetMemory)},
		{"PUT " + p + "/users/me/memory", s.authenticated(s.handlePutMemory)},
		{"POST " + p + "/users/me/memory/clear", s.authenticated(s.handleClearMemory)},

		// De persoonlijke laag (venster 6 deel 2, S20, matrixregels 52 tot en met 60).
		// Alles klasse authenticated, over de aanvrager zelf; een item buiten de
		// bibliotheken van de aanvrager is een 404.
		{"GET " + p + "/history", s.authenticated(s.handleHistory)},
		{"GET " + p + "/favorites", s.authenticated(s.handleListFavorites)},
		{"PUT " + p + "/favorites/{item_id}", s.authenticated(s.handleSetFavorite)},
		{"DELETE " + p + "/favorites/{item_id}", s.authenticated(s.handleClearFavorite)},
		{"PUT " + p + "/ratings/{item_id}", s.authenticated(s.handleSetRating)},
		{"DELETE " + p + "/ratings/{item_id}", s.authenticated(s.handleClearRating)},
		{"GET " + p + "/track-preferences/{item_id}", s.authenticated(s.handleGetTrackPreference)},
		{"PUT " + p + "/track-preferences/{item_id}", s.authenticated(s.handleSetTrackPreference)},
		{"DELETE " + p + "/track-preferences/{item_id}", s.authenticated(s.handleClearTrackPreference)},

		// Downloads voor offline kijken (venster 5 deel 3, S23, matrixregel 61 tot en
		// met 65). Alles klasse authenticated en van de eigenaar; de trede download
		// op de bibliotheek wordt bij het aanmaken en bij elke byte-aanvraag getoetst.
		{"POST " + p + "/downloads", s.authenticated(s.handleCreateDownload)},
		{"GET " + p + "/downloads", s.authenticated(s.handleListDownloads)},
		{"GET " + p + "/downloads/{download_id}", s.authenticated(s.handleGetDownload)},
		{"GET " + p + "/downloads/{download_id}/file", s.authenticated(s.handleDownloadFile)},
		{"DELETE " + p + "/downloads/{download_id}", s.authenticated(s.handleDeleteDownload)},

		// Back-up en restore (venster 7, S25, matrixregels 66 tot en met 70). Klasse
		// admin, in de handler zoals bij het beheer hierboven.
		{"GET " + p + "/backups", s.authenticated(s.handleListBackups)},
		{"POST " + p + "/backups", s.authenticated(s.handleCreateBackup)},
		{"GET " + p + "/backups/{backup_id}", s.authenticated(s.handleGetBackup)},
		{"POST " + p + "/backups/{backup_id}/verify", s.authenticated(s.handleVerifyBackup)},
		{"POST " + p + "/backups/{backup_id}/restore", s.authenticated(s.handleRestoreBackup)},

		// Beheer van omzetsessies (S18.5, matrixregel 50 en 51). Klasse admin.
		{"GET " + p + "/transcode-sessions", s.authenticated(s.handleListTranscodeSessions)},
		{"DELETE " + p + "/transcode-sessions/{session_id}", s.authenticated(s.handleStopTranscodeSession)},
		{"GET " + p + "/items/{item_id}", s.authenticated(s.handleItem)},
		{"GET " + p + "/items/{item_id}/children", s.authenticated(s.handleChildren)},
		{"GET " + p + "/search", s.authenticated(s.handleSearch)},
		{"GET " + p + "/hubs/{hub_id}", s.authenticated(s.handleHub)},
		{"GET " + p + "/artwork/{artwork_id}", s.authenticated(s.handleArtwork)},
		{"POST " + p + "/watch-state", s.authenticated(s.handleWatchStateReport)},
		{"GET " + p + "/watch-state", s.authenticated(s.handleWatchStateList)},

		// Gebruikersbeheer (DEC-121, stap 4). De autorisatieklasse staat in de
		// handler en niet in de route: "admin, of owner op zichzelf" is per
		// endpoint anders, en een middleware per klasse zou dat verschil verbergen.
		{"POST " + p + "/users", s.authenticated(s.handleCreateUser)},
		{"GET " + p + "/users", s.authenticated(s.handleListUsers)},
		// GET /users/me (S1.4) staat bewust vóór de {id}-routes in dit blok en
		// niet erin: hij is de enige die geen doel uit het pad leest. Er is geen
		// GET /users/{id}, dus "me" botst met niets.
		{"GET " + p + "/users/me", s.authenticated(s.handleCurrentUser)},
		{"PATCH " + p + "/users/{id}", s.authenticated(s.handleUpdateUser)},
		{"DELETE " + p + "/users/{id}", s.authenticated(s.handleDeleteUser)},
		{"PUT " + p + "/users/{id}/permissions", s.authenticated(s.handleSetPermissions)},

		// Serverinstellingen (S1.2, J.2 rij 2). Klasse admin, en net als bij
		// gebruikersbeheer staat die klasse in de handler: requireAdmin schrijft de
		// 404 die een niet-beheerder hoort te zien.
		{"GET " + p + "/settings", s.authenticated(s.handleGetSettings)},
		{"PATCH " + p + "/settings", s.authenticated(s.handlePatchSettings)},

		// Serverdiagnostiek (S1.3, J.2 rijen 4 tot en met 7). Alle vier klasse
		// admin. GET /server hierboven blijft authenticated en groeit alleen voor
		// een beheerder; deze vier bestaan voor een lid helemaal niet.
		{"GET " + p + "/server/environment", s.authenticated(s.handleServerEnvironment)},
		{"GET " + p + "/server/log", s.authenticated(s.handleServerLog)},
		{"POST " + p + "/server/connectivity-check", s.authenticated(s.handleConnectivityCheck)},
		{"POST " + p + "/server/rotate-signing-key", s.authenticated(s.handleRotateSigningKey)},

		// Lopende streams (S1.4, J.2 rij 8). Klasse admin, net als de vier
		// diagnostiekroutes hierboven: dit zegt wie er kijkt en op welk toestel,
		// en dat is geen antwoord voor een huisgenoot.
		{"GET " + p + "/stream-sessions", s.authenticated(s.handleStreamSessions)},

		// Kijkgeschiedenis van alle gebruikers (DEC-143). Klasse admin, om
		// dezelfde reden als de lopende streams hierboven.
		{"GET " + p + "/watch-history", s.authenticated(s.handleWatchHistory)},

		// API-tokens (S1.5, J.2 rij 12 en 13). Klasse authenticated en niet admin:
		// RB-20 zegt "een gebruiker (zelf, of een beheerder namens iemand)", dus de
		// eigen tokens zijn zelfbediening en `user_id` is de beheerdersvorm. De
		// autorisatie is daarmee die van GET /sessions (matrixregel 15) en niet die
		// van een beheerroute.
		{"POST " + p + "/auth/api-tokens", s.authenticated(s.handleCreateAPIToken)},
		{"GET " + p + "/auth/api-tokens", s.authenticated(s.handleListAPITokens)},

		// Auditlog (S1.5, J.2 rij 14). Klasse admin: het is de enige plek waar
		// staat wie wat wanneer deed, inclusief mislukte logins, en dat is geen
		// antwoord voor wie de handelingen zelf niet mag doen.
		{"GET " + p + "/audit", s.authenticated(s.handleAudit)},

		// Sessies (DEC-124, stap 6). logout staat bij auth omdat hij over de eigen
		// sessie gaat; de twee endpoints eronder gaan over sessies als resource.
		{"POST " + p + "/auth/logout", s.authenticated(s.handleLogout)},
		{"GET " + p + "/sessions", s.authenticated(s.handleListSessions)},
		{"DELETE " + p + "/sessions/{id}", s.authenticated(s.handleRevokeSession)},

		// Klasse authenticated of met een streamtoken in de querystring: een externe
		// speler kan geen header zetten.
		{"GET " + p + "/subtitles/{subtitle_id}", s.streamAuthorized(s.handleSubtitle)},

		// Klasse authenticated, met een streamtoken in de querystring, of met een
		// browser-streamsessie: een niet-geheime ss in de URL plus de cookie
		// waarvan de naam die id draagt (DEC-051).
		{"GET " + p + "/stream/{version_id}", s.streamAuthorized(s.handleStream)},

		// Alles wat onder /pleya/v1 valt en hierboven niet staat is een onbekende
		// protocolroute, en die krijgt de foutvorm van het protocol. Zonder deze
		// regel zou hij bij de SPA-terugval hieronder belanden en een client een
		// pagina HTML zien waar hij JSON verwacht. Het patroon eindigt op een
		// schuine streep en dekt dus de hele deelboom, terwijl elke exacte route
		// hierboven specifieker is en dus wint.
		{p + "/", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		})},
	}

	// De meegeleverde webclient, op het minst specifieke patroon dat er
	// bestaat. /healthz, /readyz en elke route onder /pleya/v1 houden daardoor
	// voorrang; internal/api/web_routes_test.go bewijst dat.
	//
	// Bewust zonder methode ervoor. "GET /" naast "/pleya/v1/" weigert
	// ServeMux als dubbelzinnig: de een dekt minder methoden, de ander een
	// smaller pad, en dan is er geen volgorde. De methodecontrole staat
	// daarom in de webhandler zelf, die alles buiten GET en HEAD met een 405
	// afwijst in plaats van met een pagina.
	if s.opts.Web != nil {
		table = append(table, route{"/", s.opts.Web})
	} else {
		table = append(table, route{"/", web.Handler()})
	}
	return table
}
