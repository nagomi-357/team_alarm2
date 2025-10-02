import 'package:flutter/material.dart';

class PhotoViewScreen extends StatelessWidget {
  final String photoUrl;
  final String? displayName;

  const PhotoViewScreen({super.key, required this.photoUrl, this.displayName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          displayName ?? '',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(photoUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
