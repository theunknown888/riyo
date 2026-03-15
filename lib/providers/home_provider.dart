
import 'package:flutter/material.dart';
import 'package:riyo/models/movie.dart';
import 'package:riyo/services/api_service.dart';

class HomeProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<String> _categories = ["All"];
  List<Map<String, dynamic>> _sections = [];
  Map<String, Future<List<Movie>>> _sectionFutures = {};
  Future<List<Movie>>? _featuredFuture;

  bool _isLoadingConfig = true;
  String _selectedCategory = "All";

  List<String> get categories => _categories;
  List<Map<String, dynamic>> get sections => _sections;
  bool get isLoadingConfig => _isLoadingConfig;
  String get selectedCategory => _selectedCategory;
  Future<List<Movie>>? get featuredFuture => _featuredFuture;

  Future<List<Movie>> getSectionFuture(String title, String type, {String? genre, String? token}) {
    if (_sectionFutures.containsKey(title)) {
      return _sectionFutures[title]!;
    }

    Future<List<Movie>> future;
    switch (type) {
      case 'trending':
        future = _apiService.getTrendingMovies(token: token);
        break;
      case 'top_rated':
        future = _apiService.getTopRatedMovies(token: token);
        break;
      case 'new_releases':
        future = _apiService.getNowPlayingMovies(token: token);
        break;
      case 'genre':
        future = _apiService.getTrendingMovies(token: token, genre: genre);
        break;
      default:
        future = Future.value([]);
    }

    _sectionFutures[title] = future;
    return future;
  }

  void setSelectedCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  Future<void> loadConfig({String? token}) async {
    _isLoadingConfig = true;
    notifyListeners();

    try {
      _categories = await _apiService.getHeaderCategories();

      // Use new aggregation route for home data
      final homeData = await _apiService.getHomeData();
      _sections = [
        {'title': 'Trending Movies', 'type': 'trending_new'},
        {'title': 'Popular Movies', 'type': 'popular_new'},
        {'title': 'Top Rated', 'type': 'top_rated_new'},
        {'title': 'TV Shows', 'type': 'trending_tv_new'},
      ];

      _sectionFutures.clear();
      _sectionFutures['Trending Movies'] = Future.value(homeData['trendingMovies']);
      _sectionFutures['Popular Movies'] = Future.value(homeData['popularMovies']);
      _sectionFutures['Top Rated'] = Future.value(homeData['topRatedMovies']);
      _sectionFutures['TV Shows'] = Future.value(homeData['trendingTV']);

      _featuredFuture = Future.value(homeData['trendingMovies']?.take(5).toList());
    } catch (e) {
      debugPrint('Error loading home config: $e');
    } finally {
      _isLoadingConfig = false;
      notifyListeners();
    }
  }

  void refresh() {
    _sectionFutures.clear();
    _featuredFuture = null; // Will be recreated on next demand or loadConfig
    notifyListeners();
  }
}
