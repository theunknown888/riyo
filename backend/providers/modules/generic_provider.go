package modules

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/riyobox/backend/internal/models"
	"github.com/riyobox/backend/scrapers"
)

type GenericProvider struct {
	BaseProvider
}

func NewGenericProvider(name, baseURL string) *GenericProvider {
	return &GenericProvider{
		BaseProvider: BaseProvider{
			Name:    name,
			BaseURL: baseURL,
		},
	}
}

func (p *GenericProvider) Search(query string, isTvShow bool, season, episode int) ([]models.StreamSource, error) {
	searchURL := fmt.Sprintf("%s/?s=%s", p.BaseURL, url.QueryEscape(query))
	html, err := scrapers.FetchHTML(searchURL)
	if err != nil {
		return nil, err
	}

	links := scrapers.ExtractVideoSources(html)
	links = append(links, scrapers.ExtractJSVariables(html)...)
	links = append(links, scrapers.ExtractJSONConfig(html)...)
	links = append(links, scrapers.ExtractIframes(html)...)

	var sources []models.StreamSource
	for _, link := range links {
		sources = append(sources, models.StreamSource{
			Label:    p.Name,
			URL:      link,
			Type:     "direct",
			Provider: strings.ToLower(p.Name),
			Quality:  "720p",
		})
	}
	return sources, nil
}
