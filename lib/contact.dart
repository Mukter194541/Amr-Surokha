import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => EmergencyContactScreenState();
}

class EmergencyContactScreenState extends State<EmergencyContactScreen> {
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    getUserLocation();
  }

  /// Get current user location
  Future<void> getUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services")),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Location permissions are permanently denied")),
      );
      return;
    }

    final position =
    await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() => _userPosition = position);
  }

  /// Calculate distance between user and contact
  double _calculateDistance(double lat, double lng) {
    if (_userPosition == null) return double.infinity;
    return Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
  }

  /// Confirm and delete a contact
  Future<void> _deleteContact(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Contact"),
        content: const Text("Are you sure you want to delete this contact?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection("contacts").doc(id).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contact deleted")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("contacts").snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var contacts = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final distance = _calculateDistance(
              (data["latitude"] ?? 0).toDouble(),
              (data["longitude"] ?? 0).toDouble(),
            );
            return {
              "id": doc.id, // store document ID
              "name": data["name"] ?? "Unknown",
              "phone": data["phone"] ?? "",
              "latitude": data["latitude"],
              "longitude": data["longitude"],
              "distance": distance,
            };
          }).toList();

          contacts.sort((a, b) => a["distance"].compareTo(b["distance"]));

          if (contacts.isEmpty) {
            return const Center(child: Text("No contacts found. Add one!"));
          }



          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(contact["name"]),
                subtitle: Text(
                  "${contact["phone"]}\n${contact["distance"].toStringAsFixed(0)} m away",
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteContact(contact["id"]),
                ),
              );
            },
          );
        },
      ),

      // Add new contact button
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddContactScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  Future<void> _saveContact() async {
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _latController.text.isEmpty ||
        _lngController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    await FirebaseFirestore.instance.collection("contacts").add({
      "name": _nameController.text,
      "phone": _phoneController.text,
      "latitude": double.parse(_latController.text),
      "longitude": double.parse(_lngController.text),
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Contact")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Name")),
            TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: "Phone")),
            TextField(
                controller: _latController,
                decoration: const InputDecoration(labelText: "Latitude")),
            TextField(
                controller: _lngController,
                decoration: const InputDecoration(labelText: "Longitude")),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _saveContact, child: const Text("Save"))
          ],
        ),
      ),
    );
  }
}
