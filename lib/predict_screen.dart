import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

//  map gestures inside scroll
import 'package:flutter/gestures.dart';
import 'dart:ui' show PointerDeviceKind;

// your weather service
import 'services/weather_service.dart';

class PredictScreen extends StatefulWidget {
  const PredictScreen({super.key});

  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  // Map + search
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  // Location state
  LatLng? _selectedPosition;
  String _selectedPlace = "No location selected";
  String _selectedAddress = "";
  bool _isLoadingLocation = false;

  // ✅ control scroll when interacting with map
  bool _mapInteracting = false;

  // Prediction state
  bool _isLoadingPrediction = false;
  Map<String, double>? _crimeProbabilities;
  String? _predictedCrime;
  double? _confidence;
  String? _predictionError;

  // Markers
  final Set<Marker> _markers = {};

  // Change this to your server URL
  final String _apiBaseUrl = 'http://172.27.119.70:5000';

  //  OpenWeather service
  late final WeatherService _weatherService;

  // Light UI colors
  static const Color bg = Color(0xFFF5F7FB);
  static const Color primary = Color(0xFF4F46E5);
  static const Color border = Color(0xFFE5E7EB);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();

    _weatherService = WeatherService(
      apiKey: "46a98370bb5406fa6e05fb6bf67328f1", // <-- put your key
    );

    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ---------- UTIL ----------
  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  // ONLY 3 crime classes in your model: bodyfound, murder, ViolentCrime
  Color _getCrimeColor(String crimeType) {
    switch (crimeType) {
      case 'ViolentCrime':
        return const Color(0xFFEF4444); // red
      case 'murder':
        return const Color(0xFF7C3AED); // purple
      case 'bodyfound':
        return const Color(0xFFF59E0B); // amber
      default:
        return const Color(0xFF9CA3AF); // gray
    }
  }

  String _prettyCrimeName(String k) {
    if (k == 'ViolentCrime') return 'Violent Crime';
    if (k == 'murder') return 'Murder';
    if (k == 'bodyfound') return 'Body Found';
    return k;
  }

  Widget _card({
    required Widget child,
    EdgeInsets margin = const EdgeInsets.symmetric(horizontal: 16),
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: child,
    );
  }

  // ---------- LOCATION ----------
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _predictionError = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoadingLocation = false;
            _predictionError = "Location permission denied";
          });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPosition = LatLng(position.latitude, position.longitude);
      _updateSelectedLocation(newPosition);

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(newPosition, 14),
        );
      }

      await _getPlaceName(newPosition);
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
        _predictionError = "Failed to get location";
      });
    }
  }

  Future<void> _searchLocation(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    setState(() {
      _isLoadingLocation = true;
      _predictionError = null;
    });

    try {
      final locations = await locationFromAddress('$q, Bangladesh');

      if (locations.isNotEmpty) {
        final pos = locations.first;
        final newPosition = LatLng(pos.latitude, pos.longitude);

        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(newPosition, 14),
          );
        }

        _updateSelectedLocation(newPosition);
        await _getPlaceName(newPosition);
      } else {
        setState(() {
          _isLoadingLocation = false;
          _predictionError = "Location not found";
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
        _predictionError = "Search failed";
      });
    }
  }

  void _onMapTapped(LatLng position) async {
    setState(() => _isLoadingLocation = true);
    _updateSelectedLocation(position);
    await _getPlaceName(position);
  }

  void _updateSelectedLocation(LatLng position) {
    setState(() {
      _selectedPosition = position;

      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('selected'),
            position: position,
            infoWindow: InfoWindow(
              title: 'Selected Location',
              snippet:
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRose,
            ),
          ),
        );
    });
  }

  Future<void> _getPlaceName(LatLng position) async {
    try {
      final placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _selectedPlace = place.locality ??
              place.subAdministrativeArea ??
              place.street ??
              'Selected Location';
          _selectedAddress =
          "${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}";
          _isLoadingLocation = false;
        });
      } else {
        setState(() {
          _selectedPlace = 'Selected Location';
          _selectedAddress =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _selectedPlace = 'Selected Location';
        _selectedAddress =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        _isLoadingLocation = false;
      });
    }
  }

  // ---------- PREDICTION ----------
  Future<void> _getPrediction() async {
    if (_selectedPosition == null) {
      setState(() => _predictionError = "Please select a location first");
      return;
    }

    setState(() {
      _isLoadingPrediction = true;
      _predictionError = null;
    });

    try {
      //  realtime weather
      final weather = await _weatherService.fetchWeather(
        latitude: _selectedPosition!.latitude,
        longitude: _selectedPosition!.longitude,
      );

      final now = DateTime.now();
      final week =
      ((now.difference(DateTime(now.year, 1, 1)).inDays / 7).ceil());
      final weekdays = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday'
      ];
      final weekday = weekdays[now.weekday - 1];

      final hour = now.hour;
      String partOfDay = 'night';
      if (hour < 12) partOfDay = 'morning';
      else if (hour < 17) partOfDay = 'afternoon';
      else if (hour < 20) partOfDay = 'evening';

      final placemarks = await placemarkFromCoordinates(
        _selectedPosition!.latitude,
        _selectedPosition!.longitude,
      );
      final district = placemarks.isNotEmpty
          ? (placemarks.first.administrativeArea ?? 'dhaka')
          : 'dhaka';

      final requestBody = {
        'incident_week': week,
        'incident_weekday': weekday,
        'part_of_the_day': partOfDay,
        'latitude': _selectedPosition!.latitude,
        'longitude': _selectedPosition!.longitude,
        'incident_place': _selectedPlace.toLowerCase(),
        'incident_district': district.toLowerCase(),

        //  real-time weather
        'avg_temp': weather["avg_temp"],
        'weather_code': weather["weather_code"],
        'precip': weather["precip"],
        'humidity': weather["humidity"],
        'cloudcover': weather["cloudcover"],
        'heatindex': weather["heatindex"],
      };

      final response = await http
          .post(
        Uri.parse('$_apiBaseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        setState(() {
          _predictionError = 'Server error: ${response.statusCode}';
          _isLoadingPrediction = false;
        });
        return;
      }

      final data = json.decode(response.body);
      if (data['success'] != true) {
        setState(() {
          _predictionError = 'API error';
          _isLoadingPrediction = false;
        });
        return;
      }

      final result = data['result'];
      final prediction = result['prediction'];
      final probabilities = result['all_probabilities'] as Map;

      final probs = <String, double>{};
      for (final entry in probabilities.entries) {
        final k = entry.key.toString();
        final v = (entry.value as num).toDouble();
        probs[k] = _clamp01(v);
      }

      setState(() {
        _predictedCrime = prediction['crime_type'].toString();
        _confidence = (prediction['confidence'] as num).toDouble();
        _crimeProbabilities = probs;
        _isLoadingPrediction = false;
      });
    } catch (e) {
      setState(() {
        _predictionError = 'Failed to get prediction';
        _isLoadingPrediction = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = (_crimeProbabilities ?? {}).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: Colors.black,
        title: const Text(
          "Crime Prediction",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _getCurrentLocation,
            icon: const Icon(Icons.my_location),
            tooltip: "My location",
          )
        ],
      ),
      body: SingleChildScrollView(
        physics: _mapInteracting
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // SEARCH
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: "Search location (e.g., dhaka)",
                          hintStyle: const TextStyle(color: textMuted),
                          prefixIcon:
                          const Icon(Icons.search, color: textMuted),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, color: textMuted),
                            onPressed: () => _searchController.clear(),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: _searchLocation,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _searchLocation(_searchController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: const Text(
                        "Search",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // MAP (movable inside scroll)
            Listener(
              onPointerDown: (_) => setState(() => _mapInteracting = true),
              onPointerUp: (_) => setState(() => _mapInteracting = false),
              onPointerCancel: (_) => setState(() => _mapInteracting = false),
              child: Container(
                height: 300,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: border),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 10),
                      color: Color(0x14000000),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _selectedPosition == null
                      ? const Center(child: CircularProgressIndicator())
                      : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedPosition!,
                      zoom: 14,
                    ),
                    onMapCreated: (controller) =>
                    _mapController = controller,
                    onTap: _onMapTapped,
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers:
                    <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            if (_isLoadingLocation)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "Updating location...",
                  style:
                  TextStyle(color: textMuted, fontWeight: FontWeight.w700),
                ),
              ),

            const SizedBox(height: 16),

            // SELECTED LOCATION + PREDICT
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Selected Location",
                    style: TextStyle(
                      color: textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.location_on, color: primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPlace,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectedAddress,
                              style: const TextStyle(
                                fontSize: 12,
                                color: textMuted,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _getPrediction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        "Predict",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_isLoadingPrediction)
              const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),

            if (_predictionError != null)
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _predictionError!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),

            // RESULTS (Predicted crime + 3-type breakdown)
            if (_crimeProbabilities != null && _predictedCrime != null)
              _card(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                        _getCrimeColor(_predictedCrime!).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _getCrimeColor(_predictedCrime!)
                              .withOpacity(0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Predicted Crime",
                            style: TextStyle(
                              color: textMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _prettyCrimeName(_predictedCrime!).toUpperCase(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: _getCrimeColor(_predictedCrime!),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Most posibility to Occur",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Crime Type Breakdown",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...breakdown.map((e) {
                      final p = _clamp01(e.value);
                      final c = _getCrimeColor(e.key);
                      final isTop = e.key == _predictedCrime;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _prettyCrimeName(e.key),
                                    style: TextStyle(
                                      fontWeight: isTop
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Text(
                                  "${(p * 100).toStringAsFixed(1)}%",
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: p,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFEFF2F7),
                                valueColor:
                                AlwaysStoppedAnimation<Color>(c),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
