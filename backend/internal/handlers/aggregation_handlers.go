package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/riyobox/backend/internal/db"
	"github.com/riyobox/backend/internal/models"
	"github.com/riyobox/backend/services"
	"github.com/riyobox/backend/utils"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

var MetadataSvc *services.MetadataService
var VideoExt *services.VideoExtractor

func GetHome(c *gin.Context) {
	collection := db.DB.Collection("movies")

	trendingMovies := []models.Movie{}
	popularMovies := []models.Movie{}
	topRatedMovies := []models.Movie{}
	trendingTV := []models.Movie{}

	opts := options.Find().SetLimit(10).SetSort(bson.M{"createdAt": -1})

	cursor, _ := collection.Find(context.TODO(), bson.M{"isTrending": true, "isTvShow": false, "isPublished": true}, opts)
	cursor.All(context.TODO(), &trendingMovies)

	cursor, _ = collection.Find(context.TODO(), bson.M{"isTvShow": false, "isPublished": true}, opts)
	cursor.All(context.TODO(), &popularMovies)

	optsRating := options.Find().SetLimit(10).SetSort(bson.M{"rating": -1})
	cursor, _ = collection.Find(context.TODO(), bson.M{"isTvShow": false, "isPublished": true}, optsRating)
	cursor.All(context.TODO(), &topRatedMovies)

	cursor, _ = collection.Find(context.TODO(), bson.M{"isTrending": true, "isTvShow": true, "isPublished": true}, opts)
	cursor.All(context.TODO(), &trendingTV)

	c.JSON(http.StatusOK, gin.H{
		"trendingMovies":  trendingMovies,
		"popularMovies":   popularMovies,
		"topRatedMovies":  topRatedMovies,
		"latestMovies":    popularMovies, // Simplified
		"trendingTV":      trendingTV,
		"popularTV":       trendingTV,    // Simplified
	})
}

func GetMoviesByFilter(filter bson.M) gin.HandlerFunc {
	return func(c *gin.Context) {
		collection := db.DB.Collection("movies")
		opts := options.Find().SetLimit(20).SetSort(bson.M{"createdAt": -1})

		var results []models.Movie
		cursor, err := collection.Find(context.TODO(), filter, opts)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"message": err.Error()})
			return
		}
		cursor.All(context.TODO(), &results)
		c.JSON(http.StatusOK, results)
	}
}

func GetMovieSources(c *gin.Context) {
	idStr := c.Param("id")
	collection := db.DB.Collection("movies")
	var movie models.Movie

	if id, err := bson.ObjectIDFromHex(idStr); err == nil {
		collection.FindOne(context.TODO(), bson.M{"_id": id}).Decode(&movie)
	} else if tmdbID, err := strconv.Atoi(idStr); err == nil {
		collection.FindOne(context.TODO(), bson.M{"tmdbId": tmdbID}).Decode(&movie)
	}

	if movie.TMDbID == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Movie not found"})
		return
	}

	sources := VideoExt.ExtractSources(movie.TMDbID, movie.Title, movie.IsTvShow, 0, 0)
	subtitles := utils.GetSubtitles(movie.TMDbID, movie.IsTvShow, 0, 0)

	c.JSON(http.StatusOK, gin.H{
		"sources":   sources,
		"subtitles": subtitles,
	})
}

func GetTVSources(c *gin.Context) {
	idStr := c.Param("id")
	season, _ := strconv.Atoi(c.Param("season"))
	episode, _ := strconv.Atoi(c.Param("episode"))

	collection := db.DB.Collection("movies")
	var movie models.Movie

	if id, err := bson.ObjectIDFromHex(idStr); err == nil {
		collection.FindOne(context.TODO(), bson.M{"_id": id}).Decode(&movie)
	} else if tmdbID, err := strconv.Atoi(idStr); err == nil {
		collection.FindOne(context.TODO(), bson.M{"tmdbId": tmdbID}).Decode(&movie)
	}

	if movie.TMDbID == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Not found"})
		return
	}

	sources := VideoExt.ExtractSources(movie.TMDbID, movie.Title, true, season, episode)
	subtitles := utils.GetSubtitles(movie.TMDbID, true, season, episode)

	c.JSON(http.StatusOK, gin.H{
		"sources":   sources,
		"subtitles": subtitles,
	})
}

func SearchMovies(c *gin.Context) {
	query := c.Query("query")
	collection := db.DB.Collection("movies")

	filter := bson.M{
		"title": bson.M{"$regex": query, "$options": "i"},
	}

	cursor, err := collection.Find(context.TODO(), filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": err.Error()})
		return
	}
	defer cursor.Close(context.TODO())

	var results []models.Movie
	cursor.All(context.TODO(), &results)

	c.JSON(http.StatusOK, results)
}
