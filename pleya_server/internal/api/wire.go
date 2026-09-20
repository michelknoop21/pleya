package api

import (
	"encoding/json"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// FeatureLevel is wat deze implementatie van het protocol begrijpt.
//
// Het zegt niets over wat deze server aanbiedt; daarvoor is capabilities
// leidend. Een client die uit een hoog level afleidt dat een functie bestaat
// redeneert verkeerd, en dat is precies waarom de twee velden apart staan.
const FeatureLevel = 1

// Info is het antwoord van GET /info.
type Info struct {
	Protocol     InfoProtocol `json:"protocol"`
	Server       InfoServer   `json:"server"`
	Capabilities Capabilities `json:"capabilities"`
	Auth         InfoAuth     `json:"auth"`
}

// InfoProtocol draagt de versie en het profiel.
type InfoProtocol struct {
	Major        int    `json:"major"`
	FeatureLevel int    `json:"feature_level"`
	Profile      string `json:"profile"`
}

// InfoServer draagt een id en één onderhandelingsvlag. Geen servernaam, geen
// versie en geen buildnummer: die zijn nuttig bij foutzoeken en staan daarom in
// GET /server, achter authenticatie. Een versienummer aan de buitenkant vertelt
// een scanner precies welke bekende zwakke plekken het proberen waard zijn.
type InfoServer struct {
	ID string `json:"id"`

	// SetupAcceptsName (J.2 rij 10) zegt dat POST /auth/setup het veld
	// server_name aanneemt. Hier en niet in Capabilities: het is geen functie
	// die aan of uit staat maar een eigenschap van dat ene endpoint, en het is
	// het enige veld dat een client vóór het inloggen moet weten. SetupRequest
	// is gesloten, dus zonder deze vlag stuurt een client server_name niet.
	SetupAcceptsName bool `json:"setup_accepts_name"`
}

// InfoAuth zegt hoe er ingelogd kan worden.
type InfoAuth struct {
	Methods       []string `json:"methods"`
	SetupRequired bool     `json:"setup_required"`
}

// Capabilities is wat deze server werkelijk aanbiedt, en is altijd leidend.
type Capabilities struct {
	Browse       bool `json:"browse"`
	Search       bool `json:"search"`
	Artwork      bool `json:"artwork"`
	WatchState   bool `json:"watch_state"`
	PlaybackPlan bool `json:"playback_plan"`
	Transcode    bool `json:"transcode"`
	Downloads    bool `json:"downloads"`
	LiveTV       bool `json:"live_tv"`
	Realtime     bool `json:"realtime"`

	// Users (DEC-100). Aan sinds stap 4 van PS-9: de vijf endpoints onder
	// /users bestaan, en /auth/login verifieert tegen users en niet meer tegen
	// alleen de owner-rij. Een client die deze vlag ziet mag ervan uitgaan dat
	// een tweede gebruiker kan bestaan en kan inloggen.
	Users bool `json:"users"`

	// PS-4. Twee vlaggen die de client vertellen dat hij de velden uit DEC-049
	// en het endpoint uit DEC-051 mag gebruiken. WatchStateEvent is gesloten,
	// dus zonder deze onderhandeling zou een client die base_revision meestuurt
	// een 400 krijgen van een oudere server.
	WatchStateOwnership bool `json:"watch_state_ownership"`
	StreamSessions      bool `json:"stream_sessions"`

	// Sessions (DEC-102, DEC-103). Aan sinds stap 6 van PS-9. De vlag zegt drie
	// dingen tegelijk: de client mag device_id en device_name meesturen bij
	// login en setup, GET/DELETE /sessions en POST /auth/logout bestaan, en een
	// ingetrokken sessie is binnen twee seconden ongeldig, ook voor een lopende
	// stream (DEC-099).
	Sessions bool `json:"sessions"`

	// APITokens (RB-20, J.2 rij 12 en 13). Aan sinds S1.5. De vlag zegt dat
	// POST en GET /auth/api-tokens bestaan en dat Session kind en scope draagt.
	// Hij staat naast `sessions` en niet erin: een client die sessies kent maar
	// deze vlag niet ziet, toont het sessieoverzicht zonder de tokenkolom, en
	// dat is een geldig scherm.
	APITokens bool `json:"api_tokens"`

	// CookieAuth (RB-29, J.2 rij 16). Aan sinds S1.8. De vlag zegt dat
	// POST /auth/login en POST /auth/refresh het veld credential_mode kennen en
	// het refreshcredential desgevraagd in een HttpOnly-cookie zetten. Beide
	// bodies zijn gesloten, dus zonder deze onderhandeling zou een client die
	// credential_mode meestuurt een weigering krijgen van een oudere server in
	// plaats van een veld dat stil wegvalt.
	CookieAuth bool `json:"cookie_auth"`

	// Administration (J.2 rij 1). Aan sinds S1.6, en hij dekt wat S1.2 tot en
	// met S1.5 hebben gebouwd: GET/PATCH /settings, de vier routes onder
	// /server, GET /stream-sessions en GET /audit.
	//
	// Eén vlag voor het hele oppervlak. Een client die zes vlaggen zou moeten
	// lezen krijgt zes vragen met altijd hetzelfde antwoord, want de routes
	// kwamen samen. En de vlag is netheid en geen beveiliging: de server
	// weigert onafhankelijk ervan met 404 voor wie er niet bij mag.
	Administration bool `json:"administration"`

	// MCP (RB-19, RB-20, J.2 rij 15). Uit, en dat blijft zo tot slice S16 de
	// laag werkelijk bouwt. Hij staat er nu al omdat het protocolvenster nu
	// open is: een vlag die pas met de implementatie meekomt zou een tweede
	// venster kosten voor een boolean.
	MCP bool `json:"mcp"`
}

// ServerDetail is het antwoord van GET /server.
//
// De eerste vier velden zijn klasse authenticated en staan er sinds PS-2. De
// negen daaronder gaan alleen mee voor klasse admin: acht met S1.3 (J.2 rij 3)
// en web_origin met S1.8. Ze beschrijven hoe deze server draait, en dat is voor
// een huisgenoot geen informatie maar een verkenning.
//
// cors_origins staat er bewust niet bij. Die lijst is beleid en geen adres, en
// een opsomming van vertrouwde origins vertelt precies welke herkomst het
// proberen waard is; hij staat in GET /settings en verder nergens.
//
// Pointers en geen kale waarden, want het verschil tussen "afwezig" en "leeg"
// draagt hier betekenis. Een lid ziet public_url niet; een beheerder van een
// server zonder publiek adres ziet hem als lege tekst, en dat is een ander
// antwoord op een andere vraag.
type ServerDetail struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Version   string `json:"version"`
	StartedAt string `json:"started_at"`

	PublicURL      *string             `json:"public_url,omitempty"`
	WebOrigin      *string             `json:"web_origin,omitempty"`
	Listen         *string             `json:"listen,omitempty"`
	BehindProxy    *bool               `json:"behind_proxy,omitempty"`
	TrustedProxies *[]string           `json:"trusted_proxies,omitempty"`
	Build          *string             `json:"build,omitempty"`
	Database       *ServerDatabaseWire `json:"database,omitempty"`
	FFprobe        *ServerFFprobeWire  `json:"ffprobe,omitempty"`
	Health         *ServerHealthWire   `json:"health,omitempty"`
	MCP            *ServerMCPWire      `json:"mcp,omitempty"`
}

// ServerMCPWire is de MCP-beheerlaag in GET /server, klasse admin (J.2 rij 15).
//
// Zolang capabilities.mcp uit staat draagt hij enabled false en tool_count 0,
// zonder url. Dat is een ander antwoord dan een afwezig object: het eerste zegt
// "de laag bestaat en staat uit", het tweede "deze server kent de vraag niet".
type ServerMCPWire struct {
	Enabled   bool    `json:"enabled"`
	URL       *string `json:"url,omitempty"`
	ToolCount int     `json:"tool_count"`
}

// TokenPair is wat setup, login en refresh teruggeven.
//
// RefreshToken draagt omitempty sinds S1.8: in cookiemodus zit het credential in
// de cookie pleya_refresh en hoort het niet in het lichaam. Het weglaten is het
// hele punt van RB-29, want een refreshtoken dat óók in het antwoord staat is met
// één regel JavaScript alsnog te lezen. Voor een client die credential_mode niet
// stuurt staat het er altijd; zie hoofdstuk 17d.1 voor de compatibiliteitstoets.
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	TokenType    string `json:"token_type"`
	ExpiresInMs  int64  `json:"expires_in_ms"`
}

// StreamToken is het kortlevende token voor bytes.
type StreamToken struct {
	StreamToken string `json:"stream_token"`
	ExpiresAt   string `json:"expires_at"`
}

// Library is één bibliotheek op de lijn.
//
// managed, scan_interval_seconds en scan_on_start gaan sinds S2.2 alleen mee
// voor klasse admin (J.3): voor een huisgenoot is dat geen kijkinformatie maar
// beheerdetail. scan_interval_seconds is ook voor een admin nullable (NULL
// betekent: gebruik de globale interval), dus dit veld draagt een pointer naar
// een pointer: de buitenste beslist of het veld er voor deze rol bij staat, de
// binnenste of de waarde zelf null is. roots[] en last_scan volgen met S2.3 en
// S2.4, wanneer er ook werkelijk iets zinnigs in te vullen is.
type Library struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Kind      string `json:"kind"`
	ItemCount int    `json:"item_count"`

	Managed             *string `json:"managed,omitempty"`
	ScanIntervalSeconds **int   `json:"scan_interval_seconds,omitempty"`
	ScanOnStart         *bool   `json:"scan_on_start,omitempty"`
}

// LibraryList is het antwoord van GET /libraries.
type LibraryList struct {
	Items []Library `json:"items"`
}

// CreateLibraryRequest is de gesloten aanvraagbody van POST /libraries (J.3).
type CreateLibraryRequest struct {
	Title               string   `json:"title"`
	Kind                string   `json:"kind"`
	RootPaths           []string `json:"root_paths"`
	ScanIntervalSeconds *int     `json:"scan_interval_seconds"`
	ScanOnStart         *bool    `json:"scan_on_start"`
}

// UpdateLibraryRequest is de gesloten aanvraagbody van PATCH /libraries/{id}
// (J.3). Elk veld is een pointer: afwezig betekent onveranderd.
//
// scan_interval_seconds is bovendien zelf nullable, en heeft daarom een kale
// (niet-pointer) json.RawMessage: encoding/json zet een `*json.RawMessage` bij
// het JSON-literaal null zelf op nil, vóórdat RawMessage's eigen
// UnmarshalJSON ooit wordt aangeroepen, en dan is "niet meegestuurd" en
// "meegestuurd met null" opnieuw hetzelfde ongeval als bij een kale `*int`. Een
// niet-pointer json.RawMessage krijgt zijn UnmarshalJSON wél aangeroepen op
// null en bewaart dan de letterlijke bytes `null`; alleen een afwezige sleutel
// laat het veld op zijn Go-zero (een nil slice) staan. Zie
// TestUpdateLibraryScanIntervalDistinguishesAbsentFromNull in de catalog-laag
// voor het gedrag dat dit onderscheid mogelijk maakt.
// Title en Kind zijn zelf ook niet-nullable velden en dragen daarom dezelfde
// kale json.RawMessage als scan_interval_seconds: {"title": null} moet 400
// geven en geen stille no-op, en een *string kan "afwezig" en "null" niet uit
// elkaar houden.
type UpdateLibraryRequest struct {
	Title               json.RawMessage `json:"title"`
	Kind                json.RawMessage `json:"kind"`
	RootPaths           *[]string       `json:"root_paths"`
	ScanIntervalSeconds json.RawMessage `json:"scan_interval_seconds"`
	ScanOnStart         *bool           `json:"scan_on_start"`
}

// DeleteLibraryRequest is de gesloten aanvraagbody van DELETE /libraries/{id}
// (K rij 16, J.3): confirm moet letterlijk de titel van de bibliotheek zijn.
type DeleteLibraryRequest struct {
	Confirm string `json:"confirm"`
}

// Artwork draagt de ids van de beschikbare afbeeldingen.
type Artwork struct {
	PosterID   *string `json:"poster_id"`
	BackdropID *string `json:"backdrop_id"`
}

// VideoStream is één videospoor.
type VideoStream struct {
	ID        string   `json:"id"`
	Index     int      `json:"index"`
	Codec     string   `json:"codec"`
	Profile   *string  `json:"profile"`
	Width     *int     `json:"width"`
	Height    *int     `json:"height"`
	BitDepth  *int     `json:"bit_depth"`
	FrameRate *float64 `json:"frame_rate"`
}

// AudioStream is één audiospoor.
type AudioStream struct {
	ID        string  `json:"id"`
	Index     int     `json:"index"`
	Codec     string  `json:"codec"`
	Channels  *int    `json:"channels"`
	Language  *string `json:"language"`
	Title     *string `json:"title"`
	IsDefault bool    `json:"is_default"`
}

// SubtitleStream is één ondertitelspoor, ingebed of los.
//
// Extern heeft een url en geen index; ingebed heeft een index en geen url. De
// booleans zijn expliciet en geen afleiding uit de titel.
type SubtitleStream struct {
	ID                string  `json:"id"`
	Index             *int    `json:"index"`
	Format            string  `json:"format"`
	Language          *string `json:"language"`
	Title             *string `json:"title"`
	IsDefault         bool    `json:"is_default"`
	IsForced          bool    `json:"is_forced"`
	IsHearingImpaired bool    `json:"is_hearing_impaired"`
	IsExternal        bool    `json:"is_external"`
	URL               *string `json:"url"`
}

// Version is één versie van een item.
type Version struct {
	ID              string           `json:"id"`
	Container       string           `json:"container"`
	DurationMs      int64            `json:"duration_ms"`
	FileCount       int              `json:"file_count"`
	Edition         *string          `json:"edition"`
	VideoStreams    []VideoStream    `json:"video_streams"`
	AudioStreams    []AudioStream    `json:"audio_streams"`
	SubtitleStreams []SubtitleStream `json:"subtitle_streams"`
}

// UserState is de leeskant van kijkstatus.
//
// Een item dat de identiteit nooit heeft aangeraakt draagt null, en dat is hoe
// een client het verschil ziet tussen "op nul begonnen" en "nooit geopend".
type UserState struct {
	PositionMs int64  `json:"position_ms"`
	Watched    bool   `json:"watched"`
	PlayCount  int    `json:"play_count"`
	UpdatedAt  string `json:"updated_at"`

	// Revision is de causaliteitsanker uit DEC-049. De client bewaart hem en
	// stuurt hem terug als base_revision.
	Revision *int64 `json:"revision,omitempty"`

	// OwnedByThisSession staat alleen in het antwoord op POST /watch-state.
	// Weglaten in een itemantwoord is met opzet: daar is er geen sessie om de
	// vraag op te beantwoorden.
	OwnedByThisSession *bool `json:"owned_by_this_session,omitempty"`
}

// WatchStateEvent is de aanvraagbody van POST /watch-state.
//
// De velden staan als pointer waar hun afwezigheid betekenis draagt.
// base_revision is daar het duidelijkste geval: nul is een geldige claim (de
// toestand bestaat nog niet) en weglaten betekent "geen claim", en die twee
// mogen niet samenvallen.
type WatchStateEvent struct {
	ItemID       string `json:"item_id"`
	SessionID    string `json:"session_id"`
	PositionMs   int64  `json:"position_ms"`
	DurationMs   *int64 `json:"duration_ms"`
	OccurredAt   string `json:"occurred_at"`
	Completed    bool   `json:"completed"`
	Action       string `json:"explicit_action"`
	Cause        string `json:"cause"`
	BaseRevision *int64 `json:"base_revision"`
	Backlog      bool   `json:"backlog"`
}

// WatchStateEntry is één regel in de lijst van GET /watch-state.
type WatchStateEntry struct {
	ItemID string    `json:"item_id"`
	State  UserState `json:"state"`
}

// WatchStatePage is een pagina kijkstatusregels.
type WatchStatePage struct {
	Items         []WatchStateEntry `json:"items"`
	NextCursor    *string           `json:"next_cursor"`
	TotalEstimate *int              `json:"total_estimate"`
}

// StreamSession is het antwoord van POST /auth/stream-session.
//
// Draagt uitsluitend de niet-geheime helft. Het geheim reist in de cookie en
// komt nooit in een body, een URL of een logregel.
type StreamSession struct {
	StreamSessionID string `json:"stream_session_id"`
	ExpiresAt       string `json:"expires_at"`
}

// Item is één item op de lijn.
type Item struct {
	ID                  string     `json:"id"`
	Kind                string     `json:"kind"`
	Title               string     `json:"title"`
	SortTitle           *string    `json:"sort_title"`
	Year                *int       `json:"year"`
	AddedAt             string     `json:"added_at"`
	DurationMs          *int64     `json:"duration_ms"`
	ParentID            *string    `json:"parent_id"`
	Index               *int       `json:"index"`
	ChildCount          *int       `json:"child_count"`
	EpisodeCount        *int       `json:"episode_count"`
	WatchedEpisodeCount *int       `json:"watched_episode_count"`
	Artwork             Artwork    `json:"artwork"`
	Versions            []Version  `json:"versions"`
	UserState           *UserState `json:"user_state"`
}

// ItemPage is een pagina items.
type ItemPage struct {
	Items         []Item  `json:"items"`
	NextCursor    *string `json:"next_cursor"`
	TotalEstimate *int    `json:"total_estimate"`
}

// mapItem vertaalt een domeinitem naar het wire-type.
//
// Dit is de expliciete mapper waar hoofdstuk 12.1 om vraagt. De veldnamen aan
// deze kant zijn backend-neutraal en volgen het protocol; dat het interne model
// andere namen draagt is toegestaan.
func mapItem(it catalog.Item) Item {
	out := Item{
		ID:                  it.ID.String(),
		Kind:                it.Kind,
		Title:               it.Title,
		SortTitle:           optString(it.SortTitle),
		Year:                it.Year,
		AddedAt:             formatTime(it.AddedAt),
		DurationMs:          it.DurationMs,
		ParentID:            optID(it.ParentID),
		Index:               it.Index,
		ChildCount:          it.ChildCount,
		EpisodeCount:        it.EpisodeCount,
		WatchedEpisodeCount: it.WatchedEpisodeCount,
		Artwork: Artwork{
			PosterID:   optID(it.PosterID),
			BackdropID: optID(it.BackdropID),
		},
		Versions: make([]Version, 0, len(it.Versions)),
		// Er is in PS-2 geen kijkstatus. Een item dat de identiteit nooit heeft
		// aangeraakt draagt user_state: null, en dat is elk item.
		UserState: nil,
	}

	for _, v := range it.Versions {
		out.Versions = append(out.Versions, mapVersion(v))
	}
	return out
}

func mapVersion(v catalog.Version) Version {
	out := Version{
		ID:              v.ID.String(),
		Container:       v.Container,
		DurationMs:      v.DurationMs,
		FileCount:       v.FileCount,
		Edition:         optString(v.Edition),
		VideoStreams:    []VideoStream{},
		AudioStreams:    []AudioStream{},
		SubtitleStreams: []SubtitleStream{},
	}

	for _, st := range v.Streams {
		switch st.Kind {
		case "video":
			out.VideoStreams = append(out.VideoStreams, VideoStream{
				ID:        st.ID.String(),
				Index:     derefInt(st.Index),
				Codec:     st.Codec,
				Profile:   optString(st.Profile),
				Width:     st.Width,
				Height:    st.Height,
				BitDepth:  st.BitDepth,
				FrameRate: st.FrameRate,
			})
		case "audio":
			out.AudioStreams = append(out.AudioStreams, AudioStream{
				ID:        st.ID.String(),
				Index:     derefInt(st.Index),
				Codec:     st.Codec,
				Channels:  st.Channels,
				Language:  optString(st.Language),
				Title:     optString(st.Title),
				IsDefault: st.IsDefault,
			})
		case "subtitle":
			// Een ondertitelspoor zonder formaat dat het protocol kent hoort er
			// niet op: format is verplicht, en een client kan met een formaat dat
			// de specificatie niet noemt niets beginnen.
			if st.SubtitleFormat == "" {
				continue
			}
			sub := SubtitleStream{
				ID:                st.ID.String(),
				Index:             st.Index,
				Format:            st.SubtitleFormat,
				Language:          optString(st.Language),
				Title:             optString(st.Title),
				IsDefault:         st.IsDefault,
				IsForced:          st.IsForced,
				IsHearingImpaired: st.IsHearingImpaired,
				IsExternal:        st.IsExternal,
			}
			if st.IsExternal {
				url := "/pleya/v1/subtitles/" + st.ID.String()
				sub.URL = &url
				sub.Index = nil
			}
			out.SubtitleStreams = append(out.SubtitleStreams, sub)
		}
	}
	return out
}

func mapPage(p catalog.Page, total *int) ItemPage {
	out := ItemPage{
		Items:         make([]Item, 0, len(p.Items)),
		TotalEstimate: total,
	}
	for _, it := range p.Items {
		out.Items = append(out.Items, mapItem(it))
	}
	if p.NextCursor != "" {
		c := p.NextCursor
		out.NextCursor = &c
	}
	return out
}

// formatTime is RFC 3339 in UTC met een Z-achtervoegsel, zoals hoofdstuk 2 van
// de specificatie voorschrijft.
func formatTime(t time.Time) string {
	return t.UTC().Format("2006-01-02T15:04:05Z")
}

func optString(v string) *string {
	if v == "" {
		return nil
	}
	return &v
}

func optID(v *id.ID) *string {
	if v == nil {
		return nil
	}
	s := v.String()
	return &s
}

func derefInt(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}
