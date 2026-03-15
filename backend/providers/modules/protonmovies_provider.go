package modules

func NewProtonMoviesProvider() *GenericProvider {
	return NewGenericProvider("ProtonMovies", "https://protonmovies.to")
}
