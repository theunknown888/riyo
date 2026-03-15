package modules

func NewMovieBoxProvider() *GenericProvider {
	return NewGenericProvider("MovieBox", "https://moviebox.ng")
}
