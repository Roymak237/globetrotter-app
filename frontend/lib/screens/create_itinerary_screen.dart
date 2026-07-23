import "package:flutter/material.dart";
import "../providers/auth_provider.dart";
import "../services/api_service.dart";
import "package:provider/provider.dart";

class CreateItineraryScreen extends StatefulWidget {
  const CreateItineraryScreen({super.key});

  @override
  State<CreateItineraryScreen> createState() => _CreateItineraryScreenState();
}

class _CreateItineraryScreenState extends State<CreateItineraryScreen> {
  final _titleController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _notesController = TextEditingController();
  final List<String> _selectedDestinations = [];
  List<String> _allDestinations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
  }

  Future<void> _loadDestinations() async {
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final results = await api.searchDestinations();
      if (mounted) {
        setState(() {
          _allDestinations = results.map((d) => d.name).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveItinerary() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _selectedDestinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Title and at least one destination required")),
      );
      return;
    }
    try {
      await context.read<AuthProvider>().createItinerary(
            title: title,
            destinations: _selectedDestinations,
            startDate: _startDateController.text.trim(),
            endDate: _endDateController.text.trim(),
            notes: _notesController.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Itinerary")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: "Title"),
                  ),
                  TextField(
                    controller: _startDateController,
                    decoration: const InputDecoration(labelText: "Start Date (YYYY-MM-DD)"),
                  ),
                  TextField(
                    controller: _endDateController,
                    decoration: const InputDecoration(labelText: "End Date (YYYY-MM-DD)"),
                  ),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(labelText: "Notes"),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  const Text("Destinations", style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: _allDestinations.map((name) {
                      final selected = _selectedDestinations.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedDestinations.add(name);
                            } else {
                              _selectedDestinations.remove(name);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveItinerary,
                    child: const Text("Save Itinerary"),
                  ),
                ],
              ),
            ),
    );
  }
}
