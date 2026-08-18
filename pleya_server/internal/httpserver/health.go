package httpserver

import (
	"context"
	"net/http"
)

// healthz zegt of het proces leeft. Dit endpoint wordt niet rood van een
// database die even weg is; dat onderscheid is het hele punt van twee
// endpoints in plaats van een.
func healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, `{"status":"ok"}`)
}

// readyz zegt of de server aanvragen kan verwerken. Voor deze fundering is dat
// precies een ding: is de database bereikbaar.
//
// Het antwoord bevat geen verbindingsgegevens, geen hostnaam en geen versie.
// Een readinesscontrole is doorgaans onbeschermd bereikbaar, en dan is elk
// detail erin een gratis inlichting.
func readyz(db Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			writeJSON(w, http.StatusServiceUnavailable, `{"status":"not ready","reason":"database"}`)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), ReadyTimeout)
		defer cancel()

		if err := db.Ping(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, `{"status":"not ready","reason":"database"}`)
			return
		}
		writeJSON(w, http.StatusOK, `{"status":"ready"}`)
	}
}

func writeJSON(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body + "\n"))
}
