package settings

import "time"

// Base is de omgevingslaag: de waarden waarmee de server startte.
//
// config.Load lost omgeving en default al op, dus dit is één laag en niet twee.
type Base struct {
	ServerName        string
	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	StreamTokenTTL    time.Duration
	StreamSessionTTL  time.Duration
	MaxStreamSessions int
}

// Values is de set zoals hij op dit moment geldt: per sleutel een waarde en de
// laag die hem levert.
//
// Onveranderlijk na het bouwen. De cache wisselt hem in zijn geheel om, zodat
// een aanvraag die halverwege een wijziging leest nooit een half bijgewerkte
// set ziet.
type Values struct {
	values  map[string]any
	sources map[string]Source
}

// Get geeft de waarde van een sleutel: time.Duration, int of string.
func (v Values) Get(key string) any { return v.values[key] }

// Source zegt welke laag deze sleutel levert.
func (v Values) Source(key string) Source { return v.sources[key] }

func (v Values) duration(key string) time.Duration {
	d, _ := v.values[key].(time.Duration)
	return d
}

func (v Values) ServerName() string {
	s, _ := v.values[KeyServerName].(string)
	return s
}

func (v Values) AccessTokenTTL() time.Duration   { return v.duration(KeyAccessTokenTTL) }
func (v Values) RefreshTokenTTL() time.Duration  { return v.duration(KeyRefreshTokenTTL) }
func (v Values) StreamTokenTTL() time.Duration   { return v.duration(KeyStreamTokenTTL) }
func (v Values) StreamSessionTTL() time.Duration { return v.duration(KeyStreamSessionTTL) }

func (v Values) MaxStreamSessions() int {
	n, _ := v.values[KeyMaxStreamSessions].(int)
	return n
}

// newValues bouwt de set uit de omgevingslaag met de opgeslagen sleutels
// eroverheen. Een opgeslagen waarde die niet meer door de grenzen komt wordt
// genegeerd en de omgeving wint: grenzen kunnen strenger worden na een update,
// en dan is starten met de default beter dan starten met een waarde die de
// server vandaag niet meer zou accepteren.
func newValues(base Base, stored map[string]any) Values {
	v := Values{
		values: map[string]any{
			KeyServerName:        base.ServerName,
			KeyAccessTokenTTL:    base.AccessTokenTTL,
			KeyRefreshTokenTTL:   base.RefreshTokenTTL,
			KeyStreamTokenTTL:    base.StreamTokenTTL,
			KeyStreamSessionTTL:  base.StreamSessionTTL,
			KeyMaxStreamSessions: base.MaxStreamSessions,
		},
		sources: map[string]Source{},
	}
	for _, d := range Definitions {
		v.sources[d.Key] = SourceEnv
	}
	for key, value := range stored {
		if _, ok := Find(key); !ok {
			continue
		}
		v.values[key] = value
		v.sources[key] = SourceDB
	}
	return v
}
