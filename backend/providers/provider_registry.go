package providers

import (
	"github.com/riyobox/backend/providers/modules"
)

func GetAllProviders() []Provider {
	return []Provider{
		modules.NewUHDMoviesProvider(),
		modules.NewProtonMoviesProvider(),
		modules.NewFilmyFlyProvider(),
		modules.NewMovieBoxProvider(),
		modules.NewMovies4UProvider(),
		modules.NewKmMoviesProvider(),
		modules.NewZeeflizProvider(),
		modules.NewRingzProvider(),
		modules.NewHdHub4uProvider(),
		modules.NewOgomoviesProvider(),
		modules.NewMoviezWapProvider(),
		modules.NewShowBoxProvider(),
		modules.NewRidoMoviesProvider(),
		modules.NewFlixHQProvider(),
		modules.NewPrimeWireProvider(),
	}
}
