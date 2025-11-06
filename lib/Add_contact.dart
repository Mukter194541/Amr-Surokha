import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

// Screen for adding new contacts with full screen map
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => AddContactScreenState();
}

class AddContactScreenState extends State<AddContactScreen> {
  // Text controllers for form fields
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final searchController = TextEditingController();

  // Current user ID
  final userId = FirebaseAuth.instance.currentUser!.uid;

  // Map variables
  GoogleMapController? mapController;
  LatLng? selectedLocation;
  String selectedAddress = "";
  bool _isSearching = false;
  bool _isLoadingLocation = false;
  bool _showFullScreenMap = false;

  // Default camera position
  static const LatLng _defaultLocation = LatLng(23.8103, 90.4125); // Dhaka, Bangladesh

  // Color scheme
  final Color primaryColor = Colors.blue; // Orange
  final Color backgroundColor = Colors.white;
  final Color cardColor = Colors.grey[50]!;
  final Color textColor = Colors.grey[800]!;

  // Save contact to Firestore
  Future<void> _saveContact() async {
    if (nameController.text.isEmpty || phoneController.text.isEmpty) {
      showSnackBar("Please fill name and phone number");
      return;
    }

    if (selectedLocation == null) {
      showSnackBar("Please select a location on the map");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("contacts")
          .add({
        "name": nameController.text,
        "phone": phoneController.text,
        "latitude": selectedLocation!.latitude,
        "longitude": selectedLocation!.longitude,
        "address": selectedAddress.isEmpty ? "Selected Location" : selectedAddress,
      });

      Navigator.pop(context);
    } catch (e) {
      showSnackBar("Error saving contact");
    }
  }

  // Search for a location and open full screen map
  Future<void> _searchAndOpenMap(String query) async {
    if (query.isEmpty) {
      showSnackBar("Please enter a location to search");
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      List<Location> locations = await locationFromAddress(query);

      if (locations.isNotEmpty) {
        final location = locations.first;
        final latLng = LatLng(location.latitude, location.longitude);

        List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude
        );

        String address = query;
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          address = "${placemark.street ?? ''} ${placemark.subLocality ?? ''}, ${placemark.locality ?? ''}";
        }

        setState(() {
          selectedLocation = latLng;
          selectedAddress = address;
          _showFullScreenMap = true;
        });

        Future.delayed(const Duration(milliseconds: 500), () {
          mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(latLng, 15.0),
          );
        });

      } else {
        showSnackBar("Location '$query' not found");
      }
    } catch (e) {
      showSnackBar("Error searching location");
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  // Get address from coordinates when user taps on map
  Future<void> _onMapTap(LatLng latLng) async {
    setState(() {
      _isLoadingLocation = true;
      selectedLocation = latLng;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          latLng.latitude,
          latLng.longitude
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = "${placemark.street ?? ''} ${placemark.subLocality ?? ''}, ${placemark.locality ?? ''}";

        setState(() {
          selectedAddress = address.isNotEmpty ? address : "Selected Location";
        });
      }
    } catch (e) {
      setState(() {
        selectedAddress = "Selected Location";
      });
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // Close full screen map and return to form
  void _closeFullScreenMap() {
    setState(() {
      _showFullScreenMap = false;
    });
  }

  // Show snackbar message
  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Full Screen Map View
    if (_showFullScreenMap) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            "Select Location",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (selectedLocation != null)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _closeFullScreenMap,
                tooltip: "Confirm Location",
              ),
          ],
        ),
        body: Stack(
          children: [
            GoogleMap(
              onMapCreated: (controller) {
                mapController = controller;
              },
              initialCameraPosition: CameraPosition(
                target: selectedLocation ?? _defaultLocation,
                zoom: 15.0,
              ),
              onTap: _onMapTap,
              markers: selectedLocation != null
                  ? {
                Marker(
                  markerId: const MarkerId("selected_location"),
                  position: selectedLocation!,
                  infoWindow: InfoWindow(
                    title: "Contact Location",
                    snippet: selectedAddress,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              }
                  : {},
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
            ),

            if (_isLoadingLocation)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // Instructions
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, size: 20, color: primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Tap on map to select exact location",
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: primaryColor, size: 20),
                        onPressed: _closeFullScreenMap,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Selected Location Info
            if (selectedLocation != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Card(
                  elevation: 4,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              "Selected Location:",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedAddress,
                          style: TextStyle(fontSize: 14, color: textColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _closeFullScreenMap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text("Confirm Location"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Normal Form View
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          "Add Emergency Contact",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Card(
                elevation: 2,
                color: cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.emergency, color: primaryColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Add new emergency contact with location",
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Contact Information
              Text(
                "Contact Information",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 16),

              // Name field
              _buildTextField(
                controller: nameController,
                label: "Full Name",
                icon: Icons.person_outline,
                isRequired: true,
              ),
              const SizedBox(height: 16),

              // Phone field
              _buildTextField(
                controller: phoneController,
                label: "Phone Number",
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                isRequired: true,
              ),
              const SizedBox(height: 24),

              // Location Section
              Text(
                "Location Selection",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Search for an area and select exact location on map",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),

              // Search Bar
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: "Search area (e.g., Gazipur, Dhaka, Uttara)",
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search, color: primaryColor),
                            suffixIcon: _isSearching
                                ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                              ),
                            )
                                : null,
                          ),
                          onSubmitted: _searchAndOpenMap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: () => _searchAndOpenMap(searchController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Selected Location Preview
              if (selectedLocation != null) ...[
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              "Location Selected",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedAddress,
                          style: TextStyle(color: textColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showFullScreenMap = true;
                            });
                          },
                          child: Text(
                            "Change Location",
                            style: TextStyle(color: primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: selectedLocation != null ? _saveContact : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedLocation != null ? primaryColor : Colors.grey[400],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    selectedLocation != null
                        ? "Save Emergency Contact"
                        : "Search Location First",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool isRequired = false,
  }) {
    return Card(
      elevation: 2,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: isRequired ? "$label" : label,
          labelStyle: TextStyle(color: textColor),
          prefixIcon: Icon(icon, color: primaryColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}