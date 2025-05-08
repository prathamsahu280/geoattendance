import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class SmallCameraView extends StatefulWidget {
  const SmallCameraView({super.key});

  @override
  State<SmallCameraView> createState() => _SmallCameraViewState();
}

class _SmallCameraViewState extends State<SmallCameraView> {
  CameraController? _controller;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.first;

    _controller = CameraController(camera, ResolutionPreset.low);
    _initFuture = _controller!.initialize();
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const SizedBox(
        width: 100,
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          );
        } else {
          return const SizedBox(
            width: 100,
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }
}
