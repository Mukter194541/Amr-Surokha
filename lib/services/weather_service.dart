import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  final String apiKey;

  WeatherService({required this.apiKey});

  static const String _baseUrl =
      "https://api.openweathermap.org/data/2.5/weather";

  Future<Map<String, dynamic>> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception("OpenWeather API error: ${response.statusCode}");
    }

    final data = json.decode(response.body);

    final double avgTemp = (data["main"]["temp"] as num).toDouble();
    final int humidity = (data["main"]["humidity"] as num).toInt();
    final int cloudcover = (data["clouds"]?["all"] as num?)?.toInt() ?? 0;
    final int weatherCode = (data["weather"][0]["id"] as num).toInt();

    final double precip =
    ((data["rain"]?["1h"] as num?)?.toDouble() ??
        (data["rain"]?["3h"] as num?)?.toDouble() ??
        (data["snow"]?["1h"] as num?)?.toDouble() ??
        (data["snow"]?["3h"] as num?)?.toDouble() ??
        0.0);

    // OpenWeather doesn't provide heat index directly (free tier),
    // so "feels_like" is used as a good proxy.
    final double heatindex = (data["main"]["feels_like"] as num).toDouble();

    return {
      "avg_temp": avgTemp,
      "humidity": humidity,
      "cloudcover": cloudcover,
      "weather_code": weatherCode,
      "precip": precip,
      "heatindex": heatindex,
    };
  }
}
