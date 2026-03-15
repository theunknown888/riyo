package modules

import (
	"fmt"
	"regexp"
	"net/url"
	"strings"

	"github.com/riyobox/backend/internal/models"
	"github.com/riyobox/backend/scrapers"
)

type BaseProvider struct {
	Name    string
	BaseURL string
}

func (p *BaseProvider) GetName() string {
	return p.Name
}

func (p *BaseProvider) Search(query string, isTvShow bool, season, episode int) ([]models.StreamSource, error) {
	searchQuery := query
	if isTvShow {
		searchQuery = fmt.Sprintf("%s S%02dE%02d", query, season, episode)
	}
	searchURL := fmt.Sprintf("%s/?s=%s", p.BaseURL, url.QueryEscape(searchQuery))
	html, err := scrapers.FetchHTML(searchURL)
	if err != nil {
		return nil, err
	}

	// Find the first result link
	re := regexp.MustCompile(fmt.Sprintf(`(?i)<a\s+href=["'](%s/[^"']+)["']`, regexp.QuoteMeta(p.BaseURL)))
	matches := re.FindAllStringSubmatch(html, -1)

	var allSources []models.StreamSource
	for _, m := range matches {
		contentURL := m[1]
		if strings.Contains(contentURL, "/?s=") || contentURL == p.BaseURL+"/" {
			continue
		}

		contentHTML, err := scrapers.FetchHTML(contentURL)
		if err != nil {
			continue
		}

		// Extract using all methods
		links := scrapers.ExtractVideoSources(contentHTML)
		links = append(links, scrapers.ExtractJSVariables(contentHTML)...)
		links = append(links, scrapers.ExtractJSONConfig(contentHTML)...)

		embeds := scrapers.ExtractEmbeds(contentHTML)
		for _, embed := range embeds {
			allSources = append(allSources, models.StreamSource{
				Label:    p.Name + " (Embed)",
				URL:      embed,
				Type:     "embed",
				Provider: strings.ToLower(p.Name),
				Quality:  "720p",
			})
		}

		for _, link := range links {
			allSources = append(allSources, models.StreamSource{
				Label:    p.Name,
				URL:      link,
				Type:     "direct",
				Provider: strings.ToLower(p.Name),
				Quality:  "1080p",
			})
		}

		if len(allSources) > 0 {
			break // Found sources from the first relevant result
		}
	}

	return allSources, nil
}
