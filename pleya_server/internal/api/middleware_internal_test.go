package api

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// De keten hangt niet aan een database of aan ffmpeg, dus deze tests bouwen een
// Server met alleen een logger erin. Ze leggen hem wel op s.chain en niet op een
// eigen volgorde: de volgorde is de helft van wat hier bewezen moet worden.

type recordingHandler struct {
	mu      sync.Mutex
	records []slog.Record
}

func (h *recordingHandler) Enabled(context.Context, slog.Level) bool { return true }

func (h *recordingHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.records = append(h.records, r.Clone())
	return nil
}

func (h *recordingHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *recordingHandler) WithGroup(string) slog.Handler      { return h }

func (h *recordingHandler) attr(message, key string) (slog.Value, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, record := range h.records {
		if record.Message != message {
			continue
		}
		var found slog.Value
		var ok bool
		record.Attrs(func(a slog.Attr) bool {
			if a.Key == key {
				found, ok = a.Value, true
				return false
			}
			return true
		})
		if ok {
			return found, true
		}
	}
	return slog.Value{}, false
}

func testChain(inner http.Handler) (http.Handler, *recordingHandler) {
	logs := &recordingHandler{}
	s := &Server{log: slog.New(logs)}
	return s.chain(inner), logs
}

func serve(handler http.Handler, req *http.Request) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func TestEenPanicWordtDeFoutvormVanHetProtocol(t *testing.T) {
	handler, logs := testChain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("de handler viel om")
	}))

	rec := serve(handler, httptest.NewRequest(http.MethodGet, "/pleya/v1/libraries", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, wil 500", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("content-type = %q, wil json; een client die JSON verwacht mag hier geen HTML krijgen", ct)
	}

	var body struct {
		Error struct {
			Code      string         `json:"code"`
			Retryable bool           `json:"retryable"`
			Details   map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("lichaam is geen envelop: %v (%q)", err, rec.Body.String())
	}
	if body.Error.Code != CodeInternal {
		t.Fatalf("code = %q, wil %q", body.Error.Code, CodeInternal)
	}
	if body.Error.Retryable {
		t.Fatal("retryable = true; een deterministische panic hoort geen herhaling uit te lokken")
	}

	requestID, _ := body.Error.Details["request_id"].(string)
	if requestID == "" {
		t.Fatal("details.request_id ontbreekt; zonder id is de fout niet terug te vinden in het log")
	}

	// De id is alleen iets waard als hij naar de logregel met de stack wijst.
	logged, ok := logs.attr("panic in handler", "request_id")
	if !ok {
		t.Fatal("geen logregel 'panic in handler'")
	}
	if logged.String() != requestID {
		t.Fatalf("request_id in het log = %q, in het antwoord = %q", logged.String(), requestID)
	}

	stack, ok := logs.attr("panic in handler", "stack")
	if !ok || stack.String() == "" {
		t.Fatal("de stack staat niet in het log")
	}
	if strings.Contains(rec.Body.String(), "middleware_internal_test.go") {
		t.Fatal("de stack lekt naar de client")
	}
}

func TestErrAbortHandlerBlijftEenAfbrekingEnGeenFout(t *testing.T) {
	handler, logs := testChain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic(http.ErrAbortHandler)
	}))

	var recovered any
	func() {
		defer func() { recovered = recover() }()
		serve(handler, httptest.NewRequest(http.MethodGet, "/pleya/v1/stream/x", nil))
	}()

	if recovered != http.ErrAbortHandler {
		t.Fatalf("recovered = %v, wil ErrAbortHandler; net/http moet hem zelf afhandelen", recovered)
	}
	if _, ok := logs.attr("panic in handler", "stack"); ok {
		t.Fatal("een afgebroken antwoord kwam als panic in het log; dan is elke seek een foutmelding")
	}
}

func TestEenPanicNaHetEersteBlokPlaktGeenEnvelopAchterHetAntwoord(t *testing.T) {
	handler, _ := testChain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("eerste blok"))
		panic("halverwege de stream")
	}))

	rec := httptest.NewRecorder()
	var recovered any
	func() {
		defer func() { recovered = recover() }()
		handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/pleya/v1/stream/x", nil))
	}()

	if recovered == nil {
		t.Fatal("de panic werd afgevangen terwijl het antwoord al liep; dan volgt er JSON achter halve bytes")
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, wil 200; de statusregel was al weg", rec.Code)
	}
	if strings.Contains(rec.Body.String(), CodeInternal) {
		t.Fatalf("een envelop werd achter het antwoord geplakt: %q", rec.Body.String())
	}
}

func TestDeSecurityheadersStaanOokOpEenFoutantwoord(t *testing.T) {
	cases := map[string]http.Handler{
		"een gewoon antwoord": http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		}),
		"een afgevangen panic": http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
			panic("boem")
		}),
	}

	for name, inner := range cases {
		t.Run(name, func(t *testing.T) {
			handler, _ := testChain(inner)
			rec := serve(handler, httptest.NewRequest(http.MethodGet, "/pleya/v1/info", nil))

			if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
				t.Fatalf("X-Content-Type-Options = %q, wil nosniff", got)
			}
			if got := rec.Header().Get("Referrer-Policy"); got != "no-referrer" {
				t.Fatalf("Referrer-Policy = %q, wil no-referrer", got)
			}
		})
	}
}

func TestDeLichaamslimietGeldtOokZonderDecodeBody(t *testing.T) {
	var readErr error
	var read int
	handler, _ := testChain(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		n, err := io.Copy(io.Discard, r.Body)
		read, readErr = int(n), err
	}))

	t.Run("een body binnen de grens komt er heel doorheen", func(t *testing.T) {
		body := strings.Repeat("a", maxRequestBodyBytes)
		serve(handler, httptest.NewRequest(http.MethodPost, "/pleya/v1/watch-state", strings.NewReader(body)))

		if readErr != nil {
			t.Fatalf("fout op een body van precies de grens: %v", readErr)
		}
		if read != maxRequestBodyBytes {
			t.Fatalf("gelezen = %d, wil %d", read, maxRequestBodyBytes)
		}
	})

	t.Run("een body erboven wordt een fout en geen stille afkapping", func(t *testing.T) {
		body := strings.Repeat("a", maxRequestBodyBytes+1)
		serve(handler, httptest.NewRequest(http.MethodPost, "/pleya/v1/watch-state", strings.NewReader(body)))

		if readErr == nil {
			t.Fatalf("geen fout; io.LimitReader zou hier stil %d bytes hebben doorgegeven", read)
		}
		var tooLarge *http.MaxBytesError
		if !errorsAs(readErr, &tooLarge) {
			t.Fatalf("fout = %v, wil http.MaxBytesError", readErr)
		}
	})
}

// errorsAs staat hier zodat de test geen import van errors nodig heeft naast de
// rest; het gedrag is dat van errors.As.
func errorsAs(err error, target **http.MaxBytesError) bool {
	for err != nil {
		if e, ok := err.(*http.MaxBytesError); ok {
			*target = e
			return true
		}
		unwrapper, ok := err.(interface{ Unwrap() error })
		if !ok {
			return false
		}
		err = unwrapper.Unwrap()
	}
	return false
}

// TestDeWrapperSlokDeFlusherNietOp bewaakt handlers_stream.go.
//
// Die lus spoelt per blok door en test daarvoor rechtstreeks op http.Flusher.
// Een ResponseWriter-wrapper zonder Flush laat die assertie stil falen, waarna
// de lus denkt dat een blok weg is terwijl het in de buffer staat. Dat is
// precies wat het commentaar daar zegt te willen voorkomen.
func TestDeWrapperSlokDeFlusherNietOp(t *testing.T) {
	var sawFlusher bool
	flushed := make(chan struct{}, 1)

	handler, _ := testChain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		flusher, ok := w.(http.Flusher)
		sawFlusher = ok
		if ok {
			flusher.Flush()
			flushed <- struct{}{}
		}
	}))

	serve(handler, httptest.NewRequest(http.MethodGet, "/pleya/v1/stream/x", nil))

	if !sawFlusher {
		t.Fatal("de handler ziet geen http.Flusher; de doorspoellus in handlers_stream.go slaat dan stil over")
	}
	select {
	case <-flushed:
	default:
		t.Fatal("Flush kwam niet aan")
	}
}
