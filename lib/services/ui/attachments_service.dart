import 'dart:convert';
import 'dart:isolate';

import 'package:bluebubbles/models/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart' hide PlatformFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' as isg;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vcf_dart/vcf_dart.dart';
import 'package:video_thumb_getter/index.dart';
import 'package:video_thumb_getter/video_thumbnail.dart';

AttachmentsService as = Get.isRegistered<AttachmentsService>() ? Get.find<AttachmentsService>() : Get.put(AttachmentsService());

class AttachmentsService extends GetxService {

  dynamic getContent(Attachment attachment, {String? path, bool? autoDownload, Function(PlatformFile)? onComplete}) {
    if (attachment.guid?.startsWith("temp") ?? false) {
      final sendProgress = ah.attachmentProgress.firstWhereOrNull((e) => e.item1 == attachment.guid);
      if (sendProgress != null) {
        return sendProgress;
      } else {
        return attachment;
      }
    }
    if (attachment.guid?.contains("demo") ?? false) {
      return PlatformFile(
        name: attachment.transferName!,
        path: null,
        size: attachment.totalBytes ?? 0,
        bytes: Uint8List.fromList([]),
      );
    }
    if (kIsWeb || attachment.guid == null) {
      if (attachment.bytes == null && (autoDownload ?? ss.settings.autoDownload.value)) {
        return attachmentDownloader.startDownload(attachment, onComplete: onComplete);
      } else {
        return PlatformFile(
          name: attachment.transferName!,
          path: null,
          size: attachment.totalBytes ?? 0,
          bytes: attachment.bytes,
        );
      }
    }

    final pathName = path ?? attachment.path;
    if (attachmentDownloader.getController(attachment.guid) != null) {
      return attachmentDownloader.getController(attachment.guid);
    } else if (File(pathName).existsSync()) {
      return PlatformFile(
        name: attachment.transferName!,
        path: pathName,
        size: attachment.totalBytes ?? 0,
      );
    } else if (autoDownload ?? ss.settings.autoDownload.value) {
      return attachmentDownloader.startDownload(attachment, onComplete: onComplete);
    } else {
      return attachment;
    }
  }

  String createAppleLocation(double longitude, double latitude) {
    List<String> lines = [
      "BEGIN:VCARD",
      "VERSION:3.0",
      "PRODID:-//Apple Inc.//macOS 13.0//EN",
      "N:;Current Location;;;",
      "FN:Current Location",
      "URL;type=pref:https://maps.apple.com/?ll=$longitude\\,$latitude&q=$longitude\\,$latitude",
      "END:VCARD",
      "",
    ];
    return lines.join("\n");
  }

  String? parseAppleLocationUrl(String appleLocation) {
    final lines = appleLocation.split("\n");
    final line = lines.firstWhereOrNull((e) => e.contains("URL"));
    if (line != null) {
      return line.split("pref:").last;
    } else {
      return null;
    }
  }

  Contact parseAppleContact(String appleContact) {
    final contact = VCardStack.fromData(appleContact).items.first;
    final c = Contact(
      id: randomString(8),
      displayName: contact.findFirstProperty(VConstants.formattedName)?.values.firstOrNull ?? "Unknown",
      phones: contact.findFirstProperty(VConstants.phone)?.values ?? [],
      emails: contact.findFirstProperty(VConstants.email)?.values ?? [],
      structuredName: StructuredName(
        namePrefix: contact.findFirstProperty(VConstants.name)?.values.elementAtOrNull(3) ?? "",
        familyName: contact.findFirstProperty(VConstants.name)?.values.elementAtOrNull(0) ?? "",
        givenName: contact.findFirstProperty(VConstants.name)?.values.elementAtOrNull(1) ?? "",
        middleName: contact.findFirstProperty(VConstants.name)?.values.elementAtOrNull(2) ?? "",
        nameSuffix: contact.findFirstProperty(VConstants.name)?.values.elementAtOrNull(4) ?? "",
      ),
    );
    try {
      // contact_card.dart does real avatar parsing since no plugins can parse the photo correctly when the base64 is multiline
      c.avatar = (isNullOrEmpty(contact.findFirstProperty(VConstants.photo)?.values.firstOrNull)! ? null : [0]) as Uint8List?;
    } catch (_) {}
    return c;
  }

  Future<void> saveToDisk(PlatformFile file, {bool isAutoDownload = false, bool isDocument = false}) async {
    if (kIsWeb) {
      final content = base64.encode(file.bytes!);
      // create a fake download element and "click" it
      html.AnchorElement(href: "data:application/octet-stream;charset=utf-16le;base64,$content")
        ..setAttribute("download", file.name)
        ..click();
    } else if (kIsDesktop) {
      String? savePath = await FilePicker.platform.saveFile(
        initialDirectory: (await getDownloadsDirectory())?.path,
        dialogTitle: 'Choose a location to save this file',
        fileName: file.name,
        lockParentWindow: true,
        type: file.extension != null ? FileType.custom : FileType.any,
        allowedExtensions: file.extension != null ? [file.extension!] : null,
      );

      if (savePath == null) {
        return showSnackbar('Error', 'You didn\'t select a file path!');
      } else if (await File(savePath).exists()) {
        await showDialog(
          barrierDismissible: false,
          context: Get.context!,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(
                "Confirm save",
                style: context.theme.textTheme.titleLarge,
              ),
              content: Text("This file already exists.\nAre you sure you want to overwrite it?", style: context.theme.textTheme.bodyLarge),
              backgroundColor: context.theme.colorScheme.properSurface,
              actions: <Widget>[
                TextButton(
                  child: Text("No", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text("Yes", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                  onPressed: () async {
                    if (file.path != null) {
                      await File(file.path!).copy(savePath);
                    } else {
                      await File(savePath).writeAsBytes(file.bytes!);
                    }
                    Navigator.of(context).pop();
                    showSnackbar(
                      'Success',
                      'Saved attachment to $savePath!',
                      durationMs: 3000,
                      button: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Get.theme.colorScheme.surfaceVariant,
                        ),
                        onPressed: () {
                          launchUrl(Uri.file(savePath));
                        },
                        child: Text("OPEN FILE", style: TextStyle(color: Get.theme.colorScheme.onSurfaceVariant)),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      } else {
        if (file.path != null) {
          await File(file.path!).copy(savePath);
        } else {
          await File(savePath).writeAsBytes(file.bytes!);
        }
        showSnackbar(
          'Success',
          'Saved attachment to $savePath!',
          durationMs: 3000,
          button: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Get.theme.colorScheme.surfaceVariant,
            ),
            onPressed: () {
              launchUrl(Uri.file(savePath));
            },
            child: Text("OPEN FILE", style: TextStyle(color: Get.theme.colorScheme.onSurfaceVariant)),
          ),
        );
      }
    } else {
      String? savePath;

      if (ss.settings.askWhereToSave.value && !isAutoDownload) {
        savePath = await FilePicker.platform.getDirectoryPath(
          initialDirectory: ss.settings.autoSaveDocsLocation.value,
          dialogTitle: 'Choose a location to save this file',
          lockParentWindow: true,
        );
      } else {
        if (!isDocument) {
          try {
            if (file.path == null && file.bytes != null) {
              await SaverGallery.saveImage(file.bytes!, quality: 100, name: file.name, androidRelativePath: ss.settings.autoSavePicsLocation.value, androidExistNotSave: false);
            } else {
              await SaverGallery.saveFile(file: file.path!, name: file.name, androidRelativePath: ss.settings.autoSavePicsLocation.value, androidExistNotSave: false);
            }
            return showSnackbar('Success', 'Saved attachment to gallery!');
          } catch (_) {}
        }
        savePath = ss.settings.autoSaveDocsLocation.value;
      }

      if (savePath != null) {
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        await File(join(savePath, file.name)).writeAsBytes(bytes);
        showSnackbar('Success', 'Saved attachment to ${savePath.replaceAll("/storage/emulated/0/", "")} folder!');
      } else {
        return showSnackbar('Error', 'You didn\'t select a file path!');
      }
    }
  }

  Future<bool> canAutoDownload() async {
    final canSave = (await Permission.storage.request()).isGranted;
    if (!canSave) return false;
    if (!ss.settings.autoDownload.value) {
      return false;
    } else {
      if (!ss.settings.onlyWifiDownload.value) {
        return true;
      } else {
        List<ConnectivityResult> status = await (Connectivity().checkConnectivity());
        return status.contains(ConnectivityResult.wifi);
      }
    }
  }

  Future<void> redownloadAttachment(Attachment attachment, {Function(PlatformFile)? onComplete, Function()? onError}) async {
    if (!kIsWeb) {
      final file = File(attachment.path);
      final jpgFile = File(attachment.convertedPath);
      final thumbnail = File("${attachment.path}.thumbnail");
      final jpgThumbnail = File("${attachment.convertedPath}.thumbnail");

      try {
        await file.delete();
        await jpgFile.delete();
        await thumbnail.delete();
        await jpgThumbnail.delete();
      } catch(_) {}
    }

    Get.put(AttachmentDownloadController(
        attachment: attachment,
        onComplete: (file) => onComplete?.call(file),
        onError: onError
    ), tag: attachment.guid);
  }

  Future<Size> getImageSizing(String filePath, Attachment attachment) async {
    try {
      dynamic file = File(filePath);
      isg.Size size = await isg.ImageSizeGetter.getSizeAsync(AsyncInput(FileInput(file)));
      return Size(size.needRotate ? size.height.toDouble() : size.width.toDouble(), size.needRotate ? size.width.toDouble() : size.height.toDouble());
    } catch (ex) {
      return const Size(0, 0);
    }
  }

  Future<Uint8List?> getVideoThumbnail(String filePath, {bool useCachedFile = true}) async {
    final cachedFile = File("$filePath.thumbnail");
    if (useCachedFile) {
      try {
        return await cachedFile.readAsBytes();
      } catch (_) {}
    }

    final thumbnail = await VideoThumbnail.thumbnailData(
      video: filePath,
      imageFormat: ImageFormat.JPEG,
      quality: 25,
    );
    if (!isNullOrEmpty(thumbnail)!) {
      return thumbnail;
    } else {
      if (useCachedFile) {
        await cachedFile.writeAsBytes(thumbnail);
      }
      return thumbnail;
    }
  }

  Future<Uint8List?> loadAndGetProperties(Attachment attachment, {bool onlyFetchData = false, String? actualPath}) async {
    if (kIsWeb || attachment.mimeType == null || !["image", "video"].contains(attachment.mimeStart)) return null;

    final filePath = actualPath ?? attachment.path;
    File originalFile = File(filePath);
    if (kIsDesktop) {
      await originalFile.create(recursive: true);
    }

    // Handle getting heic and tiff images
    if (attachment.mimeType!.contains('image/hei') && !kIsDesktop) {
      if (await File("$filePath.jpg").exists()) {
        originalFile = File("$filePath.jpg");
      } else {
        try {
          final file = await FlutterImageCompress.compressAndGetFile(
            filePath,
            "$filePath.jpg",
            format: CompressFormat.jpeg,
            keepExif: true,
            quality: 100,
          );
          if (file == null) {
            Logger.error("Failed to compress HEIC!");
            throw Exception();
          }
          if (onlyFetchData) return await file.readAsBytes();
          originalFile = File("$filePath.jpg");
        } catch (_) {}
      }
    }
    if (attachment.mimeType!.contains('image/tif')) {
      if (await File("$filePath.jpg").exists()) {
        originalFile = File("$filePath.jpg");
      } else {
        final receivePort = ReceivePort();
        await Isolate.spawn(
            unsupportedToPngIsolate,
            IsolateData(
                PlatformFile(
                  name: randomString(8),
                  path: originalFile.path,
                  size: 0,
                ),
                receivePort.sendPort
            ),
        );
        // Get the processed image from the isolate.
        final image = await receivePort.first as Uint8List?;
        if (onlyFetchData) return image;
        if (image != null) {
          final cacheFile = File("$filePath.jpg");
          originalFile = await cacheFile.writeAsBytes(image);
        } else {
          return null;
        }
      }
    }

    Uint8List previewData = await originalFile.readAsBytes();

    if (attachment.width != null || attachment.height != null) {
      if (attachment.mimeType == "image/gif") {
        try {
          Size size = getGifDimensions(previewData);
          if (size.width != 0 && size.height != 0) {
            attachment.width = size.width.toInt();
            attachment.height = size.height.toInt();
          }
          attachment.save(null);
        } catch (ex) {
          Logger.error('Failed to get GIF dimensions! Error: ${ex.toString()}');
        }
      } else if (attachment.mimeStart == "image") {
        try {
          Size size = await getImageSizing(filePath, attachment);
          if (size.width != 0 && size.height != 0) {
            attachment.width = size.width.toInt();
            attachment.height = size.height.toInt();
          }
          attachment.save(null);
        } catch (ex) {
          Logger.error('Failed to get Image Properties! Error: ${ex.toString()}');
        }
      }
    }

    if (attachment.metadata != null) {
      // Map the EXIF to the metadata
      try {
        dynamic file = File(filePath);
        Map<String, IfdTag> exif = await readExifFromFile(file);
        attachment.metadata ??= {};
        for (MapEntry<String, IfdTag> item in exif.entries) {
          attachment.metadata![item.key] = item.value.printable;
        }
        attachment.save(null);
      } catch (ex) {
        Logger.error('Failed to read EXIF data: ${ex.toString()}');
      }
    }

    return previewData;
  }
}