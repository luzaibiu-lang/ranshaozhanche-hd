package main

import (
	"bytes"
	"compress/gzip"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAPICompressionPreservesJSONAndConditionalResponses(t *testing.T) {
	payload := bytes.Repeat([]byte(`{"x":123.456,"y":456.789},`), 2000)
	h := compressGameJSON(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("ETag", `"fixture"`)
		if r.Header.Get("If-None-Match") == `"fixture"` {
			w.WriteHeader(304)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(payload)
	}))
	for _, encoding := range []string{"", "gzip;q=0", "gzip, deflate"} {
		r := httptest.NewRequest("GET", "/api/state", nil)
		r.Header.Set("Accept-Encoding", encoding)
		out := httptest.NewRecorder()
		h.ServeHTTP(out, r)
		body := out.Body.Bytes()
		if encoding == "gzip, deflate" {
			if out.Header().Get("Content-Encoding") != "gzip" || len(body) >= len(payload)/4 {
				t.Fatal("trajectory JSON was not compressed effectively")
			}
			reader, e := gzip.NewReader(bytes.NewReader(body))
			if e != nil {
				t.Fatal(e)
			}
			body, e = io.ReadAll(reader)
			reader.Close()
			if e != nil {
				t.Fatal(e)
			}
		} else if out.Header().Get("Content-Encoding") != "" {
			t.Fatal("compressed for a client that does not accept gzip")
		}
		if !bytes.Equal(body, payload) {
			t.Fatal("wire JSON changed during compression")
		}
	}
	r := httptest.NewRequest("GET", "/api/state", nil)
	r.Header.Set("Accept-Encoding", "gzip")
	r.Header.Set("If-None-Match", `"fixture"`)
	out := httptest.NewRecorder()
	h.ServeHTTP(out, r)
	if out.Code != 304 || out.Body.Len() != 0 || out.Header().Get("Content-Encoding") != "" {
		t.Fatal("conditional 304 gained a compressed body")
	}
}
