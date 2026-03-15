package services

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/riyobox/backend/internal/models"
	"github.com/riyobox/backend/providers"
)

type VideoExtractor struct {
	client *http.Client
	finder *UniversalFinder
}

func NewVideoExtractor() *VideoExtractor {
	return &VideoExtractor{
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		finder: NewUniversalFinder(),
	}
}

func (e *VideoExtractor) ExtractSources(tmdbID int, title string, isTvShow bool, season, episode int) []models.StreamSource {
	var allSources []models.StreamSource
	var mu sync.Mutex
	var wg sync.WaitGroup

	// --- 1. EXISTING EMBED PROVIDERS ---
	var embedProviders []providers.EmbedProvider
	if isTvShow {
		embedProviders = providers.GetTVEmbedProviders()
	} else {
		embedProviders = providers.GetEmbedProviders()
	}

	for _, p := range embedProviders {
		wg.Add(1)
		go func(p providers.EmbedProvider) {
			defer wg.Done()

			var url string
			if isTvShow {
				s, ep := season, episode
				if s < 1 { s = 1 }
				if ep < 1 { ep = 1 }
				url = providers.GenerateTVURL(p, tmdbID, s, ep)
			} else {
				url = providers.GenerateMovieURL(p, tmdbID)
			}

			// Add the Embed Source
			mu.Lock()
			allSources = append(allSources, models.StreamSource{
				Label:    p.Name + " (Embed)",
				URL:      url,
				Type:     "embed",
				Provider: strings.ToLower(p.Name),
				Quality:  "720p",
			})
			mu.Unlock()

			// Use Universal Finder to discover direct links from embed
			discovered := e.finder.FindSources(url)
			for _, link := range discovered {
				if e.ValidateLink(link) {
					mu.Lock()
					allSources = append(allSources, models.StreamSource{
						Label:    p.Name + " (Direct)",
						URL:      link,
						Type:     e.DetectType(link),
						Provider: strings.ToLower(p.Name),
						Quality:  e.finder.DetectQuality(link),
					})
					mu.Unlock()
				}
			}
		}(p)
	}

	// --- 2. NEW SCRAPING PROVIDERS ---
	if title != "" {
		newProviders := providers.GetAllProviders()
		for _, p := range newProviders {
			wg.Add(1)
			go func(p providers.Provider) {
				defer wg.Done()

				sources, err := p.Search(title, isTvShow, season, episode)
				if err == nil {
					for _, s := range sources {
						if e.ValidateLink(s.URL) {
							mu.Lock()
							allSources = append(allSources, s)
							mu.Unlock()
						}
					}
				}
			}(p)
		}
	}

	wg.Wait()
	return e.deduplicateSources(allSources)
}

func (e *VideoExtractor) ValidateLink(url string) bool {
	if url == "" {
		return false
	}
	req, err := http.NewRequest("HEAD", url, nil)
	if err != nil {
		return false
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

	resp, err := e.client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusForbidden // Some servers block HEAD but work for GET
}

func (e *VideoExtractor) DetectType(url string) string {
	if strings.Contains(url, ".m3u8") {
		return "hls"
	}
	if strings.Contains(url, ".mpd") {
		return "dash"
	}
	if strings.Contains(url, ".mp4") {
		return "direct"
	}
	return "embed"
}

func (e *VideoExtractor) deduplicateSources(sources []models.StreamSource) []models.StreamSource {
	keys := make(map[string]bool)
	var list []models.StreamSource
	for _, entry := range sources {
		if _, value := keys[entry.URL]; !value {
			keys[entry.URL] = true
			list = append(list, entry)
		}
	}
	return list
}
