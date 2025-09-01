import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController; // Controller to control the map
  LatLng? _currentPosition; // Store user location
  String _currentAddress = "Fetching address..."; // Store address
  String _coordinates = "Fetching coordinates..."; // Store coordinates

  @override
  void initState() {
    super.initState();
    _getLocation(); // Get user location when screen opens
  }

  // Function to check permission and get location
  Future<void> _getLocation() async {
    //  Check location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _currentAddress = "Location permission denied";
          _coordinates = "Coordinates not available";
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _currentAddress =
        "Location permissions are permanently denied. Enable them from phone settings.";
        _coordinates = "Coordinates not available";
      });
      return;
    }

    //  Get current position
    final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    //  Save position
    _currentPosition = LatLng(position.latitude, position.longitude);

    // Save coordinates
    _coordinates =
    "Lat: ${position.latitude}, Lng: ${position.longitude}";

    //  Get address from coordinates
    final placemarks =
    await placemarkFromCoordinates(position.latitude, position.longitude);
    final place = placemarks[0];
    _currentAddress = "${place.street}, ${place.locality}, ${place.country}";

    setState(() {}); // Update the UI

    //  Move map to current location
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentPosition!, 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Location",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),


          SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: _currentPosition == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: CameraPosition(
                target: _currentPosition!,
                zoom: 16,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId("currentLocation"),
                  position: _currentPosition!,
                  infoWindow: const InfoWindow(title: "Your Location"),
                ),
              },
              myLocationEnabled: true, // Show blue dot
              myLocationButtonEnabled: true, // Show button
            ),
          ),


          Container(

            width: double.infinity,
            child: Text(
              _coordinates,
              style: const TextStyle(fontSize: 14),
            ),
          ),


          Container(

            width: double.infinity,
            child: Text(
              _currentAddress,
              style: const TextStyle(fontSize: 14),
            ),
          ),


          const Expanded(
            child: Center(
              child: Text(""),
            ),
          ),
        ],
      ),
    );
  }
}
