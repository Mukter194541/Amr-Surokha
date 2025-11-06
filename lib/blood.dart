import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:safegurd/blood_subsection/add_emergency_blood.dart';
import 'blood_subsection/Emergency_blood_list.dart';
import 'blood_subsection/donate_blood.dart';
import 'blood_subsection/search_blood.dart';


class EmergencyBloodScreen extends StatefulWidget {
  const EmergencyBloodScreen({super.key});

  @override
  State<EmergencyBloodScreen> createState() => EmergencyBloodScreenstate();
}

class EmergencyBloodScreenstate extends State<EmergencyBloodScreen> {

  final userId = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      backgroundColor: Colors.white,


      appBar: AppBar(
        title: const Text(
          "Blood Emergency",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      // Main content
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  "Life-Saving Blood Services",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Grid of 4 cards (2x2 layout)
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2, // 2 columns
                  crossAxisSpacing: 12, // Space between columns
                  mainAxisSpacing: 12, // Space between rows
                  childAspectRatio: 0.85, // Card width/height ratio
                  children: [
                    // Card 1: Search Blood
                    buildBloodCard(
                      icon: Icons.search,
                      title: "Search Blood",
                      subtitle: "Find blood donors nearby",
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SearchBloodScreen()),
                        );
                      },
                    ),

                    // Card 2: Donate Blood
                    buildBloodCard(
                      icon: Icons.favorite,
                      title: "Donate Blood",
                      subtitle: "Register as blood donor",
                      color: Colors.red,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DonateBloodScreen()),
                        );
                      },
                    ),

                    // Card 3: Add Emergency Blood
                    buildBloodCard(
                      icon: Icons.emergency,
                      title: "Add Emergency Blood",
                      subtitle: "Add urgent blood need",
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddEmergencyBloodScreen()),
                        );
                      },
                    ),

                    // Card 4: Emergency Blood List
                    buildBloodCard(
                      icon: Icons.list_alt,
                      title: "Emergency Blood List",
                      subtitle: "View active blood Donors",
                      color: Colors.green,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const EmergencyBloodListScreen()),
                        );
                        // Navigate to Emergency Blood List screen
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Simple function to create a blood card
  Widget buildBloodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap, // ← ADDED this parameter
  }) {
    return Card(

      elevation: 3,


      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),

      // Make card clickable
      child: InkWell(
        onTap: onTap,

        // Rounded corners for tap effect
        borderRadius: BorderRadius.circular(12),

        // Card content
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Big icon in circle
              Container(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  icon,
                  size: 50, // Big icon
                  color: color,
                ),
              ),


              const SizedBox(height: 8),

              // Card title
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),


              const SizedBox(height: 2),

              // Card description
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}