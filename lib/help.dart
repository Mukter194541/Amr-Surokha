import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => HelpScreenState();
}

class HelpScreenState extends State<HelpScreen> {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  Position? userPosition;

  @override
  void initState() {
    super.initState();
    getLocation();
  }

  // Get user current location
  Future<void> getLocation() async {
    userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {}); // update UI
  }

  // Calculate distance between user and contact
  double distance(double lat, double lng) {
    if (userPosition == null) return double.infinity;
    return Geolocator.distanceBetween(
      userPosition!.latitude,
      userPosition!.longitude,
      lat,
      lng,
    );
  }

  //  Get the nearest contact from Firestore
  Future<Map<String, dynamic>?> getNearestContact() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("contacts")
        .get();

    if (snapshot.docs.isEmpty || userPosition == null) return null;

    List<Map<String, dynamic>> contacts = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        "name": data["name"] ?? "Unknown",
        "phone": data["phone"] ?? "",
        "distance": distance(
            (data["latitude"] ?? 0).toDouble(),
            (data["longitude"] ?? 0).toDouble()),
      };
    }).toList();

    contacts.sort((a, b) => a["distance"].compareTo(b["distance"]));

    return contacts.first;
  }

  //  Make a phone call
  Future<void> call(String phone) async {
    if (await Permission.phone.request().isGranted) {
      final uri = Uri.parse("tel:$phone");
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone permission denied")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: Center(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: getNearestContact(),
          builder: (context, snapshot) {
            if (userPosition == null ||
                snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return const Text("No contact found");
            }

            final contact = snapshot.data!;

            return ElevatedButton(
              onPressed: () => call(contact["phone"]),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(80),
                backgroundColor: Colors.red,
              ),
              child: Text(
                "SOS ",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 50, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            );
          },
        ),
      ),
    );
  }
}
