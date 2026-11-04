package metadata

import (
	"bytes"
	"errors"
	"image/png"
	"math"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

type tmdbCredit struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Character string `json:"character"`
	Job       string `json:"job"`
	Profile   string `json:"profile_path"`
	Adult     bool   `json:"adult"`
}
type tmdbCredits struct {
	ID   int          `json:"id"`
	Cast []tmdbCredit `json:"cast"`
	Crew []tmdbCredit `json:"crew"`
}
type tmdbPresentationImages struct {
	ID    int `json:"id"`
	Logos []struct {
		Ref      string  `json:"file_path"`
		Language *string `json:"iso_639_1"`
	} `json:"logos"`
}

func (c *TMDB) addPresentation(out *catalog.MetadataDetails, raw *tmdbDetails) {
	p := &catalog.DetailPresentation{}
	for _, language := range []string{strings.Split(c.language, "-")[0], "en", ""} {
		for _, logo := range raw.Images.Logos {
			actual := ""
			if logo.Language != nil {
				actual = *logo.Language
			}
			if (raw.Images.ID == 0 || raw.Images.ID == raw.ID) && actual == language && ValidImageRef(logo.Ref) && strings.HasSuffix(logo.Ref, ".png") {
				p.LogoRef = logo.Ref
				break
			}
		}
		if p.LogoRef != "" {
			break
		}
	}
	if score := raw.VoteAverage; score != nil && raw.VoteCount > 0 && *score >= 0 && *score <= 10 && !math.IsNaN(*score) && !math.IsInf(*score, 0) {
		p.Ratings = []catalog.ExternalRating{{Source: "tmdb", Value: *score, MaxValue: 10, VoteCount: raw.VoteCount}}
	}
	seen := map[string]bool{}
	add := func(credit tmdbCredit, role string) {
		name := strings.TrimSpace(credit.Name)
		if credit.Adult || name == "" || len(name) > 512 || len(out.People) >= 30 {
			return
		}
		character := strings.TrimSpace(credit.Character)
		key := name + "\x00" + role + "\x00" + character
		if seen[key] {
			return
		}
		seen[key] = true
		out.People = append(out.People, catalog.Person{Name: name, Role: role, Character: character})
		if credit.ID > 0 && ValidImageRef(credit.Profile) && len(p.Portraits) < 18 {
			p.Portraits = append(p.Portraits, catalog.CreditPortrait{Name: name, Role: role, Character: character, Ref: credit.Profile})
		}
	}
	// Appended objects are bound by the checked top-level title ID. An optional
	// redundant child ID may be absent, but may never contradict its parent.
	if raw.Credits.ID != 0 && raw.Credits.ID != raw.ID {
		out.Presentation = p
		return
	}
	for i, credit := range raw.Credits.Cast {
		if i >= 24 {
			break
		}
		add(credit, "actor")
	}
	for _, credit := range raw.Credits.Crew {
		switch credit.Job {
		case "Director":
			add(credit, "director")
		case "Writer", "Screenplay", "Story":
			add(credit, "writer")
		}
	}
	out.Presentation = p
}

// Logos stay PNG with actual transparency, including after a small-width request.
// Decode bounds are checked before allocation; opaque rectangles are not marks.
func validateLogo(data []byte) error {
	config, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width < 1 || config.Height < 1 || config.Width > 2048 || config.Height > 2048 {
		return errors.New("invalid or oversized logo PNG")
	}
	image, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		return errors.New("invalid logo PNG")
	}
	bounds := image.Bounds()
	for _, point := range [][2]int{{bounds.Min.X, bounds.Min.Y}, {bounds.Max.X - 1, bounds.Min.Y}, {bounds.Min.X, bounds.Max.Y - 1}, {bounds.Max.X - 1, bounds.Max.Y - 1}} {
		_, _, _, alpha := image.At(point[0], point[1]).RGBA()
		if alpha < 65535 {
			return nil
		}
	}
	return errors.New("logo has no transparent corners")
}
