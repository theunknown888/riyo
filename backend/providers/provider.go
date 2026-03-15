package providers

import (
	"github.com/riyobox/backend/internal/models"
)

type Provider interface {
	GetName() string
	Search(query string, isTvShow bool, season, episode int) ([]models.StreamSource, error)
}
