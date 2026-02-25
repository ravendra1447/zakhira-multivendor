import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  final Map<String, DateTime> _imageLoadStartTimes = {};
  final Map<String, DateTime> _imageLoadEndTimes = {};
  final Map<String, int> _imageLoadTimes = {};
  final List<String> _slowImages = [];
  final List<String> _fastImages = [];
  
  static const int _slowThresholdMs = 1000; // 1 second
  static const int _fastThresholdMs = 300;  // 300ms

  void trackImageLoadStart(String imageUrl) {
    _imageLoadStartTimes[imageUrl] = DateTime.now();
  }

  void trackImageLoadEnd(String imageUrl) {
    final endTime = DateTime.now();
    _imageLoadEndTimes[imageUrl] = endTime;
    
    final startTime = _imageLoadStartTimes[imageUrl];
    if (startTime != null) {
      final loadTime = endTime.difference(startTime).inMilliseconds;
      _imageLoadTimes[imageUrl] = loadTime;
      
      if (loadTime > _slowThresholdMs) {
        _slowImages.add('$imageUrl (${loadTime}ms)');
      } else if (loadTime < _fastThresholdMs) {
        _fastImages.add('$imageUrl (${loadTime}ms)');
      }
      
      // Clean up old entries
      _imageLoadStartTimes.remove(imageUrl);
      _imageLoadEndTimes.remove(imageUrl);
      
      print('🖼️ Image loaded: ${loadTime}ms - $imageUrl');
    }
  }

  Map<String, dynamic> getPerformanceStats() {
    if (_imageLoadTimes.isEmpty) {
      return {
        'averageLoadTime': 0,
        'totalImages': 0,
        'slowImages': 0,
        'fastImages': 0,
        'slowThreshold': _slowThresholdMs,
        'fastThreshold': _fastThresholdMs,
      };
    }

    final totalLoadTime = _imageLoadTimes.values.reduce((a, b) => a + b);
    final averageLoadTime = totalLoadTime ~/ _imageLoadTimes.length;

    return {
      'averageLoadTime': averageLoadTime,
      'totalImages': _imageLoadTimes.length,
      'slowImages': _slowImages.length,
      'fastImages': _fastImages.length,
      'slowThreshold': _slowThresholdMs,
      'fastThreshold': _fastThresholdMs,
      'performance': _getPerformanceRating(averageLoadTime),
    };
  }

  String _getPerformanceRating(int averageLoadTime) {
    if (averageLoadTime < _fastThresholdMs) {
      return '⚡ Excellent (Like Flipkart/Alibaba)';
    } else if (averageLoadTime < _slowThresholdMs) {
      return '👍 Good';
    } else if (averageLoadTime < _slowThresholdMs * 2) {
      return '⚠️ Average';
    } else {
      return '🐌 Slow (Needs Optimization)';
    }
  }

  void clearStats() {
    _imageLoadStartTimes.clear();
    _imageLoadEndTimes.clear();
    _imageLoadTimes.clear();
    _slowImages.clear();
    _fastImages.clear();
  }

  List<String> getSlowImages() => List.from(_slowImages);
  List<String> getFastImages() => List.from(_fastImages);
}

class PerformanceOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const PerformanceOverlay({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<PerformanceOverlay> createState() => _PerformanceOverlayState();
}

class _PerformanceOverlayState extends State<PerformanceOverlay> {
  final PerformanceMonitor _monitor = PerformanceMonitor();
  Timer? _updateTimer;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _updateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        setState(() {
          _stats = _monitor.getPerformanceStats();
        });
      });
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        if (_stats.isNotEmpty)
          Positioned(
            top: 50,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🚀 Performance Monitor',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Avg Load: ${_stats['averageLoadTime']}ms',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'Images: ${_stats['totalImages']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    _stats['performance'],
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      _showDetailedStats();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showDetailedStats() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Performance Statistics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Average Load Time: ${_stats['averageLoadTime']}ms'),
              Text('Total Images: ${_stats['totalImages']}'),
              Text('Fast Images: ${_stats['fastImages']}'),
              Text('Slow Images: ${_stats['slowImages']}'),
              Text('Performance: ${_stats['performance']}'),
              const SizedBox(height: 16),
              const Text('Slow Images:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(_monitor.getSlowImages().take(5).map((img) => Text(
                img,
                style: const TextStyle(fontSize: 10, color: Colors.red),
              ))),
              const SizedBox(height: 8),
              const Text('Fast Images:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(_monitor.getFastImages().take(5).map((img) => Text(
                img,
                style: const TextStyle(fontSize: 10, color: Colors.green),
              ))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _monitor.clearStats();
              Navigator.pop(context);
            },
            child: const Text('Clear Stats'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Network connectivity monitor
class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  ConnectivityResult _connectionType = ConnectivityResult.none;
  final StreamController<ConnectivityResult> _connectivityController = 
      StreamController<ConnectivityResult>.broadcast();

  Stream<ConnectivityResult> get connectivityStream => _connectivityController.stream;

  Future<void> initialize() async {
    final connectivity = Connectivity();
    _connectionType = await connectivity.checkConnectivity();
    
    connectivity.onConnectivityChanged.listen((result) {
      _connectionType = result;
      _connectivityController.add(result);
    });
  }

  bool isSlowConnection() {
    return _connectionType == ConnectivityResult.mobile;
  }

  bool isFastConnection() {
    return _connectionType == ConnectivityResult.wifi || 
           _connectionType == ConnectivityResult.ethernet;
  }

  ConnectivityResult get currentConnection => _connectionType;
}
