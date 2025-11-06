// Import necessary packages
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Service class to calculate road distances between locations
class DistanceService {
  // API key for OpenRouteService (road distance calculation)
  static const String apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjNiMTY4OGYzNTY5NjQxMDY4ZWZkMTM5MWU1ZmI2MjBkIiwiaCI6Im11cm11cjY0In0=';
  static const String baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';

  // Function to get real road distance between two points
  static Future<Map<String, dynamic>?> getRoadDistance(
      double originLat,   // User's latitude
      double originLng,   // User's longitude
      double destLat,     // Donor's latitude
      double destLng,     // Donor's longitude
      ) async {
    try {
      // Prepare API request headers
      final headers = {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      };

      // Prepare coordinates for the API
      final body = json.encode({
        'coordinates': [
          [originLng, originLat], // Start point (user)
          [destLng, destLat]      // End point (donor)
        ]
      });

      // Send request to distance API
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
            'isRealRoadDistance': true, // Real road distance from API
          };
        }
      }
    } catch (e) {
      // If API fails, we'll use fallback method
    }

    // Use fallback if API fails
    return getFallbackDistance(originLat, originLng, destLat, destLng);
  }

  // Fallback method: calculates straight line distance when API is unavailable
  static Map<String, dynamic> getFallbackDistance(
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
      'isRealRoadDistance': false, // Estimated distance (not from API)
    };
  }
}

// Main screen for searching blood donors
class SearchBloodScreen extends StatefulWidget {
  const SearchBloodScreen({super.key});

  @override
  State<SearchBloodScreen> createState() => _SearchBloodScreenState();
}

class _SearchBloodScreenState extends State<SearchBloodScreen> {
  // Firebase database connection
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Variables to store data
  List<Map<String, dynamic>> allDonors = [];      // All donors from database
  List<Map<String, dynamic>> filteredDonors = []; // Donors after filtering
  bool isLoading = true;                          // Show loading indicator
  bool isCalculating = false;                     // Show distance calculation progress
  String errorMessage = '';                       // Store error messages
  String searchQuery = '';                        // Store search text
  String? selectedBloodGroup;                     // Selected blood group filter
  Position? userPosition;                         // User's current location

  // Available blood groups for filtering
  final List<String> bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];

  @override
  void initState() {
    super.initState();
    // Start the app when screen loads
    initializeApp();
  }

  // Initialize the app by getting location and loading donors
  Future<void> initializeApp() async {
    await getUserLocation();  // Get user's current location
    await loadAllDonors();    // Load donors from database
  }

  // Get user's current location using device GPS
  Future<void> getUserLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          errorMessage = 'Please enable location services';
        });
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Request permission if not granted
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            errorMessage = 'Location permission denied';
          });
          return;
        }
      }

      // Check if permission is permanently denied
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          errorMessage = 'Location permission permanently denied';
        });
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best, // High accuracy
      );

      setState(() {
        userPosition = position; // Store user position
      });

    } catch (e) {
      setState(() {
        errorMessage = 'Error getting location';
      });
    }
  }

  // Load all blood donors from Firebase database
  Future<void> loadAllDonors() async {
    try {
      // Get data from Firebase collection
      QuerySnapshot querySnapshot = await firestore
          .collection("public_blood_donors")  // Collection name
          .where("isAvailable", isEqualTo: true) // Only show available donors
          .get();

      // Convert Firebase data to a list
      List<Map<String, dynamic>> donors = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          "id": doc.id,                    // Document ID
          "name": data["name"] ?? "Unknown",
          "age": data["age"] ?? 0,
          "bloodGroup": data["bloodGroup"] ?? "",
          "phone": data["phone"] ?? "Not provided",
          "email": data["email"] ?? "",
          "address": data["address"] ?? "",
          "latitude": (data["latitude"] ?? 0).toDouble(),
          "longitude": (data["longitude"] ?? 0).toDouble(),
          "distance": double.infinity,     // Start with large distance
          "distanceText": "Calculating...",
          "isRealRoadDistance": false,     // Not calculated yet
        };
      }).toList();

      // Update state with loaded donors
      setState(() {
        allDonors = donors;
        filteredDonors = donors;
        isLoading = false; // Hide loading indicator
      });

      // Calculate distances for all donors
      calculateAllRoadDistances(donors);

    } catch (e) {
      setState(() {
        errorMessage = 'Error loading blood donors';
        isLoading = false;
      });
    }
  }

  // Calculate road distances for all donors
  Future<void> calculateAllRoadDistances(List<Map<String, dynamic>> donors) async {
    if (userPosition == null) return; // Need user location first

    setState(() => isCalculating = true); // Show calculating indicator

    // Calculate distances one by one
    for (int i = 0; i < donors.length; i++) {
      final donor = donors[i];
      await calculateSingleRoadDistance(donor);

      // Small delay to avoid overwhelming the API
      if (i < donors.length - 1) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    setState(() => isCalculating = false); // Hide calculating indicator
  }

  // Calculate distance for a single donor
  Future<void> calculateSingleRoadDistance(Map<String, dynamic> donor) async {
    try {
      // Get road distance using DistanceService
      final roadData = await DistanceService.getRoadDistance(
        userPosition!.latitude,   // User's latitude
        userPosition!.longitude,  // User's longitude
        donor["latitude"],        // Donor's latitude
        donor["longitude"],       // Donor's longitude
      );

      if (roadData != null && mounted) {
        setState(() {
          // Update each donor's distance information
          final updatedDonors = allDonors.map((d) {
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

          allDonors = updatedDonors;
          filteredDonors = applyFilters(updatedDonors);
        });
      }
    } catch (e) {
      // Error handled silently (fallback distance will be used)
    }
  }

  // Filter donors based on search and blood group
  List<Map<String, dynamic>> applyFilters(List<Map<String, dynamic>> donors) {
    return donors.where((donor) {
      final String address = donor["address"].toString().toLowerCase();
      final String bloodGroup = donor["bloodGroup"].toString();

      // Check if donor matches search text in address
      bool matchesSearch = address.contains(searchQuery.toLowerCase());

      // Check if donor matches selected blood group
      bool matchesBloodGroup = selectedBloodGroup == null || bloodGroup == selectedBloodGroup;

      // Return donors that match both conditions
      return matchesSearch && matchesBloodGroup;
    }).toList();
  }

  // Search donors (called automatically when user types)
  void searchDonors() {
    setState(() {
      filteredDonors = applyFilters(allDonors);
    });
  }

  // Make phone call to donor
  Future<void> makePhoneCall(String phoneNumber) async {
    // Request phone permission
    var status = await Permission.phone.request();

    if (status.isGranted) {
      // Create phone call URL and launch dialer
      final Uri launchUri = Uri.parse("tel:$phoneNumber");
      await launchUrl(launchUri, mode: LaunchMode.platformDefault);
    } else {
      showSnackBar("Phone permission denied");
    }
  }

  // Send email to donor
  Future<void> sendEmail(String email) async {
    final Uri launchUri = Uri.parse("mailto:$email");
    await launchUrl(launchUri);
  }

  // Refresh data (pull to refresh)
  void refreshData() {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    initializeApp();
  }

  // Show temporary message at bottom
  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Search Blood Donors"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          buildSearchFilterSection(),  // Search and filter UI
          if (errorMessage.isNotEmpty) buildErrorMessage(), // Error message
          if (isLoading) buildLoadingIndicator() // Loading indicator
          else if (filteredDonors.isEmpty) buildEmptyState() // Empty state
          else buildDonorsList(), // Donors list
        ],
      ),
    );
  }



  // Build error message widget
  Widget buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(color: Colors.orange[700]),
            ),
          ),
        ],
      ),
    );
  }

  // Build loading indicator
  Widget buildLoadingIndicator() {
    return const Expanded(
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
    );
  }

  // Build empty state when no donors found
  Widget buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bloodtype_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty || selectedBloodGroup != null
                  ? 'No matching blood donors found'
                  : 'No blood donors available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try changing your search criteria',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build donors list
  Widget buildDonorsList() {
    return Expanded(
      child: Column(
        children: [
          // Show calculating distances indicator
          if (isCalculating)
            Container(
              padding: const EdgeInsets.all(8),
              //color: Colors.blue[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                 // const SizedBox(width: 8),
                  Text(
                    "Calculating road distances...",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
          // Donors list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredDonors.length,
              itemBuilder: (context, index) {
                final donor = filteredDonors[index];
                return buildDonorCard(donor);
              },
            ),
          ),
        ],
      ),
    );
  }

  // Build search and filter section
  Widget buildSearchFilterSection() {
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
          // Search TextField - searches automatically as user types
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by location/area...',
              prefixIcon: const Icon(Icons.location_on, color: Colors.red),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value; // Update search text
              });
              searchDonors(); // Auto-search as user types
            },
          ),
          const SizedBox(height: 12),

          // Blood Group Filter Chips
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: bloodGroups.length + 1,
              itemBuilder: (context, index) {
                // "All Blood Groups" chip
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All Blood Groups'),
                      selected: selectedBloodGroup == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedBloodGroup = null; // Clear filter
                        });
                        searchDonors(); // Auto-search
                      },
                      backgroundColor: Colors.grey[300],
                      selectedColor: Colors.red,
                      labelStyle: TextStyle(
                        color: selectedBloodGroup == null ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }

                // Blood group chips
                final bloodGroup = bloodGroups[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(bloodGroup),
                    selected: selectedBloodGroup == bloodGroup,
                    onSelected: (selected) {
                      setState(() {
                        selectedBloodGroup = selected ? bloodGroup : null;
                      });
                      searchDonors(); // Auto-search
                    },
                    backgroundColor: Colors.grey[300],
                    selectedColor: Colors.red,
                    labelStyle: TextStyle(
                      color: selectedBloodGroup == bloodGroup ? Colors.white : Colors.black,
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
  Widget buildDonorCard(Map<String, dynamic> donor) {
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
            // Header with Blood Group and Distance
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
                // Distance information
                buildDistanceInfo(distanceText, isRealRoadDistance),
              ],
            ),

            const SizedBox(height: 12),

            // Donor name and age
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  '${donor["name"]}, ${donor["age"]} years',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Donor location
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
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Contact buttons
            Row(
              children: [
                // Call button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => makePhoneCall(donor["phone"]),
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Email button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => sendEmail(donor["email"]),
                    icon: const Icon(Icons.email, size: 16),
                    label: const Text('Email'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Build distance information widget
  Widget buildDistanceInfo(String distanceText, bool isRealRoadDistance) {
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