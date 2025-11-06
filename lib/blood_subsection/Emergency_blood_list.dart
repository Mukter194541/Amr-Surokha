// Import necessary packages
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'add_emergency_blood.dart';

// Distance Service Class - Handles calculating distances between locations
class DistanceService {
  static const String apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjNiMTY4OGYzNTY5NjQxMDY4ZWZkMTM5MWU1ZmI2MjBkIiwiaCI6Im11cm11cjY0In0=';
  static const String baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';

  // This function calculates real road distance between two points using an API
  static Future<Map<String, dynamic>?> getRoadDistance(
      double originLat,
      double originLng,
      double destLat,
      double destLng,
      ) async {
    try {
      // Prepare headers for the API request
      final headers = {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      };

      // Prepare the request body with coordinates
      final body = json.encode({
        'coordinates': [
          [originLng, originLat], // Starting point
          [destLng, destLat]      // Destination point
        ]
      });

      // Send POST request to the distance API
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: body,
      );

      // If API call is successful
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if we got route data
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final summary = route['summary'];

          // Extract distance in meters and convert to kilometers
          final distanceMeters = summary['distance'];
          final distanceKm = distanceMeters / 1000;

          // Return distance information
          return {
            'distanceMeters': distanceMeters,
            'distanceKm': distanceKm,
            'distanceText': '${distanceKm.toStringAsFixed(1)} km',
            'isRealRoadDistance': true, // Mark as real road distance
          };
        }
      }
    } catch (e) {
      print('Road distance API error');
    }

    // If API fails, use fallback distance calculation
    return _getFallbackDistance(originLat, originLng, destLat, destLng);
  }

  // Fallback method when API is not available - calculates straight line distance
  static Map<String, dynamic> _getFallbackDistance(
      double originLat,
      double originLng,
      double destLat,
      double destLng,
      ) {
    // Calculate straight line distance between two points
    final straightDistance = Geolocator.distanceBetween(
        originLat, originLng, destLat, destLng
    );

    // Multiply by 1.3 to approximate road distance (roads are not straight)
    final roadDistance = straightDistance * 1.3;

    return {
      'distanceMeters': roadDistance,
      'distanceText': '${(roadDistance/1000).toStringAsFixed(1)} km',
      'isRealRoadDistance': false, // Mark as estimated distance
    };
  }
}

// Main Screen Widget - Displays list of blood donors
class EmergencyBloodListScreen extends StatefulWidget {
  const EmergencyBloodListScreen({super.key});

  @override
  State<EmergencyBloodListScreen> createState() => _EmergencyBloodListScreenState();
}

class _EmergencyBloodListScreenState extends State<EmergencyBloodListScreen> {
  // Firebase services setup
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final userId = FirebaseAuth.instance.currentUser!.uid;

  // State variables to manage app data
  Position? userPosition;           // Stores user's current location
  bool _isLoading = true;           // Shows loading indicator when true
  List<Map<String, dynamic>> _bloodDonors = []; // List to store donor data
  String _errorMessage = '';        // Stores error messages
  String _searchQuery = '';         // Stores search text
  String? _selectedBloodGroup;      // Stores selected blood group filter
  Map<String, Map<String, dynamic>> roadDistances = {}; // Stores calculated distances
  bool _isCalculating = false;      // Shows distance calculation progress

  // Available blood groups for filtering
  final List<String> _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp(); // Start the app when screen loads
  }

  // Initialize app by getting location and loading donors
  Future<void> _initializeApp() async {
    await getUserLocation();  // Get user's current location
    await _loadBloodDonors(); // Load donors from Firebase
  }

  // Get user's current location using device GPS
  Future<void> getUserLocation() async {
    try {
      // Check if location services are enabled on device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services disabled');
        return;
      }

      // Check if app has location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Request permission if not granted
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permission denied');
          return;
        }
      }

      // Check if permission is permanently denied
      if (permission == LocationPermission.deniedForever) {
        print('Location permission permanently denied');
        return;
      }

      // Get current position coordinates
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best, // High accuracy
      );

      // Update state with user position
      setState(() {
        userPosition = position;
      });
      print('Location obtained: ${position.latitude}, ${position.longitude}');

    } catch (e) {
      print('Location error');
    }
  }

  // Load blood donors from Firebase Firestore
  Future<void> _loadBloodDonors() async {
    try {
      // Get documents from Firebase collection
      QuerySnapshot querySnapshot = await _firestore
          .collection("Add_emergency_blood")
          .doc(userId)
          .collection("emergency_blood_donors")
          .get();

      // Convert Firebase documents to a list of maps
      List<Map<String, dynamic>> donors = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          "id": doc.id,                    // Document ID
          "donorName": data["donorName"] ?? "Unknown",
          "age": data["age"] ?? 0,
          "bloodGroup": data["bloodGroup"] ?? "",
          "phone": data["phone"] ?? "Not provided",
          "address": data["address"] ?? "",
          "latitude": (data["latitude"] ?? 0).toDouble(),
          "longitude": (data["longitude"] ?? 0).toDouble(),
          "timestamp": data["timestamp"],
          "distance": double.infinity, // Start with large distance
        };
      }).toList();

      // Update state with loaded donors
      setState(() {
        _bloodDonors = donors;
        _isLoading = false; // Hide loading indicator
      });

      // Calculate distances for all loaded donors
      _calculateAllRoadDistances(donors);

    } catch (e) {
      print('Load donors error');
      setState(() {
        _errorMessage = 'Error loading blood donors';
        _isLoading = false;
      });
    }
  }

  // Calculate road distances for all donors
  Future<void> _calculateAllRoadDistances(List<Map<String, dynamic>> donors) async {
    if (userPosition == null) {
      print('No user position available for distance calculation');
      return;
    }

    setState(() => _isCalculating = true); // Show calculating indicator

    // Calculate distances for each donor one by one
    for (int i = 0; i < donors.length; i++) {
      final donor = donors[i];
      await _calculateSingleRoadDistance(donor);

      // Small delay to avoid hitting API rate limits
      if (i < donors.length - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    setState(() => _isCalculating = false); // Hide calculating indicator
  }

  // Calculate distance for a single donor
  Future<void> _calculateSingleRoadDistance(Map<String, dynamic> donor) async {
    try {
      // Get road distance using DistanceService
      final roadData = await DistanceService.getRoadDistance(
        userPosition!.latitude,   // User's latitude
        userPosition!.longitude,  // User's longitude
        donor["latitude"],        // Donor's latitude
        donor["longitude"],       // Donor's longitude
      );

      // If we got distance data and screen is still active
      if (roadData != null && mounted) {
        setState(() {
          // Update each donor's distance information
          final updatedDonors = _bloodDonors.map((d) {
            if (d["id"] == donor["id"]) {
              return {
                ...d, // Keep existing donor data
                "distance": roadData['distanceMeters'],
                "distanceText": roadData['distanceText'],
                "isRealRoadDistance": roadData['isRealRoadDistance'],
              };
            }
            return d;
          }).toList();

          // Sort donors by distance (nearest first)
          updatedDonors.sort((a, b) => (a["distance"] ?? double.infinity).compareTo(b["distance"] ?? double.infinity));

          _bloodDonors = updatedDonors;
        });
      }
    } catch (e) {
      print('Distance calculation error for donor ${donor["id"]}: $e');
    }
  }

  // Refresh all distances and reload data
  Future<void> _refreshAllDistances() async {
    setState(() {
      roadDistances.clear(); // Clear existing distances
      _isCalculating = false;
    });
    await getUserLocation();    // Get fresh location
    await _loadBloodDonors();   // Reload donors
  }

  // Make phone call to donor
  Future<void> _makePhoneCall(String phoneNumber) async {
    // Request phone call permission
    var status = await Permission.phone.request();

    if (status.isGranted) {
      // Create phone call URL
      final Uri launchUri = Uri.parse("tel:$phoneNumber");
      // Launch phone dialer
      await launchUrl(launchUri, mode: LaunchMode.platformDefault);
    } else {
      _showSnackBar("Phone permission denied");  // Show error if permission denied
    }
  }

  // Delete a donor from Firebase
  Future<void> _deleteDonor(String docId, String donorName) async {
    // Show confirmation dialog before deleting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Blood Donor"),
        content: Text("Are you sure you want to delete $donorName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Confirm delete
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    // If user confirmed deletion
    if (confirm == true) {
      try {
        // Delete from Firebase
        await _firestore
            .collection("Add_emergency_blood")
            .doc(userId)
            .collection("emergency_blood_donors")
            .doc(docId)
            .delete();

        // Remove from local list
        setState(() {
          _bloodDonors.removeWhere((donor) => donor["id"] == docId);
        });

        _showSnackBar("Blood donor deleted successfully");
      } catch (e) {
        _showSnackBar("Error deleting donor");
      }
    }
  }

  // Show temporary message at bottom of screen
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Filter donors based on search query and blood group selection
  List<Map<String, dynamic>> get _filteredDonors {
    return _bloodDonors.where((donor) {
      final String donorName = donor["donorName"].toString().toLowerCase();
      final String bloodGroup = donor["bloodGroup"].toString();
      final String address = donor["address"].toString().toLowerCase();

      // Check if donor matches search text in name or address
      bool matchesSearch = donorName.contains(_searchQuery.toLowerCase()) ||
          address.contains(_searchQuery.toLowerCase());

      // Check if donor matches selected blood group
      bool matchesBloodGroup = _selectedBloodGroup == null ||
          bloodGroup == _selectedBloodGroup;

      // Return true if both conditions match
      return matchesSearch && matchesBloodGroup;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("My Blood Donors"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllDistances,
            tooltip: 'Refresh distances',
          ),
        ],
      ),
      body: Column(
        children: [
          // Location Status
          _buildLocationStatus(),

          // Search and Filter Section
          _buildSearchFilterSection(),

          // Error Message
          if (_errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.orange),
              ),
            ),

          // Loading Indicator
          if (_isLoading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(), // Spinning loader
                    SizedBox(height: 16),
                    Text("Loading blood donors..."),
                  ],
                ),
              ),
            )
          // Empty State - when no donors found
          else if (_filteredDonors.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bloodtype,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty || _selectedBloodGroup != null
                          ? 'No matching blood donors found'
                          : 'No blood donors added yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          // Blood Donors List
          else
            Expanded(
              child: Column(
                children: [
                  // Show calculating distances indicator
                  if (_isCalculating)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue[50],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Calculating distances...",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Donors list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredDonors.length,
                      itemBuilder: (context, index) {
                        final donor = _filteredDonors[index];
                        return _buildDonorCard(donor);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      // Add new donor button
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to add donor screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEmergencyBloodScreen(),
            ),
          ).then((_) => _refreshAllDistances()); // Refresh when returning
        },
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  // Build location status widget
  Widget _buildLocationStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: userPosition != null ? Colors.green[50] : Colors.orange[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Icon(
            userPosition != null ? Icons.location_on : Icons.location_off,
            color: userPosition != null ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              userPosition != null
                  ? "Location active "
                  : "Please Enable location service",
              style: TextStyle(
                fontSize: 13,
                color: userPosition != null ? Colors.green[700] : Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),



            ),
          ),
        ],
      ),
    );
  }

  // Build search and filter section
  Widget _buildSearchFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        children: [
          // Search text field
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by name or location...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value; // Update search query
              });
            },
          ),
          const SizedBox(height: 12),

          // Blood group filter chips
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bloodGroups.length + 1,
              itemBuilder: (context, index) {
                // "All" chip
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _selectedBloodGroup == null,
                      onSelected: (selected) {
                        setState(() {
                          _selectedBloodGroup = null; // Clear filter
                        });
                      },
                      backgroundColor: Colors.grey[300],
                      selectedColor: Colors.blue,
                      labelStyle: TextStyle(
                        color: _selectedBloodGroup == null ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }

                // Blood group chips
                final bloodGroup = _bloodGroups[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(bloodGroup),
                    selected: _selectedBloodGroup == bloodGroup,
                    onSelected: (selected) {
                      setState(() {
                        _selectedBloodGroup = selected ? bloodGroup : null;
                      });
                    },
                    backgroundColor: Colors.grey[300],
                    selectedColor: Colors.red,
                    labelStyle: TextStyle(
                      color: _selectedBloodGroup == bloodGroup ? Colors.white : Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Build individual donor card
  Widget _buildDonorCard(Map<String, dynamic> donor) {
    final distanceText = donor["distanceText"] ?? "Calculating...";
    final isRealRoadDistance = donor["isRealRoadDistance"] ?? false;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with blood group and delete button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Blood group badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bloodtype,
                        size: 16,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        donor["bloodGroup"],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _deleteDonor(donor["id"], donor["donorName"]),
                  tooltip: 'Delete Donor',
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Donor Information - Name and Age
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  '${donor["donorName"]}, ${donor["age"]} years',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Location information
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    donor["address"],
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis, // Show ... if text is too long
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Phone number and Distance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Phone number
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          donor["phone"],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Distance information
                _buildDistanceInfo(distanceText, isRealRoadDistance),
              ],
            ),

            const SizedBox(height: 12),

            // Call Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _makePhoneCall(donor["phone"]),
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Call Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build distance information widget
  Widget _buildDistanceInfo(String distanceText, bool isRealRoadDistance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRealRoadDistance ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isRealRoadDistance ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_car,
            size: 14,
            color: isRealRoadDistance ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(
            distanceText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isRealRoadDistance ? Colors.green[700] : Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }
}