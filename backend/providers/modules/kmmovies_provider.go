package modules

func NewKmMoviesProvider() *GenericProvider {
	return NewGenericProvider("KmMovies", "https://kmmovies.icu")
}
