package modules

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/riyobox/backend/internal/models"
	"github.com/riyobox/backend/scrapers"
)

type UHDMoviesProvider struct {
	BaseProvider
}

func NewUHDMoviesProvider() *UHDMoviesProvider {
	return &UHDMoviesProvider{
		BaseProvider: BaseProvider{
			Name:    "UHDMovies",
			BaseURL: "https://uhdmovies.vip",
		},
	}
}

func (p *UHDMoviesProvider) Search(query string, isTvShow bool, season, episode int) ([]models.StreamSource, error) {
	searchURL := fmt.Sprintf("%s/?s=%s", p.BaseURL, url.QueryEscape(query))
	html, err := scrapers.FetchHTML(searchURL)
	if err != nil {
		return nil, err
	}

	// Basic implementation, will be refined if needed
	links := scrapers.ExtractVideoSources(html)
	links = append(links, scrapers.ExtractJSVariables(html)...)

	var sources []models.StreamSource
	for _, link := range links {
		sources = append(sources, models.StreamSource{
			Label:    p.Name,
			URL:      link,
			Type:     "direct",
			Provider: strings.ToLower(p.Name),
			Quality:  "1080p",
		})
	}
	return sources, nil
}
