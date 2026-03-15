import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riyo/core/design_system.dart';
import 'package:riyo/models/movie.dart';
import 'package:riyo/services/api_service.dart';
import 'package:riyo/providers/auth_provider.dart';
import 'package:riyo/providers/settings_provider.dart';
import 'package:riyo/presentation/widgets/movie_card.dart';
import 'package:riyo/presentation/widgets/shimmer_loading.dart';
import 'package:riyo/presentation/widgets/state_widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  List<Movie> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, bool isOffline, {String? token}) async {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      _performSearch(query, isOffline, token: token);
    });
  }

  Future<void> _performSearch(String query, bool isOffline,
      {String? token}) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isLoading = false;
          _hasSearched = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasSearched = true;
      });
    }

    try {
      List<Movie> filteredMovies;
      if (isOffline) {
        final movies = await _apiService.getTrendingMovies(token: token);
        filteredMovies = movies
            .where((movie) =>
                movie.title.toLowerCase().contains(query.toLowerCase()) &&
                movie.isDownloaded)
            .toList();
      } else {
        filteredMovies = await _apiService.search(query);
      }

      if (mounted) {
        setState(() {
          _searchResults = filteredMovies;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(settings.isOffline, token: auth.token),
            Expanded(
              child: _isLoading
                ? _buildLoadingGrid()
                : (_hasSearched ? _buildSearchResults() : _buildInitialContent()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(bool isOffline, {String? token}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => _onSearchChanged(val, isOffline, token: token),
        style: AppTypography.bodyLarge,
        decoration: InputDecoration(
          hintText: isOffline ? 'Search downloads...' : 'Search movies, TV shows...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('', isOffline, token: token);
                },
              )
            : null,
        ),
      ),
    );
  }

  Widget _buildInitialContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      children: [
        Text(
          'Top Searches',
          style: AppTypography.titleLarge,
        ),
        const SizedBox(height: 16.0),
        _buildTrendingSearch('Inception'),
        _buildTrendingSearch('Interstellar'),
        _buildTrendingSearch('The Dark Knight'),
        _buildTrendingSearch('Pulp Fiction'),
        const SizedBox(height: 32.0),
        Text(
          'Categories',
          style: AppTypography.titleLarge,
        ),
        const SizedBox(height: 16.0),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12.0,
          crossAxisSpacing: 12.0,
          childAspectRatio: 2.5,
          children: [
            _buildCategoryChip('Action'),
            _buildCategoryChip('Comedy'),
            _buildCategoryChip('Drama'),
            _buildCategoryChip('Horror'),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return NoSearchResultsState(
        query: _searchController.text,
        onBack: () {
          _searchController.clear();
          _onSearchChanged('', false);
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return MovieCard(movie: _searchResults[index]);
      },
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const ShimmerLoading.rectangular(height: 150),
    );
  }

  Widget _buildTrendingSearch(String title) {
    return ListTile(
      leading: Icon(Icons.trending_up_rounded, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: AppTypography.bodyLarge),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () {
        _searchController.text = title;
        _performSearch(title, false);
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCategoryChip(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
        color: isDark ? AppColors.amoledSurface : Colors.white,
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.labelLarge,
        ),
      ),
    );
  }
}
