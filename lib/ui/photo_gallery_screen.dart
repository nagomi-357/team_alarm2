import 'package:flutter/material.dart';
import 'photo_view_screen.dart';

class PhotoGalleryScreen extends StatelessWidget {
  final List<String> photoUrls;
  final List<String?> displayNames;
  final List<String?> iconUrls;
  final int initialIndex;

  const PhotoGalleryScreen({
    super.key,
    required this.photoUrls,
    required this.displayNames,
    required this.iconUrls,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PageController(initialPage: initialIndex);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Gallery', style: TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: photoUrls.length,
        itemBuilder: (context, index) {
          final name = displayNames[index] ?? '';
          final icon = iconUrls[index];
          final url = photoUrls[index];

          return Column(
            children: [
              // Header with avatar + name (kept minimal; can be customized)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: (icon != null && icon.isNotEmpty)
                          ? NetworkImage(icon)
                          : null,
                      child: (icon == null || icon.isEmpty)
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhotoViewScreen(
                            photoUrl: url,
                            displayName: name,
                          ),
                        ),
                      );
                    },
                    child: InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

