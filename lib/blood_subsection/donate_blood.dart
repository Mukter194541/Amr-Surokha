import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

class DonateBloodScreen extends StatefulWidget {
  const DonateBloodScreen({super.key});

  @override
  State<DonateBloodScreen> createState() => _DonateBloodScreenState();
}

class _DonateBloodScreenState extends State<DonateBloodScreen> {
  // Text controllers for form fields
  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final searchController = TextEditingController();

  // Map variables
  GoogleMapController? mapController;
  LatLng? selectedLocation;
  String selectedAddress = "";
  bool _isSearching = false;
  bool _isLoadingLocation = false;
  bool _showFullScreenMap = false;
  bool _isSubmitting = false;
  bool _isCheckingRegistration = true;

  // Blood group selection
  String? _selectedBloodGroup;

  // User's existing registration data
  Map<String, dynamic>? _existingRegistration;

  // Default camera position
  static const LatLng _defaultLocation = LatLng(23.8103, 90.4125);

  // Color scheme
  final Color primaryColor = Colors.red;
  final Color backgroundColor = Colors.white;
  final Color cardColor = Colors.grey[50]!;
  final Color textColor = Colors.grey[800]!;

  // Available blood groups
  final List<String> _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingRegistration();
  }

  // Check if user is already registered as a donor
  Future<void> _checkExistingRegistration() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection("public_blood_donors")
            .where("userId", isEqualTo: user.uid)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          setState(() {
            _existingRegistration = {
              ...querySnapshot.docs.first.data(),
              'id': querySnapshot.docs.first.id
            };
          });
        }
      }
    } catch (e) {
      print("Error checking registration");
    } finally {
      setState(() {
        _isCheckingRegistration = false;
      });
    }
  }

  // Save donor to Firestore
  Future<void> _registerDonor() async {
    // Validation
    if (nameController.text.isEmpty) {
      showSnackBar("Please enter your full name");
      return;
    }

    if (ageController.text.isEmpty) {
      showSnackBar("Please enter your age");
      return;
    }

    final age = int.tryParse(ageController.text);
    if (age == null || age < 18 || age > 65) {
      showSnackBar("Age must be between 18 to 65 years");
      return;
    }

    if (phoneController.text.isEmpty) {
      showSnackBar("Please enter your phone number");
      return;
    }

    if (emailController.text.isEmpty) {
      showSnackBar("Please enter your email address");
      return;
    }

    if (_selectedBloodGroup == null) {
      showSnackBar("Please select your blood group");
      return;
    }

    if (selectedLocation == null) {
      showSnackBar("Please select your location on the map");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      // Save to public donors collection with user ID
      await FirebaseFirestore.instance
          .collection("public_blood_donors")
          .add({
        "userId": user?.uid,
        "name": nameController.text,
        "age": age,
        "phone": phoneController.text,
        "email": emailController.text,
        "bloodGroup": _selectedBloodGroup,
        "latitude": selectedLocation!.latitude,
        "longitude": selectedLocation!.longitude,
        "address": selectedAddress.isEmpty ? "Selected Location" : selectedAddress,
        "timestamp": FieldValue.serverTimestamp(),
        "isAvailable": true,
        "lastDonation": null,
      });

      // Refresh registration status
      await _checkExistingRegistration();

      showSnackBar("Successfully registered as blood donor!");

    } catch (e) {
      showSnackBar("Error registering as donor");
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  // Cancel donation (delete registration)
  Future<void> _cancelDonation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Blood Donation"),
        content: const Text("Are you sure you want to cancel your blood donation registration? People won't be able to find you as a donor."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Keep Registration"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Cancel Donation",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {

        await FirebaseFirestore.instance
            .collection("public_blood_donors")
            .doc(_existingRegistration!['id'])
            .delete();

        setState(() {
          _existingRegistration = null;
        });

        showSnackBar("Blood donation registration cancelled");
      } catch (e) {
        showSnackBar("Error cancelling registration");

      }
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
    // Show loading while checking registration
    if (_isCheckingRegistration) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text("Register as Blood Donor"),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Checking your registration..."),
            ],
          ),
        ),
      );
    }

    // Show existing registration if user is already registered
    if (_existingRegistration != null) {
      return _buildRegisteredView();
    }

    // Full Screen Map View
    if (_showFullScreenMap) {
      return _buildMapView();
    }

    // Normal Registration Form View
    return _buildRegistrationForm();
  }

  // Build the view when user is already registered
  Widget _buildRegisteredView() {
    final donor = _existingRegistration!;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text("My Blood Donation"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Success Header
              Card(
                elevation: 2,
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "You're a Registered Blood Donor!",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Thank you for being a life saver",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Donor Information Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Your Information",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Blood Group
                      _buildInfoRow(
                        icon: Icons.bloodtype,
                        label: "Blood Group",
                        value: donor['bloodGroup'] ?? 'Not specified',
                        valueColor: primaryColor,
                      ),
                      const SizedBox(height: 12),

                      // Name
                      _buildInfoRow(
                        icon: Icons.person,
                        label: "Name",
                        value: donor['name'] ?? 'Not specified',
                      ),
                      const SizedBox(height: 12),

                      // Age
                      _buildInfoRow(
                        icon: Icons.cake,
                        label: "Age",
                        value: "${donor['age'] ?? 'Not specified'} years",
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      _buildInfoRow(
                        icon: Icons.phone,
                        label: "Phone",
                        value: donor['phone'] ?? 'Not specified',
                      ),
                      const SizedBox(height: 12),

                      // Email
                      _buildInfoRow(
                        icon: Icons.email,
                        label: "Email",
                        value: donor['email'] ?? 'Not specified',
                      ),
                      const SizedBox(height: 12),

                      // Location
                      _buildInfoRow(
                        icon: Icons.location_on,
                        label: "Location",
                        value: donor['address'] ?? 'Not specified',
                      ),
                      const SizedBox(height: 12),

                      // Registration Date
                      if (donor['timestamp'] != null)
                        _buildInfoRow(
                          icon: Icons.calendar_today,
                          label: "Registered Since",
                          value: _formatTimestamp(donor['timestamp']),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Cancel Donation Button
              Card(
                elevation: 2,
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        "Cancel Blood Donation",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "If you cancel, people won't be able to find you as a blood donor. You can register again anytime.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _cancelDonation,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            "Cancel Donation",
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
            ],
          ),
        ),
      ),
    );
  }

  // Build info row for registered view
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Format timestamp for display
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "Unknown";

    try {
      final date = timestamp.toDate();
      return "${date.day}/${date.month}/${date.year}";
    } catch (e) {
      return "Unknown";
    }
  }

  // Build map view
  Widget _buildMapView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Your Location"),
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
                        "Tap on map to select your exact location",
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

  // Build registration form
  Widget _buildRegistrationForm() {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          "Register as Blood Donor",
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
              // Header - This matches your screenshot
              Card(
                elevation: 2,
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.bloodtype, color: primaryColor, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Become a Life Saver",
                              style: TextStyle(
                                fontSize: 16,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Your donation can save up to 3 lives",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
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

              // Personal Information
              Text(
                "Personal Information",
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

              // Age field
              _buildTextField(
                controller: ageController,
                label: "Age",
                icon: Icons.cake_outlined,
                keyboardType: TextInputType.number,
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
              const SizedBox(height: 16),

              // Email field
              _buildTextField(
                controller: emailController,
                label: "Email Address",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                isRequired: true,
              ),
              const SizedBox(height: 16),

              // Blood Group Selection
              Text(
                "Blood Group",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _bloodGroups.length,
                  itemBuilder: (context, index) {
                    final bloodGroup = _bloodGroups[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(bloodGroup),
                        selected: _selectedBloodGroup == bloodGroup,
                        onSelected: (selected) {
                          setState(() {
                            _selectedBloodGroup = selected ? bloodGroup : null;
                          });
                        },
                        backgroundColor: Colors.grey[300],
                        selectedColor: primaryColor,
                        labelStyle: TextStyle(
                          color: _selectedBloodGroup == bloodGroup ? Colors.white : Colors.black,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Location Section
              Text(
                "Your Location",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Select your location so people can find you nearby",
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
                            hintText: "Search your area (e.g., Gazipur, Dhaka, Uttara)",
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

              // Register Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _registerDonor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canRegister() ? primaryColor : Colors.grey[400],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : Text(
                    "Register as Blood Donor",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Disclaimer
              Card(
                elevation: 1,
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Your information will be publicly visible to people searching for blood donors",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
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

  // Check if all required fields are filled
  bool _canRegister() {
    return nameController.text.isNotEmpty &&
        ageController.text.isNotEmpty &&
        phoneController.text.isNotEmpty &&
        emailController.text.isNotEmpty &&
        _selectedBloodGroup != null &&
        selectedLocation != null;
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

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    phoneController.dispose();
    emailController.dispose();
    searchController.dispose();
    super.dispose();
  }
}