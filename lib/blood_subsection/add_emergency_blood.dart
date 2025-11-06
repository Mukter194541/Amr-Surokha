import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

class AddEmergencyBloodScreen extends StatefulWidget {
  const AddEmergencyBloodScreen({super.key});

  @override
  State<AddEmergencyBloodScreen> createState() => _AddEmergencyBloodScreenState();
}

class _AddEmergencyBloodScreenState extends State<AddEmergencyBloodScreen> {
  // Text controllers for form fields
  final nameController = TextEditingController();
  final ageController = TextEditingController();
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
  bool _isSaving = false;

  // Blood groups list
  final List<String> bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];
  String? selectedBloodGroup;

  // Default camera position
  static const LatLng _defaultLocation = LatLng(23.8103, 90.4125);

  // Save emergency blood request to Firestore WITH PRIVACY
  Future<void> _saveEmergencyBlood() async {
    if (_isSaving) return;

    // Validate required fields
    if (nameController.text.isEmpty ||
        ageController.text.isEmpty ||
        selectedBloodGroup == null) {
      _showSnackBar("Please fill all required fields");
      return;
    }

    if (selectedLocation == null) {
      _showSnackBar("Please select a location");
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Save with user ID as document ID for PRIVACY
      await FirebaseFirestore.instance
          .collection("Add_emergency_blood")
          .doc(userId)  // Use user ID as document ID
          .collection("emergency_blood_donors")
          .add({
        "donorName": nameController.text.trim(),
        "age": int.tryParse(ageController.text.trim()) ?? 0,
        "bloodGroup": selectedBloodGroup,
        "phone": phoneController.text.isEmpty ? "Not provided" : phoneController.text.trim(),
        "latitude": selectedLocation!.latitude,
        "longitude": selectedLocation!.longitude,
        "address": selectedAddress.isEmpty ? "Selected Location" : selectedAddress,
        "timestamp": FieldValue.serverTimestamp(),
        "status": "active",
      }, ); // merge: true allows updating existing data

      _showSnackBar("Blood donor saved successfully!");

      // Clear form and go back
      _clearForm();
      Navigator.pop(context);

    } catch (e) {
      print("Firestore Error: ");
      _showSnackBar("Error: Please try again");
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _clearForm() {
    nameController.clear();
    ageController.clear();
    phoneController.clear();
    setState(() {
      selectedBloodGroup = null;
      selectedLocation = null;
      selectedAddress = "";
    });
  }

  // Search for a location and open full screen map
  Future<void> _searchAndOpenMap(String query) async {
    if (query.isEmpty) {
      _showSnackBar("Please enter a location to search");
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
        _showSnackBar("Location '$query' not found");
      }
    } catch (e) {
      _showSnackBar("Error searching location");
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
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
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
          title: const Text("Select Location"),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
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
                    title: "Donor Location",
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

            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, size: 20, color: Colors.black),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Tap on map to select location",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black, size: 20),
                        onPressed: _closeFullScreenMap,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (selectedLocation != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Selected Location:",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedAddress,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _closeFullScreenMap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Add Emergency Blood"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Header with privacy info
              Card(
                elevation: 2,
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.bloodtype, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Emergency Blood  Registration",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Add familiar person's Blood group for critical situation ",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Donor Information
              const Text(
                "Blood Donor Information",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 16),

              // Name field
              _buildTextField(
                controller: nameController,
                label: "Donor Name",
                icon: Icons.person,
                isRequired: true,
              ),
              const SizedBox(height: 16),

              // Age field
              _buildTextField(
                controller: ageController,
                label: "Age",
                icon: Icons.cake,
                keyboardType: TextInputType.number,
                isRequired: true,
              ),
              const SizedBox(height: 16),

              // Blood Group Dropdown
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonFormField<String>(
                    value: selectedBloodGroup,
                    decoration: const InputDecoration(
                      labelText: "Blood Group",
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.bloodtype),
                    ),
                    items: bloodGroups.map((String bloodGroup) {
                      return DropdownMenuItem<String>(
                        value: bloodGroup,
                        child: Text(bloodGroup),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedBloodGroup = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select blood group';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Phone field (optional)
              _buildTextField(
                controller: phoneController,
                label: "Contact Phone",
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                isRequired: false,
              ),
              const SizedBox(height: 24),

              // Location Section
              const Text(
                "Location",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Search and select Donor location",
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
                            hintText: "Search location...",
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search, color: Colors.blue),
                            suffixIcon: _isSearching
                                ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
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
                          color: Colors.blue,
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
                            const Icon(Icons.check_circle, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            const Text(
                              "Location Selected",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(selectedAddress),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showFullScreenMap = true;
                            });
                          },
                          child: const Text("Change Location"),
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
                  onPressed: _isSaving ? null : _saveEmergencyBlood,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    "Save Details",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

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
          prefixIcon: Icon(icon, color: Colors.blue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}