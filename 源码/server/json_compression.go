package main

import (
	"bytes"
	"compress/gzip"
	"net/http"
	"strconv"
	"strings"
)

type bufferedJSON struct {
	parent http.ResponseWriter
	body   bytes.Buffer
	status int
}

func (w *bufferedJSON) Header() http.Header { return w.parent.Header() }
func (w *bufferedJSON) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
	}
}
func (w *bufferedJSON) Write(data []byte) (int, error) {
	if w.status == 0 {
		w.status = 200
	}
	return w.body.Write(data)
}

// A trajectory is immutable data repeated in room snapshots. Compress API
// JSON only when the client accepts gzip; encode after the handler returns,
// so compression never holds the world/room mutex or blocks another action.
func compressGameJSON(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/stream" {
			next.ServeHTTP(w, r)
			return
		}
		accepts := false
		for _, encoding := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
			fields := strings.Split(strings.TrimSpace(encoding), ";")
			if fields[0] != "gzip" {
				continue
			}
			accepts = true
			for _, parameter := range fields[1:] {
				parts := strings.SplitN(strings.TrimSpace(parameter), "=", 2)
				if len(parts) == 2 && parts[0] == "q" {
					if quality, e := strconv.ParseFloat(parts[1], 64); e == nil && quality <= 0 {
						accepts = false
					}
				}
			}
		}
		if !accepts || !strings.HasPrefix(r.URL.Path, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		capture := &bufferedJSON{parent: w}
		next.ServeHTTP(capture, r)
		w.Header().Add("Vary", "Accept-Encoding")
		if capture.status == 0 {
			capture.status = 200
		}
		if capture.body.Len() < 1024 || capture.status == 204 || capture.status == 304 || r.Method == http.MethodHead {
			w.WriteHeader(capture.status)
			if r.Method != http.MethodHead {
				w.Write(capture.body.Bytes())
			}
			return
		}
		var encoded bytes.Buffer
		writer, _ := gzip.NewWriterLevel(&encoded, gzip.BestSpeed)
		writer.Write(capture.body.Bytes())
		writer.Close()
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Del("Content-Length")
		w.WriteHeader(capture.status)
		w.Write(encoded.Bytes())
	})
}
