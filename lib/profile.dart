import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  // Firebase services
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;

  // User data
  Map<String, dynamic>? userData;
  File? profileImage;
  bool isLoading = true;
  bool isEditing = false;
  bool isFirstTime = false;

  // Text controllers for editing
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  // Load user data from Firebase
  Future<void> loadUserData() async {
    try {
      final User? user = auth.currentUser;
      if (user != null) {
        final DocumentSnapshot userDoc = await firestore
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            userData = userDoc.data() as Map<String, dynamic>;
            nameController.text = userData?['name'] ?? '';
            emailController.text = userData?['email'] ?? user.email ?? '';
            phoneController.text = userData?['phone'] ?? '';
            ageController.text = userData?['age']?.toString() ?? '';
            addressController.text = userData?['address'] ?? '';
            isFirstTime = false;
            profileImage = null;
          });
        } else {
          setState(() {
            emailController.text = user.email ?? '';
            isFirstTime = true;
            isEditing = true;
          });
        }
      }
    } catch (e) {
      //print('Error loading user data: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Update user data in Firebase
  Future<void> updateUserData() async {
    try {
      final User? user = auth.currentUser;
      if (user != null) {
        if (isFirstTime) {
          await firestore.collection('users').doc(user.uid).set({
            'name': nameController.text,
            'email': user.email ?? '',
            'phone': phoneController.text,
            'age': int.tryParse(ageController.text) ?? 0,
            'address': addressController.text,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await firestore.collection('users').doc(user.uid).update({
            'name': nameController.text,
            'phone': phoneController.text,
            'age': int.tryParse(ageController.text) ?? 0,
            'address': addressController.text,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await loadUserData();

        setState(() {
          isEditing = false;
          isFirstTime = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Pick profile image from gallery
  Future<void> pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          profileImage = File(image.path);
        });

        // Upload image to Firebase Storage
        await uploadImageToFirebase(File(image.path));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      //print('Error picking image: $e');
      if (e.toString().contains('PERMISSION')) {
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text('Please allow gallery access in app settings to select profile pictures.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pick image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Upload image to Firebase Storage and save URL to Firestore
  Future<void> uploadImageToFirebase(File imageFile) async {
    try {
      final User? user = auth.currentUser;
      if (user != null) {
        // Create a unique filename for the image
        String fileName = 'profile_${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // Reference to Firebase Storage
        Reference storageRef = storage.ref().child('profile_images/$fileName');

        // Upload the file
        UploadTask uploadTask = storageRef.putFile(imageFile);

        // Wait for the upload to complete
        TaskSnapshot snapshot = await uploadTask;

        // Get the download URL
        String downloadUrl = await snapshot.ref.getDownloadURL();

        // Save the URL to Firestore
        await firestore.collection('users').doc(user.uid).update({
          'profileImage': downloadUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update local state
        setState(() {
          userData?['profileImage'] = downloadUrl;
        });
      }
    } catch (e) {
      //print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Sign out user
  Future<void> signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await auth.signOut();
    }
  }

  // Build profile header with image and basic info
  Widget buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade400, Colors.red.shade700],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: profileImage != null
                      ? Image.file(profileImage!, fit: BoxFit.cover)
                      : userData?['profileImage'] != null && userData?['profileImage'].isNotEmpty
                      ? Image.network(
                    userData!['profileImage'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.grey.shade600,
                      );
                    },
                  )
                      : Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 1.5),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.camera_alt, size: 14, color: Colors.red),
                    onPressed: pickImage,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            nameController.text.isEmpty ? 'No Name' : nameController.text,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          Text(
            emailController.text.isEmpty ? 'No Email' : emailController.text,
            style: TextStyle(
              fontSize: 12,
              //color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          if (userData != null && userData!['createdAt'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Member since ${formatDate(userData!['createdAt'])}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String formatDate(dynamic timestamp) {
    if (timestamp == null) return "recently";
    try {
      final date = timestamp.toDate();
      return "${date.day}/${date.month}/${date.year}";
    } catch (e) {
      return "recently";
    }
  }

  // Build profile information section
  Widget buildProfileInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, color: Colors.red.shade600, size: 18),
                const SizedBox(width: 6),
                Text(
                  isFirstTime ? 'Complete Your Profile' : 'Personal Information',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          buildCompactInfoField(
            label: 'Full Name',
            icon: Icons.person,
            controller: nameController,
            isEditing: isEditing,
          ),
          const SizedBox(height: 8),
          buildCompactInfoField(
            label: 'Email',
            icon: Icons.email,
            controller: emailController,
            isEditing: false,
          ),
          const SizedBox(height: 8),
          buildCompactInfoField(
            label: 'Phone',
            icon: Icons.phone,
            controller: phoneController,
            isEditing: isEditing,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          buildCompactInfoField(
            label: 'Age',
            icon: Icons.cake,
            controller: ageController,
            isEditing: isEditing,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          buildCompactInfoField(
            label: 'Address',
            icon: Icons.location_on,
            controller: addressController,
            isEditing: isEditing,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  // Build individual info field
  Widget buildCompactInfoField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required bool isEditing,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: isEditing
                ? TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              decoration: InputDecoration(
                border: InputBorder.none,
                labelText: label,
                hintText: 'Enter your $label',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            )
                : Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.text.isEmpty ? 'Not set' : controller.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: controller.text.isEmpty ? Colors.grey : Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build action buttons
  Widget buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (isEditing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: updateUserData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isFirstTime ? 'Save Profile' : 'Save Changes',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          if (!isEditing)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        isEditing = true;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Edit Profile'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: signOut,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Sign Out'),
                  ),
                ),
              ],
            ),

          if (isEditing) const SizedBox(height: 8),

          if (isEditing)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    isEditing = false;
                    if (isFirstTime) {
                      nameController.clear();
                      phoneController.clear();
                      ageController.clear();
                      addressController.clear();
                    } else {
                      loadUserData();
                    }
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Colors.grey),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(isFirstTime ? 'Cancel Setup' : 'Cancel'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isFirstTime ? 'Complete Profile' : 'My Profile'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading profile...'),
          ],
        ),
      )
          : SingleChildScrollView(
        child: Column(
          children: [
            buildProfileHeader(),
            buildProfileInfo(),
            buildActionButtons(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    ageController.dispose();
    addressController.dispose();
    super.dispose();
  }
}