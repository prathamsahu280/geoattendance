import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationTrackingService extends GetxController {
  // Supabase client
  late final SupabaseClient _supabase;
  final String _tableName = 'locations';

  // Connectivity variables
  final Connectivity _connectivity = Connectivity();
  final RxBool isConnected = false.obs;
  final Rx<ConnectivityResult> connectionType = ConnectivityResult.none.obs;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Location tracking timers
  Timer? _offlineLocationTracker;
  Timer? _onlineLocationTracker;
  Timer? _syncTimer;

  // Database
  late Database _database;
  final RxBool _isDatabaseInitialized = false.obs;

  // User info
  final String userId = 'user_123'; // Replace with actual user ID

  // Notifications
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  @override
  void onInit() async {
    super.onInit();

    // Get Supabase instance
    _supabase = Supabase.instance.client;

    // Initialize database
    await _initDatabase();

    // Initialize notifications
    await _initializeNotifications();

    // Check initial connectivity
    await _checkConnectivity();

    // Start listening for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
      onError: (error) {
        debugPrint('Connectivity subscription error: $error');
        isConnected.value = false;
      },
    );
  }

  // Initialize SQLite database
  Future<void> _initDatabase() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'location_tracking.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE locations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              latitude REAL,
              longitude REAL,
              accuracy REAL,
              date TEXT,
              time TEXT,
              synced INTEGER DEFAULT 0
            )
          ''');
        },
      );

      _isDatabaseInitialized.value = true;
      debugPrint('Database initialized successfully');
    } catch (e) {
      debugPrint('Database initialization error: $e');
    }
  }

  // Initialize notifications
  Future<void> _initializeNotifications() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'location_tracking_channel',
        'Location Tracking',
        description: 'Used for location tracking service notifications',
        importance: Importance.low,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

      await _notifications.initialize(initializationSettings);
      debugPrint('Notifications initialized successfully');
    } catch (e) {
      debugPrint('Notification initialization error: $e');
    }
  }

  // Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      debugPrint('Initial connectivity check failed: $e');
      isConnected.value = false;
    }
  }

  // Update connection status
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final result = results.first;
    connectionType.value = result;

    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.mobile:
      case ConnectivityResult.ethernet:
      case ConnectivityResult.vpn:
        isConnected.value = true;
        _handleConnectionEstablished();
        break;

      default:
        isConnected.value = false;
        _handleConnectionLost();
    }
  }

  // Handle when connection is established
  void _handleConnectionEstablished() {
    debugPrint('Internet connected via ${connectionType.value.toString().split('.').last}');

    // Show notification
    _showTrackingNotification(true);

    // Cancel offline tracker if active
    _offlineLocationTracker?.cancel();

    // Start online tracking
    _onlineLocationTracker = Timer.periodic(
        const Duration(seconds: 30),
            (_) => _trackOnlineLocation()
    );

    // Start sync process for stored locations
    _syncStoredLocations();

    // Set up periodic sync
    _syncTimer = Timer.periodic(
        const Duration(minutes: 5),
            (_) => _syncStoredLocations()
    );
  }

  // Handle when connection is lost
  void _handleConnectionLost() {
    debugPrint('Connection lost. Switching to offline mode.');

    // Show notification
    _showTrackingNotification(false);

    // Cancel online trackers
    _onlineLocationTracker?.cancel();
    _syncTimer?.cancel();

    // Start offline tracking
    _offlineLocationTracker = Timer.periodic(
        const Duration(seconds: 60),
            (_) => _trackOfflineLocation()
    );
  }

  // Show persistent notification
  Future<void> _showTrackingNotification(bool isOnline) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'location_tracking_channel',
        'Location Tracking',
        channelDescription: 'Used for location tracking service notifications',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
      );

      const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);

      await _notifications.show(
        1,
        'Location Tracking Active',
        isOnline
            ? 'Online Mode: Tracking and syncing locations'
            : 'Offline Mode: Storing locations locally',
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  // Track location when online
  Future<void> _trackOnlineLocation() async {
    if (!_isDatabaseInitialized.value) return;

    try {
      // Check and request permission if needed
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied');
        return;
      }

      // Get current position
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Format current date and time
      final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());

      // Store in database
      final int locationId = await _database.insert('locations', {
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'date': currentDate,
        'time': currentTime,
        'synced': 0,
      });

      // Try to send immediately
      await _sendLocationToSupabase(locationId, position, currentDate, currentTime);

      debugPrint('Online location recorded: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error tracking online location: $e');
    }
  }

  // Track location when offline
  Future<void> _trackOfflineLocation() async {
    if (!_isDatabaseInitialized.value) return;

    try {
      // Check and request permission if needed
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied');
        return;
      }

      // Get current position
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Format current date and time
      final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());

      // Store in database
      await _database.insert('locations', {
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'date': currentDate,
        'time': currentTime,
        'synced': 0,
      });

      debugPrint('Offline location stored: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error tracking offline location: $e');
    }
  }

  // Send a single location to Supabase
  Future<void> _sendLocationToSupabase(
      int locationId,
      Position position,
      String date,
      String time
      ) async {
    if (!isConnected.value) return;

    try {
      final Map<String, dynamic> payload = {
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'date': date,
        'time': time,
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from(_tableName)
          .insert(payload);

      // Success handling - response will be data if successful
      // Mark as synced in database
      await _database.update(
        'locations',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [locationId],
      );
      debugPrint('Location synced to Supabase successfully: $locationId');
    } catch (e) {
      debugPrint('Error sending location to Supabase: $e');
    }
  }

  // Sync all stored locations
  Future<void> _syncStoredLocations() async {
    if (!isConnected.value || !_isDatabaseInitialized.value) return;

    try {
      // Get all unsynced locations
      final List<Map<String, dynamic>> unsyncedLocations = await _database.query(
        'locations',
        where: 'synced = ?',
        whereArgs: [0],
        limit: 100, // Process in batches
      );

      if (unsyncedLocations.isEmpty) {
        debugPrint('No locations to sync');
        return;
      }

      debugPrint('Found ${unsyncedLocations.length} locations to sync');

      for (final location in unsyncedLocations) {
        try {
          final Map<String, dynamic> payload = {
            'user_id': location['user_id'],
            'latitude': location['latitude'],
            'longitude': location['longitude'],
            'accuracy': location['accuracy'],
            'date': location['date'],
            'time': location['time'],
            'created_at': DateTime.now().toIso8601String(),
          };

          await _supabase
              .from(_tableName)
              .insert(payload);

          // Mark as synced
          await _database.update(
            'locations',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [location['id']],
          );
          debugPrint('Synced location ID: ${location['id']}');

          // Small delay to prevent overwhelming the server
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('Error syncing individual location: $e');
        }
      }

      // Optionally clean up old synced data (keep last 7 days)
      await _cleanupOldData();
    } catch (e) {
      debugPrint('Error syncing stored locations: $e');
    }
  }

  // Clean up old synced data
  Future<void> _cleanupOldData() async {
    if (!_isDatabaseInitialized.value) return;

    try {
      // Calculate date 7 days ago
      final DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final String cutoffDate = DateFormat('yyyy-MM-dd').format(sevenDaysAgo);

      // Delete old synced records
      final int deleted = await _database.delete(
        'locations',
        where: 'synced = ? AND date < ?',
        whereArgs: [1, cutoffDate],
      );

      if (deleted > 0) {
        debugPrint('Cleaned up $deleted old location records');
      }
    } catch (e) {
      debugPrint('Error cleaning up old data: $e');
    }
  }

  // Get the count of stored locations
  Future<Map<String, int>> getLocationCounts() async {
    if (!_isDatabaseInitialized.value) return {'total': 0, 'synced': 0, 'unsynced': 0};

    try {
      // Get total count
      final List<Map<String, dynamic>> totalResult = await _database.rawQuery(
          'SELECT COUNT(*) as count FROM locations'
      );
      final int totalCount = Sqflite.firstIntValue(totalResult) ?? 0;

      // Get synced count
      final List<Map<String, dynamic>> syncedResult = await _database.rawQuery(
          'SELECT COUNT(*) as count FROM locations WHERE synced = 1'
      );
      final int syncedCount = Sqflite.firstIntValue(syncedResult) ?? 0;

      return {
        'total': totalCount,
        'synced': syncedCount,
        'unsynced': totalCount - syncedCount,
      };
    } catch (e) {
      debugPrint('Error getting location counts: $e');
      return {'total': 0, 'synced': 0, 'unsynced': 0};
    }
  }

  // Force sync now
  Future<bool> forceSyncNow() async {
    if (!isConnected.value) {
      return false;
    }

    try {
      await _syncStoredLocations();
      return true;
    } catch (e) {
      debugPrint('Force sync failed: $e');
      return false;
    }
  }

  @override
  void onClose() {
    // Cancel all subscriptions and timers
    _connectivitySubscription?.cancel();
    _offlineLocationTracker?.cancel();
    _onlineLocationTracker?.cancel();
    _syncTimer?.cancel();

    // Close database
    _database.close();

    // Cancel notifications
    _notifications.cancel(1);

    super.onClose();
  }
}