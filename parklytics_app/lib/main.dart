import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';

void main() => runApp(const ParklyticsApp());

class ParklyticsApp extends StatelessWidget {
  const ParklyticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Parklytics',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapScreen(),
    );
  }
}

// Enhanced Road data class
class Road {
  final String name;
  final List<LatLng> points;
  final Color color;
  final String status;
  final int availabilityChance; // Percentage chance of finding a spot

  Road({
    required this.name,
    required this.points,
    required this.color,
    required this.status,
    required this.availabilityChance,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;
  static const LatLng _kozhikodeBeach = LatLng(11.2588, 75.7705);
  // Distant teleport point for testing (Baby Memorial Hospital area)
  static const LatLng _teleportPoint = LatLng(11.2625, 75.7931);

  List<Road> _roads = [];
  List<LatLng> _routePoints = [];
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  Road? _recommendedRoad;
  bool _isNavigating = false;
  String _navigationInstruction = 'Follow the path';

  // Demo Mode State
  bool _isDemoRunning = false;
  String _demoStatusMessage = '';
  Timer? _demoTimer;
  int _demoStep = 0;
  List<LatLng> _demoPath = [];
  double _currentHeading = 0.0;
  
  // Navigation Info
  List<dynamic> _routeSteps = [];
  int _currentRouteStepIndex = 0;
  double _demoRemainingDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
    _initializeRoads();
    _fetchRoadGeometries();
    _getCurrentLocation();
  }

  void _initializeRoads() {
    // We only provide Start/End anchors. Points will be populated by OSRM API.
    _roads = [
      Road(
        name: 'Main Beach Road',
        points: [
          const LatLng(11.2648, 75.7681),
          const LatLng(11.2478, 75.7728),
        ],
        color: Colors.red,
        status: 'Busy',
        availabilityChance: 15,
      ),
      Road(
        name: 'Joseph Road',
        points: [
          const LatLng(11.2587, 75.7707),
          const LatLng(11.2588, 75.7785),
        ],
        color: Colors.green,
        status: 'Highly Available',
        availabilityChance: 85,
      ),
      Road(
        name: 'Customs Road',
        points: [
          const LatLng(11.2561, 75.7714),
          const LatLng(11.2562, 75.7795),
        ],
        color: Colors.orange,
        status: 'Medium',
        availabilityChance: 45,
      ),
      Road(
        name: 'Red Cross Road',
        points: [
          const LatLng(11.2541, 75.7722),
          const LatLng(11.2542, 75.7820),
        ],
        color: Colors.green,
        status: 'Available',
        availabilityChance: 78,
      ),
    ];
  }

  Future<void> _fetchRoadGeometries() async {
    for (int i = 0; i < _roads.length; i++) {
      final road = _roads[i];
      if (road.points.length != 2) continue;

      final start = road.points[0];
      final end = road.points[1];

      final url =
          'https://router.project-osrm.org/match/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson&overview=full';

      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20)); // Increased from 5s for slow internet
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['matchings'] != null && data['matchings'].isNotEmpty) {
            final geometry =
                data['matchings'][0]['geometry']['coordinates'] as List;
            final List<LatLng> roadPoints = geometry
                .map(
                  (coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()),
                )
                .toList();

            if (mounted) {
              setState(() {
                _roads[i] = Road(
                  name: road.name,
                  points: roadPoints,
                  color: road.color,
                  status: road.status,
                  availabilityChance: road.availabilityChance,
                );
              });
            }
          }
        }
      } catch (e) {
        print('Error fetching geometry for ${road.name}: $e');
        // Fallback to simple line if OSRM fails
      }
    }
  }

  // Auto-Teleport Check: If emulator is in another continent
  void _checkAndTeleport() {
    if (_currentLocation != null) {
      double distance = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        _kozhikodeBeach.latitude,
        _kozhikodeBeach.longitude,
      );

      // If more than 500km away, suggest teleport
      if (distance > 500000) {
        _showTeleportDialog();
      }
    }
  }

  void _showTeleportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Update'),
        content: const Text(
          'Your current location seems to be very far from Kozhikode. Would you like to teleport to the city center (approx. 3km away) for testing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentLocation = _teleportPoint;
              });
              Navigator.pop(context);
              _mapController.animateTo(dest: _teleportPoint, zoom: 15.5);
            },
            child: const Text('Teleport (Recommended)'),
          ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      final position = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _checkAndTeleport();
    } catch (e) {
      print('Location error: $e');
    }
  }

  // Interpolate route points so the vehicle animates smoothly instead of teleporting
  List<LatLng> _interpolatePath(List<LatLng> originalPath, double maxStepDistanceMeters) {
    if (originalPath.length <= 1) return originalPath;

    final List<LatLng> interpolated = [originalPath.first];

    for (int i = 0; i < originalPath.length - 1; i++) {
      final start = originalPath[i];
      final end = originalPath[i + 1];

      final distance = Geolocator.distanceBetween(
          start.latitude, start.longitude, end.latitude, end.longitude);

      if (distance > maxStepDistanceMeters) {
        final steps = (distance / maxStepDistanceMeters).ceil();
        final latStep = (end.latitude - start.latitude) / steps;
        final lngStep = (end.longitude - start.longitude) / steps;

        for (int j = 1; j < steps; j++) {
          interpolated.add(
            LatLng(start.latitude + (latStep * j), start.longitude + (lngStep * j))
          );
        }
      }
      interpolated.add(end);
    }
    return interpolated;
  }

  // Routing UI Helpers
  String _getInstructionFromStep(Map<String, dynamic> step) {
    try {
      final maneuver = step['maneuver'] ?? {};
      final type = maneuver['type'] as String? ?? '';
      final modifier = maneuver['modifier'] as String? ?? '';
      final name = step['name'] as String? ?? '';
      
      String cleanModifier = modifier.replaceAll('-', ' ');
      if (type == 'turn') {
        return 'Turn $cleanModifier onto ${name.isEmpty ? "the street" : name}';
      } else if (type == 'new name' || type == 'continue') {
        return 'Continue on ${name.isEmpty ? "the street" : name}';
      } else if (type == 'arrive') {
        return 'Arrive at parking street';
      } else if (type == 'depart') {
        return 'Head $cleanModifier on ${name.isEmpty ? "the street" : name}';
      } else if (type == 'roundabout') {
        return 'Take the roundabout';
      }
      return 'Follow the path';
    } catch (e) {
      return 'Drive carefully';
    }
  }

  IconData _getIconForModifier(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) return Icons.turn_left;
    if (lower.contains('right')) return Icons.turn_right;
    if (lower.contains('roundabout')) return Icons.roundabout_right;
    if (lower.contains('arrive')) return Icons.flag;
    return Icons.straight;
  }

  // --- DEMO MODE LOGIC ---
  Future<void> _startDemoDrive() async {
    if (_isDemoRunning) return;

    if (_routePoints.isEmpty || !_isNavigating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please search for a destination first before starting the demo.'),
        ),
      );
      return;
    }

    setState(() {
      _isDemoRunning = true;
      _demoStep = 0;
      _demoStatusMessage = 'Route calculation...';
      _demoPath = List<LatLng>.from(_routePoints);
    });

    // Interpolate points so we smoothly step every ~12 meters (faster demo)
    _demoPath = _interpolatePath(_demoPath, 12.0);
    _demoRemainingDistance = _demoPath.length * 12.0;

    if (!mounted) return;

    setState(() {
      _currentLocation = _demoPath.first;
      _demoStatusMessage = 'Driving to recommended parking street...';
    });

    _mapController.animateTo(dest: _currentLocation!, zoom: 18.0);

    // Wait for the initial animation to settle so map tiles can load
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isDemoRunning) return;

      // Timer set to 100ms for fast animation. 12m per 100ms = 120m/s = 432 km/h
      _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_demoStep < _demoPath.length - 1) {
          setState(() {
            _demoStep++;
            _currentLocation = _demoPath[_demoStep];
            _demoRemainingDistance = (_demoPath.length - _demoStep) * 12.0;
            
            final prev = _demoPath[_demoStep - 1];
            final next = _demoPath[_demoStep];
            final dy = next.latitude - prev.latitude;
            final dx = next.longitude - prev.longitude;
            if (dx != 0 || dy != 0) {
              // Calculate bearing. atan2(dx, dy) where dy is North (lat) and dx is East (lng)
              _currentHeading = math.atan2(dx, dy);
            }
            
            // Turn instruction logic
            if (_currentRouteStepIndex < _routeSteps.length - 1) {
              var nextStep = _routeSteps[_currentRouteStepIndex + 1];
              var loc = nextStep['maneuver']['location'] as List?;
              if (loc != null && loc.length >= 2) {
                var stepLatLng = LatLng(loc[1], loc[0]);
                var distToManeuver = Geolocator.distanceBetween(
                  _currentLocation!.latitude, _currentLocation!.longitude,
                  stepLatLng.latitude, stepLatLng.longitude);
                // When we are at the turn point (within 15m), transition to the FOLLOWING instruction
                if (distToManeuver < 15.0) {
                  _currentRouteStepIndex++;
                  if (_currentRouteStepIndex + 1 < _routeSteps.length) {
                    _navigationInstruction = _getInstructionFromStep(_routeSteps[_currentRouteStepIndex + 1]);
                  } else {
                    _navigationInstruction = 'Arriving at destination';
                  }
                }
              }
            }
          });
          // Use .move() instead of .animateTo() because overlapping animations
          // block the MapController from resolving the map's state, preventing tiles from loading!
          _mapController.mapController.move(_currentLocation!, 18.0);
        } else {
          // Reached end of path
          timer.cancel();
          setState(() {
            _demoStatusMessage = 'Vehicle stopped';
          });

          // Wait 3 seconds, then trigger bluetooth disconnect
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() {
              _demoStatusMessage = 'Car Bluetooth disconnected → Parking detected';
            });
            _triggerParkingEvent(_currentLocation!);
          });
        }
      });
    });
  }

  void _showParkingDiffDialog(String streetName, int oldChance, int newChance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Parking Detected', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vehicle parked on $streetName.', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            const Text('Live Occupancy Updated:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Before', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('$oldChance%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 30),
                  Column(
                    children: [
                      const Text('After Ping', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('$newChance%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerParkingEvent(LatLng location) async {
    final url = Uri.parse('http://10.0.2.2:5000/parking-event'); // 10.0.2.2 is localhost for Android Emulator
    
    final payload = {
      "event": "bluetooth_disconnect",
      "lat": location.latitude,
      "lng": location.longitude,
      "timestamp": DateTime.now().toIso8601String()
    };

    Road? parkedRoad = _recommendedRoad;
    int oldChance = 0;
    int newChance = 0;

    if (parkedRoad == null) {
      double minDistance = double.infinity;
      for (var road in _roads) {
        if (road.points.isEmpty) continue;
        final distance = Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          road.points.first.latitude,
          road.points.first.longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          parkedRoad = road;
        }
      }
    }

    if (parkedRoad != null) {
      final roadToUpdate = parkedRoad;
      oldChance = roadToUpdate.availabilityChance;
      newChance = math.max(0, oldChance - 5);

      setState(() {
        final index = _roads.indexWhere((r) => r.name == roadToUpdate.name);
        if (index != -1) {
          _roads[index] = Road(
            name: roadToUpdate.name,
            points: _roads[index].points,
            color: newChance < 50 ? Colors.orange : _roads[index].color,
            status: newChance < 50 ? 'Medium' : _roads[index].status,
            availabilityChance: newChance,
          );
          parkedRoad = _roads[index];
        }
      });
    }

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        setState(() {
          _demoStatusMessage = 'Parking event registered. Street occupancy updated.';
        });
      } else {
        setState(() {
          _demoStatusMessage = 'Error sending parking event: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('Demo HTTP Error: $e');
      setState(() {
        _demoStatusMessage = 'Simulated Parking Event Registered (Offline Mode)';
      });
    }
    
    if (parkedRoad != null && mounted) {
      _showParkingDiffDialog(parkedRoad!.name, oldChance, newChance);
    }

    // In all cases, cleanly end the demo after a few seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isDemoRunning = false;
          _demoStatusMessage = '';
          _isNavigating = false;
          _routePoints = [];
          _recommendedRoad = null;
          _destinationLocation = null;
        });
      }
    });

    // Ask feedback after a bit more time
    final String feedbackRoad = parkedRoad?.name ?? 'Unknown';
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _showSlotEaseDialog(feedbackRoad);
      }
    });
  }

  Future<void> _submitFeedback(String roadName, bool easily) async {
    final url = Uri.parse('http://10.0.2.2:5000/submit-feedback');
    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'road_name': roadName, 'found_easily': easily}),
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      print('Feedback HTTP Error: $e');
    }
  }

  void _showSlotEaseDialog(String roadName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Parking Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Did you get a slot easily?', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _submitFeedback(roadName, true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Thank you for the feedback!')),
                );
              }
            },
            child: const Text('Yes', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _submitFeedback(roadName, false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Got it! We are updating the real-time predictions.')),
                );
              }
            },
            child: const Text('No', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  // --- END DEMO MODE LOGIC ---

  // Recommendation Engine: Find the nearest 'Green' road to the search location
  void _recommendParking(LatLng target) {
    Road? bestRoad;
    double minDistance = double.infinity;

    for (var road in _roads) {
      if (road.status.contains('Available')) {
        final distance = Geolocator.distanceBetween(
          target.latitude,
          target.longitude,
          road.points[0].latitude,
          road.points[0].longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          bestRoad = road;
        }
      }
    }

    if (bestRoad != null) {
      setState(() {
        _recommendedRoad = bestRoad;
      });
      _showRecommendationDialog(bestRoad, minDistance);
    }
  }

  void _showRecommendationDialog(Road road, double distance) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Best Strategy Found!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${road.availabilityChance}% Success Chance',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Park at: ${road.name}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This street is just ${(distance / 1000).toStringAsFixed(2)} km from your destination and has high legal parking capacity.',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _getDirections(road.points[0]);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions, size: 20),
                        SizedBox(width: 8),
                        Text('Go to Street'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // Routing Logic: Use OSRM API to get path
  Future<void> _getDirections(LatLng destination) async {
    if (_currentLocation == null) {
      await _getCurrentLocation();
      if (_currentLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable location to get directions'),
            ),
          );
        }
        return;
      }
    }

    print(
      'Routing from: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
    );
    print('Routing to: ${destination.latitude}, ${destination.longitude}');

    // Destination is the ENTRY POINT of the recommended street
    final routeDest = _recommendedRoad?.points.first ?? destination;

    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${_currentLocation!.longitude},${_currentLocation!.latitude};'
        '${routeDest.longitude},${routeDest.latitude}?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20)); // Increased routing timeout

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final coordinates = route['geometry']['coordinates'] as List;

          List<dynamic> parsedSteps = [];
          String instruction = 'Follow the path';
          try {
            parsedSteps = route['legs'][0]['steps'] as List;
            // Always show the UPCOMING turn (index 1) early, rather than the "Head north" (index 0) instruction
            if (parsedSteps.length > 1) {
              instruction = _getInstructionFromStep(parsedSteps[1]);
            } else if (parsedSteps.isNotEmpty) {
              instruction = _getInstructionFromStep(parsedSteps[0]);
            }
          } catch (e) {
            print('Instruction parse error: $e');
          }

          setState(() {
            _routePoints = coordinates.map((c) => LatLng(c[1], c[0])).toList();
            _isNavigating = true; // Enter navigation mode
            _routeSteps = parsedSteps;
            _currentRouteStepIndex = 0;
            _demoRemainingDistance = (route['distance']?.toDouble() ?? 0.0);
            _navigationInstruction = instruction;
          });

          // Fit map to show both points
          _mapController.animatedFitCamera(
            cameraFit: CameraFit.coordinates(
              coordinates: [_currentLocation!, destination],
              padding: const EdgeInsets.all(80), // More padding for nav view
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No driving route found. Are you too far away?'),
            ),
          );
        }
      } else {
        print('OSRM Routing Error: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Routing service unavailable. Please try again.'),
          ),
        );
      }
    } catch (e) {
      print('Error getting directions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Routing failed: ${e.toString().contains('Timeout') ? 'Request Timed Out' : 'Check Internet Connection'}',
            ),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _searchNominatim(String query) async {
    if (query.isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(query);
    // Switched to Photon API (by Komoot) since Nominatim strictly blocks TypeAhead IPs on repeated typing
    final url =
        'https://photon.komoot.io/api/?q=$encodedQuery&lat=11.2588&lon=75.7705&limit=5';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'ParklyticsApp/1.0 (contact@example.com)'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];
        return features.map<Map<String, dynamic>>((f) {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final geometry = f['geometry'] as Map<String, dynamic>? ?? {};
          final coords = geometry['coordinates'] as List? ?? [0.0, 0.0];
          
          List<String> nameParts = [];
          if (props['name'] != null) nameParts.add(props['name'].toString());
          if (props['street'] != null) nameParts.add(props['street'].toString());
          if (props['city'] != null) nameParts.add(props['city'].toString());
          
          return {
            'display_name': nameParts.isEmpty ? 'Unknown location' : nameParts.join(', '),
            'lat': (coords[1] as num).toDouble(),
            'lon': (coords[0] as num).toDouble(),
          };
        }).toList();
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      print('Search error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Search failed: ${e.toString()}',
            ),
          ),
        );
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parklytics - Smart Parking'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: const MapOptions(
              initialCenter: _kozhikodeBeach,
              initialZoom: 15.5,
            ),
            children: [
              TileLayer(
                // Use CartoDB Positron maps as they are very reliable and less DNS-restricted by Emulators
                urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.parklytics_app',
                maxNativeZoom: 19, // Use cached tiles if needed natively without throwing
                errorImage: const NetworkImage('https://via.placeholder.com/256x256.png?text=Map+Offline'),
                keepBuffer: 3, // Preload more map chunks off-screen
                panBuffer: 1, // Preload map chunks in panning direction
              ),
              // Colored Roads Layer (Heatmap)
              // Only draw roads that have been populated by OSRM
              if (_roads.any((r) => r.points.length > 2))
                PolylineLayer(
                  polylines: _roads.where((r) => r.points.length > 2).map((r) {
                    return Polyline(
                      points: r.points,
                      color: r.color.withOpacity(0.65),
                      strokeWidth: 7.0,
                    );
                  }).toList(),
                ),
              // Direction Route Layer
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue.withOpacity(0.8),
                      strokeWidth: 8.0,
                    ),
                  ],
                ),
              // Navigation Path (Ends at entry point)
              if (_isNavigating)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 6.0,
                    ),
                  ],
                ),
              // Markers Layer
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 60,
                      height: 60,
                      child: Transform.rotate(
                        angle: _currentHeading,
                        child: _isDemoRunning
                            ? Image.asset(
                                'assets/car.png',
                                fit: BoxFit.contain,
                              )
                            : Icon(
                                _isNavigating ? Icons.navigation : Icons.circle,
                                color: Colors.blue,
                                size: _isNavigating ? 35 : 20,
                              ),
                      ),
                    ),
                  // Parking Icon at Entry point
                  if (_recommendedRoad != null)
                    Marker(
                      point: _recommendedRoad!.points.first,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue[900],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.local_parking,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  if (_destinationLocation != null && !_isNavigating)
                    Marker(
                      point: _destinationLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  if (_recommendedRoad != null && _isNavigating)
                    Marker(
                      point: _recommendedRoad!.points[0],
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.local_parking,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Navigation Overlay (Top)
          if (_isNavigating)
            Positioned(
              top: 10,
              left: 15,
              right: 15,
              child: Card(
                color: Colors.green[700],
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Row(
                    children: [
                      Icon(_getIconForModifier(_navigationInstruction), 
                           color: Colors.white, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _navigationInstruction,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Show remaining distance during demo or navigation
                            Row(
                              children: [
                                const Icon(Icons.straighten, color: Colors.white70, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _demoRemainingDistance > 1000 
                                      ? '${(_demoRemainingDistance / 1000).toStringAsFixed(1)} km left' 
                                      : '${_demoRemainingDistance.toStringAsFixed(0)} m left',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_isDemoRunning)
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isNavigating = false;
                              _isDemoRunning = false;
                              if (_demoTimer != null) _demoTimer!.cancel();
                              _routePoints = [];
                              _recommendedRoad = null;
                              _destinationLocation = null;
                              _demoStatusMessage = '';
                            });
                          },
                          icon: const Icon(Icons.stop, size: 18),
                          label: const Text('End Demo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            elevation: 0,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: () {
                            setState(() {
                              _isNavigating = false;
                              _routePoints = [];
                              _recommendedRoad = null;
                              _destinationLocation = null;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
            // Search Bar
            Positioned(
              top: 10,
              left: 15,
              right: 15,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TypeAheadField<Map<String, dynamic>>(
                  suggestionsCallback: (search) => _searchNominatim(search),
                  builder: (context, controller, focusNode) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Search destination...',
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 15),
                      ),
                    );
                  },
                  errorBuilder: (context, error) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Search failed. Check your internet connection.'),
                    );
                  },
                  emptyBuilder: (context) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No addresses found.'),
                    );
                  },
                  itemBuilder: (context, suggestion) {
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(suggestion['display_name']!),
                    );
                  },
                  onSelected: (suggestion) {
                    final lat = suggestion['lat'];
                    final lon = suggestion['lon'];
                    final target = LatLng(lat, lon);

                    setState(() {
                      _destinationLocation = target;
                      _routePoints = []; // Clear previous route
                      _isNavigating = false;
                      _recommendedRoad = null;
                    });

                    _mapController.animateTo(dest: target, zoom: 16.5);
                    _recommendParking(target);
                  },
                ),
              ),
            ),
            
            // Demo Status Overlay
            if (_demoStatusMessage.isNotEmpty)
              Positioned(
                top: 140, // Moved down to prevent overlapping with the navigation HUD
                left: 15,
                right: 15,
                child: Card(
                  color: Colors.orange[800],
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.campaign, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _demoStatusMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

          // Action Buttons
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                // Demo Mode Button (Top of stack)
                FloatingActionButton.extended(
                  onPressed: _startDemoDrive,
                  backgroundColor: _isDemoRunning ? Colors.grey : Colors.orange,
                  heroTag: 'demoBtn',
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  label: const Text(
                    'Start Demo',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                
                // Zoom In
                FloatingActionButton(
                  onPressed: () {
                    final currentZoom =
                        _mapController.mapController.camera.zoom;
                    _mapController.animateTo(
                      dest: _mapController.mapController.camera.center,
                      zoom: currentZoom + 1,
                    );
                  },
                  backgroundColor: Colors.white,
                  mini: true,
                  heroTag: 'zoomInBtn',
                  child: const Icon(Icons.add, color: Colors.black),
                ),
                const SizedBox(height: 10),
                // Zoom Out
                FloatingActionButton(
                  onPressed: () {
                    final currentZoom =
                        _mapController.mapController.camera.zoom;
                    _mapController.animateTo(
                      dest: _mapController.mapController.camera.center,
                      zoom: currentZoom - 1,
                    );
                  },
                  backgroundColor: Colors.white,
                  mini: true,
                  heroTag: 'zoomOutBtn',
                  child: const Icon(Icons.remove, color: Colors.black),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _currentLocation = _kozhikodeBeach;
                    });
                    _mapController.animateTo(dest: _kozhikodeBeach, zoom: 15.5);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Location simulated to Kozhikode Beach'),
                      ),
                    );
                  },
                  backgroundColor: Colors.blue,
                  heroTag: 'simulateBtn',
                  child: const Icon(Icons.gps_fixed, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: () => _mapController.animateTo(
                    dest: _kozhikodeBeach,
                    zoom: 15.5,
                  ),
                  backgroundColor: Colors.white,
                  heroTag: 'centerBtn',
                  child: const Icon(
                    Icons.center_focus_strong,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
