package scrapers

import (
	"encoding/json"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

var client = &http.Client{
	Timeout: 15 * time.Second,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		return nil // Follow redirects
	},
}

func FetchHTML(url string) (string, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
	req.Header.Set("Referer", url)

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return string(body), nil
}

func ExtractIframes(html string) []string {
	re := regexp.MustCompile(`(?i)<iframe.*?src=["'](.*?)["']`)
	matches := re.FindAllStringSubmatch(html, -1)

	var urls []string
	for _, m := range matches {
		if len(m) > 1 {
			u := m[1]
			if strings.HasPrefix(u, "//") {
				u = "https:" + u
			}
			urls = append(urls, u)
		}
	}
	return urls
}

func ExtractVideoSources(html string) []string {
	// METHOD 1 – HTML PARSING & METHOD 5 - NETWORK DISCOVERY (MANIFESTS)
	patterns := []string{
		`https?://[^\s"']+\.m3u8[^\s"']*`,
		`https?://[^\s"']+\.mp4[^\s"']*`,
		`https?://[^\s"']+\.mpd[^\s"']*`, // DASH manifest
		`file:\s*["'](https?://.*?)["']`,
		`source\s+src=["'](https?://.*?)["']`,
		`video_url\s*:\s*["'](https?://.*?)["']`,
	}

	var sources []string
	for _, p := range patterns {
		re := regexp.MustCompile(p)
		matches := re.FindAllStringSubmatch(html, -1)
		for _, m := range matches {
			if len(m) > 1 {
				sources = append(sources, m[1])
			} else if len(m) == 0 {
				// For non-capturing group regexes
				rawMatches := re.FindAllString(html, -1)
				sources = append(sources, rawMatches...)
			}
		}
	}

	return sources
}

func ExtractJSVariables(html string) []string {
	// METHOD 3 – JAVASCRIPT VARIABLE PARSING
	patterns := []string{
		`["']?file["']?\s*:\s*["'](https?://.*?)["']`,
		`["']?sources["']?\s*:\s*\[(.*?)\]`,
		`["']?video_url["']?\s*:\s*["'](https?://.*?)["']`,
		`["']?url["']?\s*:\s*["'](https?://.*?)["']`,
		`var\s+\w+\s*=\s*["'](https?://.*?)["']`,
	}

	var sources []string
	for _, p := range patterns {
		re := regexp.MustCompile(p)
		matches := re.FindAllStringSubmatch(html, -1)
		for _, m := range matches {
			if len(m) > 1 {
				if strings.Contains(m[1], "http") {
					sources = append(sources, m[1])
				} else if p == `["']?sources["']?\s*:\s*\[(.*?)\]` {
					// Recursive extraction for sources array
					innerRe := regexp.MustCompile(`["']?(?:file|src|url)["']?\s*:\s*["'](https?://.*?)["']`)
					innerMatches := innerRe.FindAllStringSubmatch(m[1], -1)
					for _, im := range innerMatches {
						if len(im) > 1 {
							sources = append(sources, im[1])
						}
					}
				}
			}
		}
	}
	return sources
}

func ExtractJSONConfig(html string) []string {
	// METHOD 4 – PLAYER CONFIG PARSING
	var sources []string
	// Look for JSON objects that might contain video sources (common in JWPlayer, Video.js)
	re := regexp.MustCompile(`(?s)\{.*?"(?:sources|playlist|file)".*?\}`)
	matches := re.FindAllString(html, -1)

	for _, m := range matches {
		var data interface{}
		if err := json.Unmarshal([]byte(m), &data); err == nil {
			sources = append(sources, findURLsInJSON(data)...)
		}
	}
	return sources
}

func findURLsInJSON(data interface{}) []string {
	var urls []string
	switch v := data.(type) {
	case string:
		if strings.HasPrefix(v, "http") && (strings.Contains(v, ".mp4") || strings.Contains(v, ".m3u8") || strings.Contains(v, ".mpd")) {
			urls = append(urls, v)
		}
	case map[string]interface{}:
		for _, val := range v {
			urls = append(urls, findURLsInJSON(val)...)
		}
	case []interface{}:
		for _, val := range v {
			urls = append(urls, findURLsInJSON(val)...)
		}
	}
	return urls
}

func FollowRedirects(url string) (string, error) {
	// METHOD 6 – REDIRECT EXTRACTION
	req, _ := http.NewRequest("HEAD", url, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

	resp, err := client.Do(req)
	if err != nil {
		return url, err
	}
	defer resp.Body.Close()
	return resp.Request.URL.String(), nil
}

func ExtractEmbeds(html string) []string {
	// METHOD 7 – EMBED PROVIDER EXTRACTION
	embedProviders := []string{
		"vidsrc.to",
		"2embed.cc",
		"multiembed.mov",
		"vidlink.pro",
		"player.autoembed.cc",
		"vidsrc.me",
		"superembed.stream",
	}

	var embeds []string
	iframes := ExtractIframes(html)
	for _, iframe := range iframes {
		for _, provider := range embedProviders {
			if strings.Contains(iframe, provider) {
				embeds = append(embeds, iframe)
				break
			}
		}
	}
	return embeds
}
