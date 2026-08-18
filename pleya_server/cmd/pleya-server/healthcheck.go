package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
)

// healthURL bouwt de lokale URL voor de healthcheck. Een luisteradres als
// ":8080" of "0.0.0.0:8080" wordt 127.0.0.1: de controle draait in dezelfde
// container en hoort nooit over het netwerk te gaan.
func healthURL(addr string) (string, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return "", fmt.Errorf("luisteradres %q is geen host:poort", addr)
	}
	if host == "" || host == "0.0.0.0" || host == "::" || host == "[::]" {
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port) + "/healthz", nil
}

func probe(ctx context.Context, url string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%w: status %d", errNotOK, resp.StatusCode)
	}
	return nil
}
