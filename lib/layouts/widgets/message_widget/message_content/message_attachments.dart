import 'dart:io';
import 'dart:typed_data';

import 'package:bluebubbles/helpers/attachment_downloader.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/message_content/media_players/url_preview_widget.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/message_content/message_attachment.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/reactions.dart';
import 'package:bluebubbles/managers/settings_manager.dart';
import 'package:bluebubbles/repository/models/attachment.dart';
import 'package:bluebubbles/repository/models/message.dart';
import 'package:bluebubbles/socket_manager.dart';
import 'package:flutter/material.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:mime_type/mime_type.dart';
import 'package:path/path.dart';
import 'package:video_player/video_player.dart';

class SavedAttachmentData {
  List<Attachment> attachments = [];
  Map<String, Metadata> urlMetaData = {};
  Map<String, VideoPlayerController> controllers = {};
  Future<List<Attachment>> attachmentsFuture;
  Map<String, Uint8List> imageData = {};

  void dispose() {
    controllers.values.forEach((element) {
      element.dispose();
    });
  }
}

class MessageAttachments extends StatefulWidget {
  MessageAttachments(
      {Key key,
      @required this.message,
      @required this.savedAttachmentData,
      @required this.showTail,
      @required this.showHandle})
      : super(key: key);
  final Message message;
  final SavedAttachmentData savedAttachmentData;
  final bool showTail;
  final bool showHandle;

  @override
  _MessageAttachmentsState createState() => _MessageAttachmentsState();
}

class _MessageAttachmentsState extends State<MessageAttachments>
    with TickerProviderStateMixin {
  Map<String, dynamic> _attachments = new Map();

  @override
  void initState() {
    super.initState();
    if (widget.savedAttachmentData.attachments.length > 0) {
      for (Attachment attachment in widget.savedAttachmentData.attachments) {
        initForAttachment(attachment);
      }
    }
  }

  void initForAttachment(Attachment attachment) {
    String appDocPath = SettingsManager().appDocDir.path;
    String pathName =
        "$appDocPath/attachments/${attachment.guid}/${attachment.transferName}";

    /**
           * Case 1: If the file exists (we can get the type), add the file to the chat's attachments
           * Case 2: If the attachment is currently being downloaded, get the AttachmentDownloader object and add it to the chat's attachments
           * Case 3: If the attachment is a text-based one, automatically auto-download
           * Case 4: Otherwise, add the attachment, as is, meaning it needs to be downloaded
           */

    if (FileSystemEntity.typeSync(pathName) != FileSystemEntityType.notFound) {
      _attachments[attachment.guid] = File(pathName);
    } else if (SocketManager()
        .attachmentDownloaders
        .containsKey(attachment.guid)) {
      _attachments[attachment.guid] =
          SocketManager().attachmentDownloaders[attachment.guid];
    } else if (attachment.mimeType == null ||
        attachment.mimeType.startsWith("text/")) {
      AttachmentDownloader downloader =
          new AttachmentDownloader(attachment, widget.message);
      _attachments[attachment.guid] = downloader;
    } else {
      _attachments[attachment.guid] = attachment;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.savedAttachmentData.attachmentsFuture == null &&
        widget.savedAttachmentData.attachments.length == 0) {
      widget.savedAttachmentData.attachmentsFuture =
          Message.getAttachments(widget.message);
    }
    return FutureBuilder(
      builder: (context, snapshot) {
        if (snapshot.hasData ||
            widget.savedAttachmentData.attachments.length > 0) {
          if (widget.savedAttachmentData.attachments.length == 0)
            widget.savedAttachmentData.attachments = snapshot.data;

          for (Attachment attachment
              in widget.savedAttachmentData.attachments) {
            initForAttachment(attachment);
          }
          return _buildActualWidget();
        } else {
          return Container();
        }
      },
      future: widget.savedAttachmentData.attachmentsFuture,
    );
  }

  Widget _buildActualWidget() {
    return Column(
      mainAxisAlignment: widget.message.isFromMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Stack(
          alignment:
              widget.message.isFromMe ? Alignment.topRight : Alignment.topLeft,
          children: <Widget>[
            Padding(
              padding:
                  widget.message.hasReactions && widget.message.hasAttachments
                      ? EdgeInsets.only(
                          right: !widget.message.isFromMe ? 16.0 : 10.0,
                          bottom: 10.0,
                          left: widget.message.isFromMe ? 16.0 : 10.0,
                          top: 24.0,
                        )
                      : EdgeInsets.symmetric(
                          horizontal: (widget.showTail ||
                                  !widget.showHandle ||
                                  widget.message.isFromMe)
                              ? 10.0
                              : 45.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildAttachments(),
              )
            ),
            widget.message.hasReactions
                ? Reactions(
                    message: widget.message,
                  )
                : Container(),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildAttachments() {
    List<Widget> content = <Widget>[];
    List<Attachment> nullMimeTypeAttachments = <Attachment>[];

    for (Attachment attachment in widget.savedAttachmentData.attachments) {
      if (attachment.mimeType == null) {
        nullMimeTypeAttachments.add(attachment);
      } else {
        content.add(
          MessageAttachment(
            message: widget.message,
            attachment: attachment,
            content: _attachments[attachment.guid],
            updateAttachment: () {
              initForAttachment(attachment);
            },
            savedAttachmentData: widget.savedAttachmentData,
          ),
        );
      }
    }
    if (nullMimeTypeAttachments.length != 0)
      content.add(
        UrlPreviewWidget(
          linkPreviews: nullMimeTypeAttachments,
          message: widget.message,
          savedAttachmentData: widget.savedAttachmentData,
        ),
      );

    return content;
  }

  String getMimeType(File attachment) {
    String mimeType = mime(basename(attachment.path));
    if (mimeType == null) return "";
    mimeType = mimeType.substring(0, mimeType.indexOf("/"));
    return mimeType;
  }
}
