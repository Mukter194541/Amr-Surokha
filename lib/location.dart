import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'services/weather_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;

  String _currentAddress = "Fetching address...";
  String _coordinates = "Fetching coordinates...";

  bool _isLoadingPrediction = false;
  Map<String, double>? _crimeProbabilities;
  String? _predictedCrime;
  double? _confidence;
  String? _predictionError;

  late final WeatherService _weatherService;
  final String _apiBaseUrl = 'http://172.27.119.70:5000';

  static const Color bg = Color(0xFFF5F7FB);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE5E7EB);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textDark = Color(0xFF111827);
  static const Color primary = Colors.lightBlueAccent;

  static const Set<String> _allowedCrimes = {
    'ViolentCrime',
    'murder',
    'bodyfound'
  };

  @override
  void initState() {
    super.initState();
    _weatherService =
        WeatherService(apiKey: "46a98370bb5406fa6e05fb6bf67328f1");
    _getLocationAndAutoPredict();
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  Color _getCrimeColor(String type) {
    switch (type) {
      case 'ViolentCrime':
        return Colors.red;
      case 'murder':
        return Colors.deepPurple;
      case 'bodyfound':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getCrimeIcon(String type) {
    switch (type) {
      case 'ViolentCrime':
        return Icons.warning_amber_rounded;
      case 'murder':
        return Icons.gavel_rounded;
      case 'bodyfound':
        return Icons.location_searching_rounded;
      default:
        return Icons.help_outline;
    }
  }

  String _pretty(String k) {
    if (k == 'ViolentCrime') return "Violent Crime(Assault,Rape)";
    if (k == 'murder') return "Murder";
    if (k == 'bodyfound') return "Body Found";
    return k;
  }

  Future<void> _getLocationAndAutoPredict() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    final lat = pos.latitude;
    final lon = pos.longitude;

    _currentPosition = LatLng(lat, lon);
    _coordinates =
    "Lat: ${lat.toStringAsFixed(6)}, Lng: ${lon.toStringAsFixed(6)}";

    String district = 'dhaka';
    String placeName = 'unknown';

    final placemarks = await placemarkFromCoordinates(lat, lon);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      _currentAddress =
      "${p.locality ?? ''}, ${p.administrativeArea ?? ''}, ${p.country ?? ''}";

      district =
      (p.subAdministrativeArea ?? p.administrativeArea ?? 'dhaka');
      placeName =
      (p.locality ?? p.subLocality ?? p.street ?? 'unknown');
    }

    setState(() {});

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentPosition!, 16),
    );

    await _predict(lat, lon, district, placeName);
  }

  Future<void> _predict(
      double lat, double lon, String district, String placeName) async {
    setState(() {
      _isLoadingPrediction = true;
      _predictionError = null;
    });

    try {
      final weather =
      await _weatherService.fetchWeather(latitude: lat, longitude: lon);

      final now = DateTime.now();
      final week =
      ((now.difference(DateTime(now.year, 1, 1)).inDays / 7).ceil());

      final weekday = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday'
      ][now.weekday - 1];

      final hour = now.hour;
      String part = 'night';
      if (hour < 12) part = 'morning';
      else if (hour < 17) part = 'afternoon';
      else if (hour < 20) part = 'evening';

      String clean(String s) => s.trim().toLowerCase();

      final body = {
        'incident_week': week,
        'incident_weekday': clean(weekday),
        'part_of_the_day': clean(part),
        'latitude': lat,
        'longitude': lon,
        'incident_place': clean(placeName),
        'incident_district': clean(district),
        'avg_temp': weather["avg_temp"],
        'weather_code': weather["weather_code"],
        'precip': weather["precip"],
        'humidity': weather["humidity"],
        'cloudcover': weather["cloudcover"],
        'heatindex': weather["heatindex"],
      };

      final res = await http.post(
        Uri.parse('$_apiBaseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      final data = json.decode(res.body);
      final result = data['result'];
      final probsRaw =
      Map<String, dynamic>.from(result['all_probabilities']);

      final probs = <String, double>{};
      for (final e in probsRaw.entries) {
        if (_allowedCrimes.contains(e.key)) {
          probs[e.key] = _clamp01((e.value as num).toDouble());
        }
      }

      final predicted = result['prediction']['crime_type'];

      setState(() {
        _crimeProbabilities = probs;
        _predictedCrime = predicted;
        _confidence = probs[predicted] ?? 0.0;
        _isLoadingPrediction = false;
      });
    } catch (e) {
      setState(() {
        _predictionError = "Prediction failed";
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
        backgroundColor: primary,
        centerTitle: true,
        title: const Text(
          "Live Location",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // MAP CARD (Movable)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Container(
                    height: 230,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _currentPosition == null
                          ? const Center(child: CircularProgressIndicator())
                          : GoogleMap(
                        onMapCreated: (c) => _mapController = c,
                        initialCameraPosition: CameraPosition(
                          target: _currentPosition!,
                          zoom: 16,
                        ),
                        markers: {
                          Marker(
                            markerId:
                            const MarkerId("currentLocation"),
                            position: _currentPosition!,
                          ),
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,

                        // Map movable again
                        scrollGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_currentAddress,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(_coordinates,
                      style: const TextStyle(color: textMuted)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoadingPrediction)
              const CircularProgressIndicator()
            else if (_predictionError != null)
              Text(_predictionError!,
                  style: const TextStyle(color: Colors.red))
            else if (_crimeProbabilities != null &&
                  _predictedCrime != null)
                Container(
                  margin:
                  const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Text("Crime Type Breakdown",
                          style: TextStyle(
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      ...breakdown.map((e) {
                        final p = e.value;
                        final c = _getCrimeColor(e.key);

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8),
                          child: Row(
                            children: [
                              Icon(_getCrimeIcon(e.key),
                                  color: c),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment
                                          .spaceBetween,
                                      children: [
                                        Text(_pretty(e.key)),
                                        Text(
                                            "${(p * 100).toStringAsFixed(1)}%"),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                      value: p,
                                      minHeight: 8,
                                      valueColor:
                                      AlwaysStoppedAnimation(
                                          c),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
