import 'package:flutter/material.dart';
import 'package:gailtrack/widgets/camera.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

// Import the LocationTrackingService
import 'package:gailtrack/controller/network_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  try {
    await Supabase.initialize(
        url:
            'https://oounmycsyfuqvzagiadh.supabase.co', // e.g., 'https://xyzproject.supabase.co'
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vdW5teWNzeWZ1cXZ6YWdpYWRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI0NjAzMTUsImV4cCI6MjA0ODAzNjMxNX0.cqxVFYCn7youkcsCvvIMVo4hD_HzUlgPoEEJCfckz-c',
        debug: true // Enable debug mode to see more logs
        );
    print('Supabase initialized successfully');
  } catch (e) {
    print('Error initializing Supabase: $e');
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Location Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: LocationTrackerHome(),
    );
  }
}

class LocationTrackerHome extends StatefulWidget {
  @override
  _LocationTrackerHomeState createState() => _LocationTrackerHomeState();
}

class _LocationTrackerHomeState extends State<LocationTrackerHome> {
  final LocationTrackingService _trackingService =
      Get.put(LocationTrackingService());

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request location permissions
    await [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.camera
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Tracker'),
        elevation: 2,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConnectionStatus(),
              const SizedBox(height: 20),
              _buildLocationStats(),
              const SizedBox(height: 20),
              _buildActionButtons(),
              const SizedBox(height: 20),
              _buildInfoCard(),
              const SmallCameraView()
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Obx(() {
      final isConnected = _trackingService.isConnected.value;
      final connectionType = _trackingService.connectionType.value;

      return Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection Status',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isConnected ? Icons.wifi : Icons.wifi_off,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected
                        ? 'Connected via ${connectionType.toString().split('.').last}'
                        : 'Offline',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildLocationStats() {
    return FutureBuilder<Map<String, int>>(
      future: _trackingService.getLocationCounts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            elevation: 3,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final counts = snapshot.data!;

        return Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location Statistics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _buildStatRow('Total Locations', counts['total'] ?? 0),
                _buildStatRow('Synced', counts['synced'] ?? 0, Colors.green),
                _buildStatRow(
                    'Pending Sync',
                    counts['unsynced'] ?? 0,
                    (counts['unsynced'] ?? 0) > 0
                        ? Colors.orange
                        : Colors.green),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String label, int value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Obx(() {
                  final isConnected = _trackingService.isConnected.value;

                  return ElevatedButton.icon(
                    onPressed: isConnected
                        ? () async {
                            final result =
                                await _trackingService.forceSyncNow();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result
                                    ? 'Sync completed successfully'
                                    : 'Sync failed'),
                                backgroundColor:
                                    result ? Colors.green : Colors.red,
                              ),
                            );
                            setState(() {});
                          }
                        : null,
                    icon: const Icon(Icons.sync),
                    label: const Text('Force Sync'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  );
                }),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Statistics refreshed'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Stats'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About Location Tracking',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Location Tracking Status'),
              subtitle: Obx(() {
                final isConnected = _trackingService.isConnected.value;
                return Text(
                  isConnected
                      ? 'Online Mode: Collecting every 30 seconds'
                      : 'Offline Mode: Collecting every 60 seconds',
                );
              }),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Information'),
              subtitle: Obx(() {
                final isConnected = _trackingService.isConnected.value;
                return Text(
                  isConnected
                      ? 'Auto-sync enabled (every 5 minutes)'
                      : 'Auto-sync disabled while offline',
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
