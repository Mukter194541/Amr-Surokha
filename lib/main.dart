import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'location.dart';
import 'contact.dart';
import 'auth_page.dart';
import 'help.dart.';
import 'blood.dart.';
import 'profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF64D2A3),
        scaffoldBackgroundColor: const Color(0xFF64D2A3),

        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF64D2A3),
          foregroundColor: Colors.black,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.orangeAccent,
        ),
      ),






      //  If user logged in → HomeActivity, else AuthPage
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return const HomeActivity(); // already logged in
          }
          return const AuthPage(); // show login/signup
        },
      ),
    );
  }
}

class HomeActivity extends StatefulWidget {
  const HomeActivity({super.key});

  @override
  State<HomeActivity> createState() => _HomeActivityState();
}

class _HomeActivityState extends State<HomeActivity> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const MapScreen(),
    const HelpScreen(),
    const ProfileScreen(),
    const EmergencyContactScreen(),
    const EmergencyBloodScreen(),
    //Builder(builder: (context) => const EmergencyContactScreen()),
  ];

  final List<String> _titles = [
    "Incident Details",
    "Help Center",
    "My Profile",
    "",
    "Emergency Blood"
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /*appBar: AppBar(
       // title: Text(_titles[_selectedIndex]),
        centerTitle: true,
        //backgroundColor: Colors.cyan,
        //elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),*/
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.cyan,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Maps"),
          BottomNavigationBarItem(icon: Icon(Icons.help), label: "Help"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
          BottomNavigationBarItem(icon: Icon(Icons.contact_emergency), label: "Contact"),
          BottomNavigationBarItem(icon: Icon(Icons.bloodtype), label: "Blood"),
        ],
      ),
    );
  }
}

/*class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Profile Screen'));
  }
}*/

/*class EmergencyBloodScreen extends StatelessWidget {
  const EmergencyBloodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Blood Screen'));
  }
}*/
