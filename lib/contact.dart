import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import "Add_contact.dart";


// This class handles distance calculations using OpenRouteService API
class DistanceService {
  // API key for OpenRouteService (free service for road distances)
  static const String apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjNiMTY4OGYzNTY5NjQxMDY4ZWZkMTM5MWU1ZmI2MjBkIiwiaCI6Im11cm11cjY0In0=';
  static const String baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';

  // This method calculates real road distance between two points
  static Future<Map<String, dynamic>?> getRoadDistance(
      double originLat,   // Starting point latitude
      double originLng,   // Starting point longitude
      double destLat,     // Destination latitude
      double destLng,     // Destination longitude
      ) async {
    try {
      // Prepare headers for the API request
      final headers = {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      };

      // Prepare the request body with coordinates
      // Note: OpenRouteService uses [longitude, latitude] format
      final body = json.encode({
        'coordinates': [
          [originLng, originLat],  // Start point
          [destLng, destLat]       // End point
        ]
      });

      // Send POST request to the API
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: body,
      );

      // Check if the request was successful
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if we got valid route data
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];      // Get the first route
          final summary = route['summary'];     // Get route summary

          final distanceMeters = summary['distance'];  // Distance in meters
          final distanceKm = distanceMeters / 1000;    // Convert to kilometers

          // Return the distance data
          return {
            'distanceMeters': distanceMeters,
            'distanceKm': distanceKm,
            'distanceText': '${distanceKm.toStringAsFixed(1)} km',
            'isRealRoadDistance': true,  // Flag to show this is real API data
          };
        }
      }
    } catch (e) {
      // If API fails, use fallback calculation
      // Silent fail - no error message to user
    }

    // Use fallback if API fails
    return _getFallbackDistance(originLat, originLng, destLat, destLng);
  }

  // Fallback method when API is not available
  // Calculates approximate road distance (1.3x straight line distance)
  static Map<String, dynamic> _getFallbackDistance(
      double originLat,
      double originLng,
      double destLat,
      double destLng,
      ) {
    // Calculate straight line distance using device's geolocator
    final straightDistance = Geolocator.distanceBetween(
        originLat, originLng, destLat, destLng
    );

    // Approximate road distance (typically 1.2x to 1.4x straight line)
    final roadDistance = straightDistance * 1.3;

    return {
      'distanceMeters': roadDistance,
      'distanceText': '${(roadDistance/1000).toStringAsFixed(1)} km',
      'isRealRoadDistance': false,  // Flag to show this is approximate data
    };
  }
}

// Main screen that shows emergency contacts
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => EmergencyContactScreenState();
}

class EmergencyContactScreenState extends State<EmergencyContactScreen> {
  // Store user's current GPS position
  Position? userPosition;

  // Get current user ID from Firebase Authentication
  final userId = FirebaseAuth.instance.currentUser!.uid;

  // Store calculated road distances for each contact
  Map<String, Map<String, dynamic>> roadDistances = {};

  // Track if distance calculation is in progress
  bool _isCalculating = false;

  // Store list of contacts
  List<Map<String, dynamic>> _contacts = [];

  // Track if app is still loading initial data
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Initialize the app when screen loads
    _initializeApp();
  }

  // Initialize app data
  Future<void> _initializeApp() async {
    await getUserLocation();  // Get user's current location
    setState(() => _isLoading = false);  // Mark loading as complete
  }

  // Get user's current location using device GPS
  Future<void> getUserLocation() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return; // Silently return if location is disabled
    }

    // Check location permission status
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission if not granted
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return; // Silently return if permission denied
      }
    }

    // Check if permission is permanently denied
    if (permission == LocationPermission.deniedForever) {
      return; // Silently return if permanently denied
    }

    try {
      // Get current position with high accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      // Update state with user's position
      setState(() => userPosition = position);
    } catch (e) {
      // Silent fail - no error message
    }
  }

  // Show snackbar (temporary message at bottom of screen)
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Calculate straight line distance between user and contact
  double _calculateStraightDistance(double lat, double lng) {
    if (userPosition == null) return double.infinity; // Return large number if no location
    return Geolocator.distanceBetween(
      userPosition!.latitude,  // User's latitude
      userPosition!.longitude, // User's longitude
      lat,  // Contact's latitude
      lng,  // Contact's longitude
    );
  }

  // Calculate road distance for a specific contact
  Future<void> _calculateRoadDistance(String contactId, double contactLat, double contactLng) async {
    // Don't calculate if: no user location, already calculating, or already calculated
    if (userPosition == null || _isCalculating || roadDistances.containsKey(contactId)) {
      return;
    }

    // Mark calculation as in progress
    setState(() => _isCalculating = true);

    try {
      // Get road distance from DistanceService
      final roadData = await DistanceService.getRoadDistance(
        userPosition!.latitude,   // User's lat
        userPosition!.longitude,  // User's lng
        contactLat,               // Contact's lat
        contactLng,               // Contact's lng
      );

      // If we got data and screen is still active, update state
      if (roadData != null && mounted) {
        setState(() {
          roadDistances[contactId] = roadData;  // Store distance for this contact
          _isCalculating = false;               // Mark calculation as complete
        });
      } else {
        setState(() => _isCalculating = false); // Mark calculation as complete even if failed
      }
    } catch (e) {
      setState(() => _isCalculating = false); // Mark calculation as complete on error
    }
  }

  // Refresh all distances (clear cache and recalculate)
  Future<void> _refreshAllDistances() async {
    setState(() {
      roadDistances.clear();  // Clear all stored distances
      _isCalculating = false; // Reset calculation state
    });
    await getUserLocation();  // Refresh user location
  }

  // Delete a contact with confirmation dialog
  Future<void> _deleteContact(String id, String name) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Contact"),
        content: Text("Are you sure you want to delete $name?"),
        actions: [
          // Cancel button
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          // Delete button (red color)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
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
      // Delete from Firebase Firestore
      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("contacts")
          .doc(id)
          .delete();

      // Update local state
      setState(() {
        roadDistances.remove(id);  // Remove from distances cache
      });

      _showSnackBar("Contact deleted");  // Show success message
    }
  }

  // Make phone call to contact
  Future<void> makePhoneCallDirect(String phoneNumber) async {
    // Request phone permission
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

  // Process Firestore documents into contact list
  List<Map<String, dynamic>> _processContacts(List<QueryDocumentSnapshot> docs) {
    // Convert Firestore documents to contact maps
    final contacts = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final contactLat = (data["latitude"] ?? 0).toDouble();
      final contactLng = (data["longitude"] ?? 0).toDouble();

      return {
        "id": doc.id,  // Firestore document ID
        "name": data["name"] ?? "Unknown",      // Contact name
        "phone": data["phone"] ?? "",           // Contact phone
        "latitude": contactLat,                 // Contact latitude
        "longitude": contactLng,                // Contact longitude
        "straightDistance": _calculateStraightDistance(contactLat, contactLng), // Straight line distance
        "roadDistance": roadDistances[doc.id],  // Road distance (if calculated)
      };
    }).toList();

    // Sort contacts by distance (closest first)
    contacts.sort((a, b) {
      // Use road distance if available, otherwise use straight line distance
      final aRoad = a["roadDistance"]?['distanceMeters'] ?? a["straightDistance"];
      final bRoad = b["roadDistance"]?['distanceMeters'] ?? b["straightDistance"];
      return aRoad.compareTo(bRoad);  // Sort in ascending order
    });

    return contacts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],  // Light grey background
      appBar: AppBar(
        title: const Text(
          "Emergency Contacts",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.blue[700],  // Dark blue app bar
        foregroundColor: Colors.white,      // White text
        elevation: 0,                       // Remove shadow
        actions: [
          // Refresh button in app bar
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _refreshAllDistances,
            tooltip: "Refresh distances",
          ),
        ],
      ),
      // Main content area
      body: _isLoading
          ? _buildLoadingState()  // Show loading spinner
          : StreamBuilder<QuerySnapshot>(
        // Real-time stream from Firestore
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("contacts")
            .snapshots(),
        builder: (context, snapshot) {
          // Handle errors
          if (snapshot.hasError) {
            return _buildErrorState("Failed to load contacts");
          }

          // Show loading if no data yet
          if (!snapshot.hasData) {
            return _buildLoadingState();
          }

          // Process contacts from Firestore data
          final contacts = _processContacts(snapshot.data!.docs);

          // Show empty state if no contacts
          if (contacts.isEmpty) {
            return _buildEmptyState();
          }

          // Show contacts list
          return _buildContactsList(contacts);
        },
      ),
      // Floating action button to add new contact
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to Add Contact screen
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddContactScreen()),
          );
        },
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  // Widget for error state
  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Widget for loading state
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular progress indicator
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
          ),
          const SizedBox(height: 16),
          const Text(
            "Loading contacts...",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Widget for empty state (no contacts)
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            "No Emergency Contacts",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            "Add your first contact for quick access",
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // Build the main contacts list
  Widget _buildContactsList(List<Map<String, dynamic>> contacts) {
    return Column(
      children: [
        buildLocationStatus(),  // Location status bar
        Expanded(
          // List of contacts
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return buildContactCard(contact);  // Build each contact card
            },
          ),
        ),
      ],
    );
  }

  // Location status bar at top of contacts list
  Widget buildLocationStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],  // Light blue background
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Location icon (green if active, orange if not)
          Icon(
            userPosition != null ? Icons.location_on : Icons.location_off,
            color: userPosition != null ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            // Status text
            child: Text(
              userPosition != null
                  ? "Location active • Road distances calculated"
                  : "Enable location for accurate distances",
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Show loading spinner if calculating distances
          if (_isCalculating) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build individual contact card
  Widget buildContactCard(Map<String, dynamic> contact) {
    final roadData = contact["roadDistance"];
    final straightDistanceKm = (contact["straightDistance"] / 1000).toStringAsFixed(1);

    // Calculate road distance after build is complete (if needed)
    if (roadData == null && userPosition != null && !_isCalculating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateRoadDistance(
          contact["id"],
          contact["latitude"],
          contact["longitude"],
        );
      });
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // Contact avatar
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue[100],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person,
            color: Colors.blue[700],
            size: 24,
          ),
        ),
        // Contact name
        title: Text(
          contact["name"],
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        // Contact details
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Phone number
              Text(
                contact["phone"],
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              // Distance information
              buildDistanceInfo(roadData, straightDistanceKm),
            ],
          ),
        ),
        // Action buttons (call and delete)
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Call button
            IconButton(
              icon: Icon(Icons.call, color: Colors.green[700], size: 20),
              onPressed: () => makePhoneCallDirect(contact["phone"]),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
            // Delete button
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 20),
              onPressed: () => _deleteContact(contact["id"], contact["name"]),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build distance information widget
  Widget buildDistanceInfo(Map<String, dynamic>? roadData, String straightDistanceKm) {
    // If we have road distance data
    if (roadData != null) {
      return Row(
        children: [
          // Car icon (green for real data, orange for approximate)
          Icon(
            Icons.directions_car,
            size: 16,
            color: roadData['isRealRoadDistance'] == true ? Colors.green[600] : Colors.orange[600],
          ),
          const SizedBox(width: 6),
          // Distance text
          Text(
            roadData['distanceText'],
            style: TextStyle(
              fontSize: 13,
              color: roadData['isRealRoadDistance'] == true ? Colors.green[700] : Colors.orange[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    // If calculating road distance
    else if (userPosition != null) {
      return Row(
        children: [
          // Loading spinner
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
            ),
          ),
          const SizedBox(width: 6),
          // Calculating text
          Text(
            "Calculating",
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[700],
            ),
          ),
        ],
      );
    }
    // If no location available, show straight line distance
    else {
      return Text(
        "Straight line: $straightDistanceKm km",
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      );
    }
  }
}








