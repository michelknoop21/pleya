package push

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Rich push (DEC-XXX). Apple only ever sees the generic alert; the title and
// the poster reference travel sealed under the key the app registered for this
// installation, and the app's Notification Service Extension opens them.

// artworkTokenTTL bounds the poster reference to the lifetime of the delivery.
const artworkTokenTTL = 24 * time.Hour

// maxTitleRunes keeps two long titles well inside Apple's 4 KB.
const maxTitleRunes = 100

// richContent is what the extension decrypts. The server writes the final,
// localized text, so the extension carries no strings of its own.
type richContent struct {
	Title   string `json:"title"`
	Body    string `json:"body"`
	Artwork string `json:"artwork,omitempty"`
	Token   string `json:"token,omitempty"`
}

// seal encrypts with AES-256-GCM and returns nonce|ciphertext|tag, the layout
// of CryptoKit's AES.GCM.SealedBox.combined.
func seal(key, plaintext []byte, random io.Reader) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(random, nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, plaintext, nil), nil
}

// sealedContent describes the first of the due items for this installation
// and seals it. Empty means: send the generic alert only. Nothing here is
// logged, so a title never reaches the server log either.
func (s *Service) sealedContent(ctx context.Context, key []byte, locale string, user, session id.ID, items []id.ID) string {
	if len(key) != 32 || len(items) == 0 || s.Items == nil {
		return ""
	}
	var first id.ID
	// The earliest addition leads, so a season batch names its first episode.
	if err := s.pool.QueryRow(ctx, `SELECT id FROM media_items WHERE id=ANY($1)
		ORDER BY added_at, item_index NULLS LAST, id LIMIT 1`, items).Scan(&first); err != nil {
		return ""
	}
	item, err := s.Items.Item(ctx, first)
	if err != nil {
		return ""
	}
	season, show := s.lineage(ctx, item)
	content := describe(locale, item, season, show, len(items)-1)
	poster := item.PosterID
	if show != nil && show.PosterID != nil {
		poster = show.PosterID
	}
	if poster != nil && s.Signer != nil {
		token, _, err := s.Signer.Mint(user.String(), session.String(), auth.TokenArtwork, artworkTokenTTL, poster.String())
		if err == nil {
			content.Artwork, content.Token = poster.String(), token
		}
	}
	plain, err := json.Marshal(content)
	if err != nil {
		return ""
	}
	sealed, err := seal(key, plain, rand.Reader)
	if err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(sealed)
}

// lineage finds the season and series of an episode; nil for anything else.
func (s *Service) lineage(ctx context.Context, item catalog.Item) (season, show *catalog.Item) {
	if item.Kind != "episode" || item.ParentID == nil {
		return nil, nil
	}
	parent, err := s.Items.Item(ctx, *item.ParentID)
	if err != nil {
		return nil, nil
	}
	if parent.Kind == "show" {
		return nil, &parent
	}
	if parent.Kind != "season" || parent.ParentID == nil {
		return nil, nil
	}
	grand, err := s.Items.Item(ctx, *parent.ParentID)
	if err != nil || grand.Kind != "show" {
		return &parent, nil
	}
	return &parent, &grand
}

// describe writes the localized text: "Nieuw: <titel>" and, for a batch,
// "en 3 meer". An episode is named by its series, with the episode below.
func describe(locale string, item catalog.Item, season, show *catalog.Item, more int) richContent {
	nl := locale == "nl"
	name := clip(item.Title)
	body := "New movie in your library."
	if nl {
		body = "Nieuwe film in je bibliotheek."
	}
	if item.Kind == "episode" {
		if show != nil {
			name = clip(show.Title)
		}
		body = clip(item.Title)
		switch {
		case item.Index != nil && season != nil && season.Index != nil && nl:
			body = fmt.Sprintf("Seizoen %d, aflevering %d: %s", *season.Index, *item.Index, body)
		case item.Index != nil && season != nil && season.Index != nil:
			body = fmt.Sprintf("Season %d, episode %d: %s", *season.Index, *item.Index, body)
		case item.Index != nil && nl:
			body = fmt.Sprintf("Aflevering %d: %s", *item.Index, body)
		case item.Index != nil:
			body = fmt.Sprintf("Episode %d: %s", *item.Index, body)
		}
	}
	title := "New: " + name
	if nl {
		title = "Nieuw: " + name
	}
	if more > 0 {
		if nl {
			title += fmt.Sprintf(" en %d meer", more)
		} else {
			title += fmt.Sprintf(" and %d more", more)
		}
	}
	return richContent{Title: title, Body: body}
}

func clip(text string) string {
	runes := []rune(text)
	if len(runes) <= maxTitleRunes {
		return text
	}
	return string(runes[:maxTitleRunes-1]) + "…"
}
