package settings

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync/atomic"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Cache is de set zoals de server hem op dit moment gebruikt.
//
// Hot reload zit hier en niet in een herstart: elke lezer haalt de waarde per
// aanvraag op, dus een geslaagde PATCH geldt voor het eerstvolgende verzoek. Dat
// is de eis uit de acceptatie van S1 ("een nieuw token heeft de nieuwe TTL"),
// en het is ook de enige vorm die klopt: een server die pas na een herstart
// luistert zou een beheerder een wijziging tonen die niet draait.
//
// Zonder Store bestaat alleen de omgevingslaag. Dat is geen testgemak maar het
// gedrag van een server die nog geen migratie 0008 achter de rug heeft.
type Cache struct {
	base    Base
	store   *Store
	log     *slog.Logger
	current atomic.Pointer[Values]
}

// NewCache bouwt de cache op de omgevingslaag. store en log mogen nil zijn.
func NewCache(base Base, store *Store, log *slog.Logger) *Cache {
	c := &Cache{base: base, store: store, log: log}
	v := newValues(base, nil)
	c.current.Store(&v)
	return c
}

// Current geeft de set die nu geldt.
func (c *Cache) Current() Values { return *c.current.Load() }

// HasStore zegt of er een database achter zit. Zonder database is elke sleutel
// alleen-lezen, en dan hoort PATCH niet te doen alsof hij iets bewaart.
func (c *Cache) HasStore() bool { return c.store != nil }

// Reload leest de opgeslagen sleutels en wisselt de set om.
//
// Een opgeslagen waarde die niet meer door de grenzen komt wordt overgeslagen
// en de omgeving wint (zie newValues). Dat is geen stille correctie van de
// database: de rij blijft staan, alleen de draaiende server gebruikt hem niet,
// en er gaat een regel naar het log. Zonder die regel zou een beheerder in het
// scherm een waarde zien die niet draait en nergens kunnen zien waarom.
func (c *Cache) Reload(ctx context.Context) error {
	if c.store == nil {
		return nil
	}
	raw, err := c.store.All(ctx)
	if err != nil {
		return err
	}

	stored := make(map[string]any, len(raw))
	for key, value := range raw {
		parsed, err := Parse(key, value)
		if err != nil {
			if c.log != nil {
				c.log.Warn("opgeslagen instelling wordt overgeslagen, de omgeving blijft gelden",
					slog.String("key", key), slog.String("error", err.Error()))
			}
			continue
		}
		stored[key] = parsed
	}

	v := newValues(c.base, stored)
	c.current.Store(&v)
	return nil
}

// Apply valideert een patch, schrijft hem en herlaadt.
//
// De volgorde ligt vast: eerst elke sleutel valideren, dan pas schrijven. Een
// patch met drie sleutels waarvan de tweede buiten de grens ligt hoort er nul
// te wijzigen, want half doorgevoerd beheer is erger dan geweigerd beheer.
//
// De fout bij een ongeldige waarde is *InvalidValueError, en de HTTP-laag maakt
// daar settings.invalid_value van met het veld en de grens erbij.
func (c *Cache) Apply(ctx context.Context, patch map[string]json.RawMessage, by id.ID) error {
	encoded := make(map[string]json.RawMessage, len(patch))
	for key, raw := range patch {
		parsed, err := Parse(key, raw)
		if err != nil {
			return err
		}
		value, err := Encode(parsed)
		if err != nil {
			return err
		}
		encoded[key] = value
	}

	if err := c.store.Put(ctx, encoded, by); err != nil {
		return err
	}
	return c.Reload(ctx)
}
