import "package:flutter/material.dart";
import "../models/destination.dart";
import "../services/api_service.dart";
import "../widgets/destination_card.dart";
import "../providers/auth_provider.dart";
import "package:provider/provider.dart";

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _api = ApiService();
  List<Destination> _recommendations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loading = true);
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please login to see recommendations")),
          );
        }
        return;
      }
      final results = await _api.fetchRecommendations(token: token);
      if (mounted) {
        setState(() {
          _recommendations = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _loading
          ? const CircularProgressIndicator()
          : _recommendations.isEmpty
              ? const Text("No recommendations yet. Update your preferences!")
              : ListView.builder(
                  itemCount: _recommendations.length,
                  itemBuilder: (context, index) {
                    final rec = _recommendations[index];
                    return DestinationCard(destination: rec);
                  },
                ),
    );
  }
}
