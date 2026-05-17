package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	ImmichURL      string
	Port           string
	Timeout        time.Duration
	CacheDir       string
	ThumbsPath     string
	EncodedPath    string
	AuthCacheTTL   time.Duration
}

func loadConfig() (*Config, error) {
	immichURL := os.Getenv("IMMICH_INTERNAL_URL")
	if immichURL == "" {
		return nil, fmt.Errorf("IMMICH_INTERNAL_URL is required")
	}

	port := os.Getenv("AUTH_PORT")
	if port == "" {
		port = "8088"
	}

	timeoutSec := 5
	if v := os.Getenv("AUTH_TIMEOUT"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			return nil, fmt.Errorf("invalid AUTH_TIMEOUT: %w", err)
		}
		timeoutSec = n
	}

	thumbsPath := os.Getenv("IMMICH_THUMBS_PATH")
	if thumbsPath == "" {
		thumbsPath = "thumbs"
	}

	encodedPath := os.Getenv("IMMICH_ENCODED_PATH")
	if encodedPath == "" {
		encodedPath = "encoded-video"
	}

	cacheTTL := 10 * time.Second
	if v := os.Getenv("AUTH_CACHE_TTL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return nil, fmt.Errorf("invalid AUTH_CACHE_TTL: %w", err)
		}
		cacheTTL = d
	}

	return &Config{
		ImmichURL:    immichURL,
		Port:         port,
		Timeout:      time.Duration(timeoutSec) * time.Second,
		CacheDir:     os.Getenv("CACHE_DIR"),
		ThumbsPath:   thumbsPath,
		EncodedPath:  encodedPath,
		AuthCacheTTL: cacheTTL,
	}, nil
}
