//(必要)pickers/image_pick.dart　(画像ピッカー)

import 'dart:io';
import 'package:image_picker/image_picker.dart';
class ImagePick {
  static final _picker = ImagePicker();
  static Future<File?> pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    return x!=null ? File(x.path) : null;
  }
  static Future<File?> pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    return x!=null ? File(x.path) : null;
  }
}

