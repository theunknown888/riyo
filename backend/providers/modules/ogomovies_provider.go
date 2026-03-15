package modules

func NewOgomoviesProvider() *GenericProvider {
	return NewGenericProvider("Ogomovies", "https://ogomovies.org")
}
