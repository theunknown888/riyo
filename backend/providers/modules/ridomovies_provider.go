package modules

func NewRidoMoviesProvider() *GenericProvider {
	return NewGenericProvider("RidoMovies", "https://ridomovies.tv")
}
