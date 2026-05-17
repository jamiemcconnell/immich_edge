package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

var (
	uuidSeg      = `[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`
	thumbPattern = regexp.MustCompile(`/api/assets/(` + uuidSeg + `)/thumbnail`)
	videoPattern = regexp.MustCompile(`/api/assets/(` + uuidSeg + `)/video/playback`)
)

type immichUser struct {
	ID string `json:"id"`
}

type immichAsset struct {
	OwnerID string `json:"ownerId"`
}

type immichSharedLink struct {
	UserID string `json:"userId"`
}

// authCache is a simple in-memory TTL cache keyed by a hash of the credential.
// Used for both auth results (credential → userId) and membership checks (uuid+key → ownerId).
type authCache struct {
	mu      sync.Mutex
	entries map[[32]byte]cacheEntry
	ttl     time.Duration
}

type cacheEntry struct {
	userID  string
	expires time.Time
}

func newAuthCache(ttl time.Duration) *authCache {
	c := &authCache{
		entries: make(map[[32]byte]cacheEntry),
		ttl:     ttl,
	}
	go c.evictLoop()
	return c
}

func (c *authCache) evictLoop() {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()
	for range tick.C {
		now := time.Now()
		c.mu.Lock()
		for k, e := range c.entries {
			if now.After(e.expires) {
				delete(c.entries, k)
			}
		}
		c.mu.Unlock()
	}
}

func (c *authCache) get(key [32]byte) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || time.Now().After(e.expires) {
		delete(c.entries, key)
		return "", false
	}
	return e.userID, true
}

func (c *authCache) set(key [32]byte, userID string) {
	c.mu.Lock()
	c.entries[key] = cacheEntry{userID: userID, expires: time.Now().Add(c.ttl)}
	c.mu.Unlock()
}

func credHash(parts ...string) [32]byte {
	h := sha256.New()
	for _, p := range parts {
		h.Write([]byte(p))
		h.Write([]byte{0})
	}
	var out [32]byte
	copy(out[:], h.Sum(nil))
	return out
}

type server struct {
	cfg             *Config
	client          *http.Client
	cache           *authCache // credential → userId
	membershipCache *authCache // uuid+sharedKey → ownerId
}

func newServer(cfg *Config) *server {
	s := &server{
		cfg: cfg,
		client: &http.Client{
			Timeout: cfg.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 100,
				IdleConnTimeout:     90 * time.Second,
				DisableKeepAlives:   false,
				TLSHandshakeTimeout: 5 * time.Second,
			},
		},
	}
	if cfg.AuthCacheTTL > 0 {
		s.cache = newAuthCache(cfg.AuthCacheTTL)
		s.membershipCache = newAuthCache(cfg.AuthCacheTTL)
	}
	return s
}

func (s *server) validate(w http.ResponseWriter, r *http.Request) {
	originalURI := r.Header.Get("X-Original-URI")
	parsed, _ := url.Parse(originalURI)
	sharedKey := ""
	sharedPassword := ""
	if parsed != nil {
		sharedKey = parsed.Query().Get("key")
		sharedPassword = parsed.Query().Get("password")
	}

	var uuid, assetType string
	if m := thumbPattern.FindStringSubmatch(originalURI); m != nil {
		uuid, assetType = m[1], "thumb"
	} else if m := videoPattern.FindStringSubmatch(originalURI); m != nil {
		uuid, assetType = m[1], "video"
	}

	var userID string
	var err error
	if sharedKey != "" {
		userID, err = s.getSharedLinkUserID(sharedKey, sharedPassword, r)
	} else {
		userID, err = s.getUserID(r)
	}
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	resolvedID := userID
	if len(uuid) >= 4 {
		aa, bb := uuid[:2], uuid[2:4]

		if sharedKey != "" {
			// Shared link: always verify the UUID is actually in the shared album.
			// getAssetMembership calls Immich with ?key= which returns 403 if the
			// UUID is not in the album — catches key-for-wrong-album attacks.
			ownerID, err := s.getAssetMembership(r, uuid, sharedKey)
			if err != nil {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			resolvedID = ownerID
		} else if s.cfg.CacheDir != "" {
			// Session auth: owner-resolution fallback for shared albums.
			if !s.fileExists(userID, uuid, aa, bb, assetType) {
				ownerID, err := s.getAssetOwnerID(r, uuid, "")
				if err == nil && ownerID != "" && ownerID != userID && s.fileExists(ownerID, uuid, aa, bb, assetType) {
					resolvedID = ownerID
				}
			}
		}
	}

	w.Header().Set("X-User-Id", resolvedID)
	w.WriteHeader(http.StatusOK)
}

// getAssetMembership verifies a UUID is accessible via a shared link key and returns
// the asset's ownerId. Results are cached for AuthCacheTTL. Failures (403, network
// errors) are never cached so a photo added to an album is immediately accessible.
func (s *server) getAssetMembership(r *http.Request, uuid, sharedKey string) (string, error) {
	if s.membershipCache != nil {
		ck := credHash("member", uuid, sharedKey)
		if ownerID, ok := s.membershipCache.get(ck); ok {
			return ownerID, nil
		}
	}

	ownerID, err := s.getAssetOwnerID(r, uuid, sharedKey)
	if err != nil {
		return "", err
	}

	if s.membershipCache != nil {
		s.membershipCache.set(credHash("member", uuid, sharedKey), ownerID)
	}
	return ownerID, nil
}

func (s *server) fileExists(userID, uuid, aa, bb, assetType string) bool {
	var candidates []string
	if assetType == "thumb" {
		base := filepath.Join(s.cfg.CacheDir, s.cfg.ThumbsPath, userID, aa, bb, uuid)
		candidates = []string{
			base + "-thumbnail.webp",
			base + "_thumbnail.webp",
			base + "-preview.jpeg",
			base + "_preview.jpeg",
		}
	} else {
		base := filepath.Join(s.cfg.CacheDir, s.cfg.EncodedPath, userID, aa, bb, uuid)
		candidates = []string{base + ".mp4"}
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return true
		}
	}
	return false
}

func (s *server) getSharedLinkUserID(key, password string, r *http.Request) (string, error) {
	cookie := r.Header.Get("Cookie")
	if s.cache != nil {
		ck := credHash("link", key, cookie)
		if uid, ok := s.cache.get(ck); ok {
			return uid, nil
		}
	}

	apiURL := s.cfg.ImmichURL + "/api/shared-links/me?key=" + url.QueryEscape(key)
	if password != "" {
		apiURL += "&password=" + url.QueryEscape(password)
	}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("shared link returned %d", resp.StatusCode)
	}

	var link immichSharedLink
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&link); err != nil || link.UserID == "" {
		return "", fmt.Errorf("invalid shared link response")
	}

	if s.cache != nil {
		s.cache.set(credHash("link", key, cookie), link.UserID)
	}
	return link.UserID, nil
}

func (s *server) getUserID(r *http.Request) (string, error) {
	var credParts []string
	if v := r.Header.Get("x-api-key"); v != "" {
		credParts = []string{"apikey", v}
	} else if v := r.Header.Get("Authorization"); v != "" {
		credParts = []string{"auth", v}
	} else {
		for _, c := range r.Cookies() {
			if c.Name == "immich_access_token" {
				credParts = []string{"token", c.Value}
				break
			}
		}
	}

	if s.cache != nil && len(credParts) > 0 {
		ck := credHash(credParts...)
		if uid, ok := s.cache.get(ck); ok {
			return uid, nil
		}
	}

	req, err := http.NewRequest("GET", s.cfg.ImmichURL+"/api/users/me", nil)
	if err != nil {
		return "", err
	}
	copyAuthHeaders(r, req)

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("immich returned %d", resp.StatusCode)
	}

	var u immichUser
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&u); err != nil || u.ID == "" {
		return "", fmt.Errorf("invalid user response")
	}

	if s.cache != nil && len(credParts) > 0 {
		s.cache.set(credHash(credParts...), u.ID)
	}
	return u.ID, nil
}

func (s *server) getAssetOwnerID(r *http.Request, uuid string, sharedKey string) (string, error) {
	apiURL := s.cfg.ImmichURL + "/api/assets/" + uuid
	if sharedKey != "" {
		apiURL += "?key=" + url.QueryEscape(sharedKey)
	}

	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	if sharedKey == "" {
		copyAuthHeaders(r, req)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("asset lookup returned %d", resp.StatusCode)
	}

	var a immichAsset
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&a); err != nil {
		return "", err
	}
	return a.OwnerID, nil
}

func copyAuthHeaders(from, to *http.Request) {
	if v := from.Header.Get("Authorization"); v != "" {
		to.Header.Set("Authorization", v)
	}
	if v := from.Header.Get("x-api-key"); v != "" {
		to.Header.Set("x-api-key", v)
	}
	for _, c := range from.Cookies() {
		if c.Name == "immich_access_token" {
			to.AddCookie(c)
			break
		}
	}
}

func (s *server) health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"ok"}`)
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	srv := newServer(cfg)
	mux := http.NewServeMux()
	mux.HandleFunc("/validate", srv.validate)
	mux.HandleFunc("/health", srv.health)

	addr := ":" + cfg.Port
	log.Printf("auth service listening on %s, immich=%s, cacheDir=%s, authCacheTTL=%s",
		addr, cfg.ImmichURL, cfg.CacheDir, cfg.AuthCacheTTL)

	httpSrv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	if err := httpSrv.ListenAndServe(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
