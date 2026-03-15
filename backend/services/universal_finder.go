package services

import (
	"strings"
	"sync"

	"github.com/riyobox/backend/scrapers"
)

type UniversalFinder struct{}

func NewUniversalFinder() *UniversalFinder {
	return &UniversalFinder{}
}

func (f *UniversalFinder) FindSources(url string) []string {
	var allSources []string
	var mu sync.Mutex

	// METHOD 6 – REDIRECT EXTRACTION (initial)
	finalURL, _ := scrapers.FollowRedirects(url)
	html, err := scrapers.FetchHTML(finalURL)
	if err != nil {
		return nil
	}

	// 1. Try HTML parsing (METHOD 1)
	htmlSources := scrapers.ExtractVideoSources(html)
	mu.Lock()
	allSources = append(allSources, htmlSources...)
	mu.Unlock()

	// 2. Try iframe extraction (METHOD 2)
	iframes := scrapers.ExtractIframes(html)
	var wg sync.WaitGroup
	for _, iframe := range iframes {
		wg.Add(1)
		go func(iframeURL string) {
			defer wg.Done()
			// Recursive discovery (depth 1)
			iframeHTML, err := scrapers.FetchHTML(iframeURL)
			if err == nil {
				s := scrapers.ExtractVideoSources(iframeHTML)
				js := scrapers.ExtractJSVariables(iframeHTML)
				json := scrapers.ExtractJSONConfig(iframeHTML)
				mu.Lock()
				allSources = append(allSources, s...)
				allSources = append(allSources, js...)
				allSources = append(allSources, json...)
				mu.Unlock()
			}
		}(iframe)
	}

	// 3. Try JavaScript parsing (METHOD 3)
	jsSources := scrapers.ExtractJSVariables(html)
	mu.Lock()
	allSources = append(allSources, jsSources...)
	mu.Unlock()

	// 4. Try JSON config parsing (METHOD 4)
	jsonSources := scrapers.ExtractJSONConfig(html)
	mu.Lock()
	allSources = append(allSources, jsonSources...)
	mu.Unlock()

	// 5. Try embed extraction (METHOD 7)
	embeds := scrapers.ExtractEmbeds(html)
	mu.Lock()
	allSources = append(allSources, embeds...)
	mu.Unlock()

	wg.Wait()

	// METHOD 6 – REDIRECT EXTRACTION (for all found sources)
	var finalSources []string
	for _, s := range allSources {
		fSource, _ := scrapers.FollowRedirects(s)
		finalSources = append(finalSources, fSource)
	}

	return f.uniqueSources(finalSources)
}

func (f *UniversalFinder) uniqueSources(sources []string) []string {
	keys := make(map[string]bool)
	var list []string
	for _, entry := range sources {
		if _, value := keys[entry]; !value && entry != "" {
			keys[entry] = true
			list = append(list, entry)
		}
	}
	return list
}

func (f *UniversalFinder) DetectQuality(url string) string {
	lowerURL := strings.ToLower(url)
	if strings.Contains(lowerURL, "2160") || strings.Contains(lowerURL, "4k") {
		return "4K"
	}
	if strings.Contains(lowerURL, "1080") {
		return "1080p"
	}
	if strings.Contains(lowerURL, "720") {
		return "720p"
	}
	if strings.Contains(lowerURL, "480") {
		return "480p"
	}
	return "720p"
}
