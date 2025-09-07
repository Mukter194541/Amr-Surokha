import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// Screen to show the list of emergency contacts
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => EmergencyContactScreenState();
}

class EmergencyContactScreenState extends State<EmergencyContactScreen> {
  Position? _userPosition;  // User's current GPS position, initially null

  // Get current logged-in user's unique ID from Firebase Auth
  final userId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    getUserLocation();  // Get user's current location when the screen loads
  }

  /// Function to get the user's current GPS location with permission handling
  Future<void> getUserLocation() async {
    // Check if location services are enabled on the device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // If not enabled, show a message to user and return early
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services")),
      );
      return;
    }

    // Check the current permission status for location
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // If permission is denied, request it from the user
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // If still denied, show message and return early
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // If permission is denied forever, show message and return early
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permissions are permanently denied")),
      );
      return;
    }

    // If permission granted, get current position with high accuracy
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Update the state with the current position (to trigger UI update)
    setState(() => _userPosition = position);
  }

  /// Calculate distance in meters between user's position and a contact's position
  double _calculateDistance(double lat, double lng) {
    if (_userPosition == null) return double.infinity; // If location not available, return very large number
    return Geolocator.distanceBetween(
      _userPosition!.latitude,    // User's latitude
      _userPosition!.longitude,   // User's longitude
      lat,                       // Contact's latitude
      lng,                       // Contact's longitude
    );
  }

  /// Function to delete a contact with confirmation dialog
  Future<void> _deleteContact(String id) async {
    // Show a confirmation dialog to the user
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Contact"),
        content: const Text("Are you sure you want to delete this contact?"),
        actions: [
          // Cancel button - returns false (don't delete)
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          // Delete button - returns true (delete)
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      // If user confirms, delete contact from Firestore database
      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)  // User's document
          .collection("contacts") // Subcollection contacts
          .doc(id)  // Contact document by id
          .delete();

      // Show message that contact was deleted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contact deleted")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use StreamBuilder to listen to real-time updates from Firestore
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("contacts")
            .snapshots(),  // Listen to contacts collection snapshots
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // If error occurs while fetching data, show error message
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            // While waiting for data, show loading spinner
            return const Center(child: CircularProgressIndicator());
          }

          // Map each document into a Map with data including calculated distance
          final contacts = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;

            // Calculate distance from user's current location to contact's location
            final distance = _calculateDistance(
              (data["latitude"] ?? 0).toDouble(),
              (data["longitude"] ?? 0).toDouble(),
            );

            return {
              "id": doc.id,
              "name": data["name"] ?? "Unknown",
              "phone": data["phone"] ?? "",
              "latitude": data["latitude"],
              "longitude": data["longitude"],
              "distance": distance,  // distance in meters
            };
          }).toList();

          // Sort contacts list by nearest distance first
          contacts.sort((a, b) => a["distance"].compareTo(b["distance"]));

          if (contacts.isEmpty) {
            // If no contacts found, show a message
            return const Center(child: Text("No contacts found. Add one!"));
          }

          // Build a list view showing each contact's details
          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];

              // Convert distance to kilometers with 2 decimals
              final distanceInKm = (contact["distance"] / 1000).toStringAsFixed(2);

              return ListTile(
                leading: const Icon(Icons.person, color: Colors.blue), // Person icon
                title: Text(contact["name"]),  // Contact name
                subtitle: Text(
                  "${contact["phone"]}\n$distanceInKm km away", // Phone + distance in km
                ),
                isThreeLine: true, // Allow subtitle to take two lines
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red), // Delete icon button
                  onPressed: () => _deleteContact(contact["id"]),  // Delete contact on tap
                ),
              );
            },
          );
        },
      ),

      // Floating button to navigate to AddContactScreen
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Screen to add a new contact
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  // Controllers to get input text from user
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  // Get current user ID from Firebase Auth
  final userId = FirebaseAuth.instance.currentUser!.uid;

  /// Save the new contact to Firestore
  Future<void> _saveContact() async {
    // Validate all fields are filled
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _latController.text.isEmpty ||
        _lngController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    try {
      // Add a new document in user's contacts subcollection
      await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("contacts")
          .add({
        "name": _nameController.text,
        "phone": _phoneController.text,
        "latitude": double.parse(_latController.text),
        "longitude": double.parse(_lngController.text),
      });

      // After saving, go back to previous screen
      Navigator.pop(context);
    } catch (e) {
      // If error occurs, show a generic error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(title: const Text("Add Contact")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // TextField for contact name
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),

            // TextField for contact phone number
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: "Phone"),
            ),

            // TextField for contact latitude (as string, converted later)
            TextField(
              controller: _latController,
              decoration: const InputDecoration(labelText: "Latitude"),
            ),

            // TextField for contact longitude (as string, converted later)
            TextField(
              controller: _lngController,
              decoration: const InputDecoration(labelText: "Longitude"),
            ),

            const SizedBox(height: 20),

            // Button to save contact
            ElevatedButton(
              onPressed: _saveContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, // button color
                foregroundColor: Colors.white, // text color
              ),
              child: const Text("Save"),
            ),

          ],
        ),
      ),
    );
  }
}
