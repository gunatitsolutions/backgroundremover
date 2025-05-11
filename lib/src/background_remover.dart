// import 'dart:io';
//
// import 'package:apple_vision_selfie/apple_vision_selfie.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/rendering.dart';
// import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
// import 'package:image/image.dart' as img;
//
// class FlutterBackgroundRemover {
//   // Private constructor to prevent instantiation of the class
//   FlutterBackgroundRemover._();
//
//   // Apple Vision Selfie controller for macOS
//   static final AppleVisionSelfieController visionController =
//       AppleVisionSelfieController();
//
//   // Google ML Kit Selfie Segmentation for Android and iOS
//   static final SelfieSegmenter _segmenter = SelfieSegmenter(
//     mode: SegmenterMode.single,
//     enableRawSizeMask: true,
//   );
//
//   // Asynchronous method to remove background from an image file
//   static Future<Uint8List> removeBackground(File file) async {
//     final inputImage = InputImage.fromFile(file);
//
//     // Read image bytes in a separate isolate
//     final Uint8List bytes = await compute(_getBytes, file);
//
//     // Decode image size from bytes
//     final size = await decodeImageFromList(bytes);
//     final Uint8List image = bytes;
//
//     // Check the platform and call the appropriate background removal method
//     if (Platform.isMacOS) {
//       return await _removeBackgroundMacOS(image,
//           size: Size(size.width.toDouble(), size.height.toDouble()));
//     } else if (Platform.isAndroid || Platform.isIOS) {
//       return await _mobileRemovebackground(inputImage,
//           orignalImage: image, width: size.width, height: size.height);
//     } else {
//       throw UnimplementedError("Unsupported platform");
//     }
//   }
//
//   // Helper method to read bytes from a file
//   static Future<Uint8List> _getBytes(File file) async {
//     return await file.readAsBytes();
//   }
//
//   // Method to remove background on mobile platforms (Android and iOS)
//   static Future<Uint8List> _mobileRemovebackground(InputImage inputImage,
//       {required Uint8List orignalImage,
//       required int width,
//       required int height}) async {
//     try {
//       final mask = await _segmenter.processImage(inputImage);
//
//       final decodedImage = await removeBackgroundFromImage(
//           image: img.decodeImage(orignalImage)!,
//           segmentationMask: mask!,
//           width: width,
//           height: height);
//
//       return Uint8List.fromList(img.encodePng(decodedImage));
//     } catch (e) {
//       throw Exception("Image Cannot Remove Background");
//     }
//   }
//
//   // Method to remove background on macOS using Apple Vision
//   static Future<Uint8List> _removeBackgroundMacOS(Uint8List inputImage,
//       {required Size size}) async {
//     try {
//       final value = await visionController.processImage(SelfieSegmentationData(
//         image: inputImage,
//         imageSize: size,
//         format: PictureFormat.png,
//         quality: SelfieQuality.accurate,
//       ));
//
//       if (value != null && value[0] != null) {
//         return value[0]!;
//       } else {
//         throw Exception("Image Cannot Remove Background");
//       }
//     } catch (e) {
//       throw Exception("Image Cannot Remove Background");
//     }
//   }
//
//   // Method to remove background from an image using a segmentation mask
//   static Future<img.Image> removeBackgroundFromImage({
//     required img.Image image,
//     required SegmentationMask segmentationMask,
//     required int width,
//     required int height,
//   }) async {
//     return await compute(_removeBackgroundFromImage, {
//       'image': image,
//       'segmentationMask': segmentationMask,
//       'width': width,
//       'height': height
//     });
//   }
//
//   // Helper method to remove background from an image in a separate isolate
//   static Future<img.Image> _removeBackgroundFromImage(
//       Map<String, dynamic> input) async {
//     final img.Image image = input['image'];
//     final int height = input['height'];
//     final int width = input['width'];
//     final SegmentationMask segmentationMask = input['segmentationMask'];
//
//     // Create a new image with the background removed based on the segmentation mask
//     final newImage = img.copyResize(image,
//         width: segmentationMask.width, height: segmentationMask.height);
//
//     for (int y = 0; y < segmentationMask.height; y++) {
//       for (int x = 0; x < segmentationMask.width; x++) {
//         final int index = y * segmentationMask.width + x;
//         final double bgConfidence =
//             ((1.0 - segmentationMask.confidences[index]) * 255)
//                 .toInt()
//                 .toDouble();
//
//         // Check if the background confidence is below a threshold (e.g., 100)
//         if (bgConfidence >= 100) {
//           // If not fully transparent, copy the pixel from the original image
//           newImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 0));
//         }
//       }
//     }
//
//     return img.copyResize(newImage, width: width, height: height);
//   }
// }

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';

class FlutterBackgroundRemover {
  FlutterBackgroundRemover._();

  static final SelfieSegmenter _segmenter = SelfieSegmenter(
    mode: SegmenterMode.stream, // ✅ HIGH QUALITY mode
    enableRawSizeMask: true,
  );

  static Future<Uint8List> removeBackground(File file) async {
    final inputImage = InputImage.fromFile(file);
    final Uint8List bytes = await compute(_getBytes, file);

    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw Exception("Failed to decode image");
    }

    final segmentationMask = await _segmenter.processImage(inputImage);
    if (segmentationMask == null) {
      throw Exception("Failed to generate segmentation mask");
    }

    final result = await compute(
      _applySoftMask,
      {
        'image': decodedImage,
        'mask': segmentationMask,
      },
    );
    // ByteData? byteData = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
    // return byteData;
    return Uint8List.fromList(img.encodePng(result));
  }

  static Future<Uint8List> _getBytes(File file) async {
    return await file.readAsBytes();
  }

  /// Smooth background removal using alpha blending
  static img.Image _applySoftMask(Map<String, dynamic> args) {
    final img.Image image = args['image'];
    final SegmentationMask mask = args['mask'];

    final int origWidth = image.width;
    final int origHeight = image.height;

    final int maskWidth = mask.width;
    final int maskHeight = mask.height;

    final newImage = img.Image(width: origWidth, height: origHeight);

    for (int y = 0; y < origHeight; y++) {
      for (int x = 0; x < origWidth; x++) {
        final int mx = (x * maskWidth / origWidth).floor().clamp(0, maskWidth - 1);
        final int my = (y * maskHeight / origHeight).floor().clamp(0, maskHeight - 1);
        final int maskIndex = my * maskWidth + mx;

        final double confidence = mask.confidences[maskIndex].clamp(0.0, 1.0);
        final int alpha = (confidence * 255).toInt();

        final pixel = image.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);

        newImage.setPixelRgba(x, y, r, g, b, alpha);
      }
    }

    return newImage;
  }

  static img.Image _blendWithAlphaSoft(Map<String, dynamic> args) {
    final img.Image image = args['image'];
    final SegmentationMask mask = args['mask'];
    final int maskW = mask.width;
    final int maskH = mask.height;
    final int imgW = image.width;
    final int imgH = image.height;

    final img.Image output = img.Image(width: imgW, height: imgH);

    for (int y = 0; y < imgH; y++) {
      for (int x = 0; x < imgW; x++) {
        // Bilinear upscale the mask to match image size
        final double gx = x * (maskW / imgW);
        final double gy = y * (maskH / imgH);

        final int x0 = gx.floor().clamp(0, maskW - 1);
        final int x1 = (gx.ceil()).clamp(0, maskW - 1);
        final int y0 = gy.floor().clamp(0, maskH - 1);
        final int y1 = (gy.ceil()).clamp(0, maskH - 1);

        final double dx = gx - x0;
        final double dy = gy - y0;

        // Get four surrounding mask confidences
        final double q11 = mask.confidences[y0 * maskW + x0];
        final double q21 = mask.confidences[y0 * maskW + x1];
        final double q12 = mask.confidences[y1 * maskW + x0];
        final double q22 = mask.confidences[y1 * maskW + x1];

        // Bilinear interpolation
        final double interpConfidence = (1 - dx) * (1 - dy) * q11 +
            dx * (1 - dy) * q21 +
            (1 - dx) * dy * q12 +
            dx * dy * q22;

        final pixel = image.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);
        final a = (interpConfidence.clamp(0.0, 1.0) * 255).toInt();

        output.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return output;
  }
}
