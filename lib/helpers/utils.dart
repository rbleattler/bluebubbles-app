import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:bluebubbles/layouts/widgets/message_widget/group_event.dart';
import 'package:bluebubbles/repository/models/chat.dart';
import 'package:bluebubbles/repository/models/message.dart';
import 'package:blurhash_flutter/blurhash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:bluebubbles/managers/contact_manager.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/services.dart';

DateTime parseDate(dynamic value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is DateTime) return value;
  return null;
}

Size textSize(String text, TextStyle style) {
  final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr)
    ..layout(minWidth: 0, maxWidth: double.infinity);
  return textPainter.size;
}

String formatPhoneNumber(String str) {
  if (str.length < 10) return str;
  String areaCode = "";

  String numberWithoutAreaCode = str;

  if (str.startsWith("+")) {
    areaCode = "+1 ";
    numberWithoutAreaCode = str.substring(2);
  }

  String formattedPhoneNumber = areaCode +
      "(" +
      numberWithoutAreaCode.substring(0, 3) +
      ") " +
      numberWithoutAreaCode.substring(3, 6) +
      "-" +
      numberWithoutAreaCode.substring(6, numberWithoutAreaCode.length);
  return formattedPhoneNumber;
}

bool sameAddress(String address1, String address2) {
  String formattedNumber = address1.replaceAll(RegExp(r'[-() ]'), '');

  return formattedNumber == address2 ||
      "+1" + formattedNumber == address2 ||
      "+" + formattedNumber == address2;
}

getInitials(String name, String delimeter, {double size = 30}) {
  if (name == null) return Icon(Icons.person, color: Colors.white, size: size);
  List array = name.split(delimeter);
  // If there is a comma, just return the "people" icon
  if (name.contains(", ") || name.contains(" & "))
    return Icon(Icons.people, color: Colors.white, size: size);

  // If there is an & character, it's 2 people, format accordingly
  if (name.contains(' & ')) {
    List names = name.split(' & ');
    String first = names[0].startsWith("+") ? null : names[0][0];
    String second = names[1].startsWith("+") ? null : names[1][0];

    // If either first or second name is null, return the people icon
    if (first == null || second == null) {
      return Icon(Icons.people, color: Colors.white, size: size);
    } else {
      return "${first.toUpperCase()}&${second.toUpperCase()}";
    }
  }

  // If the name is a phone number, return the "person" icon
  if (name.startsWith("+") || array[0].length < 1)
    return Icon(Icons.person, color: Colors.white, size: size);

  switch (array.length) {
    case 1:
      return array[0][0].toUpperCase();
      break;
    default:
      if (array.length - 1 < 0 || array[array.length - 1].length < 1) return "";
      String first = array[0][0].toUpperCase();
      String last = array[array.length - 1][0].toUpperCase();
      if (!last.contains(new RegExp('[A-Za-z]'))) last = array[1][0];
      if (!last.contains(new RegExp('[A-Za-z]'))) last = "";
      return first + last;
  }
}

Future<Uint8List> blurHashDecode(String blurhash, int width, int height) async {
  List<int> result = await compute(blurHashDecodeCompute,
      jsonEncode({"hash": blurhash, "width": width, "height": height}));
  return Uint8List.fromList(result);
}

List<int> blurHashDecodeCompute(String data) {
  Map<String, dynamic> map = jsonDecode(data);
  Uint8List imageDataBytes = Decoder.decode(
      map["hash"],
      ((map["width"] / 200) as double).toInt(),
      ((map["height"] / 200) as double).toInt());
  return imageDataBytes.toList();
}

String randomString(int length) {
  var rand = new Random();
  var codeUnits = new List.generate(length, (index) {
    return rand.nextInt(33) + 89;
  });

  return new String.fromCharCodes(codeUnits);
}

bool sameSender(Message first, Message second) {
  return (first != null &&
      second != null &&
      (first.isFromMe && second.isFromMe ||
          (!first.isFromMe &&
              !second.isFromMe &&
              (first.handle != null &&
                  second.handle != null &&
                  first.handle.address == second.handle.address))));
}

extension DateHelpers on DateTime {
  bool isToday() {
    final now = DateTime.now();
    return now.day == this.day &&
        now.month == this.month &&
        now.year == this.year;
  }

  bool isYesterday() {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return yesterday.day == this.day &&
        yesterday.month == this.month &&
        yesterday.year == this.year;
  }

  bool isWithin(DateTime other, {int ms, int seconds, int minutes, int hours}) {
    Duration diff = this.difference(other);
    if (ms != null) {
      return diff.inMilliseconds < ms;
    } else if (seconds != null) {
      return diff.inSeconds < seconds;
    } else if (minutes != null) {
      return diff.inMinutes < minutes;
    } else if (hours != null) {
      return diff.inHours < hours;
    } else {
      throw new Exception("No timerange specified!");
    }
  }
}

String sanitizeString(String input) {
  if (input == null) return "";
  input = input.replaceAll(String.fromCharCode(65532), '');
  input = input.trim();
  return input;
}

bool isEmptyString(String input) {
  if (input == null) return true;
  input = sanitizeString(input);
  return input.isEmpty;
}

Future<String> getGroupEventText(Message message) async {
  String text = "Unknown group event";
  String handle = "You";
  if (message.handleId != null && message.handle != null)
    handle = await ContactManager().getContactTitle(message.handle.address);

  if (message.itemType == ItemTypes.participantRemoved.index) {
    text = "$handle removed someone from the conversation";
  } else if (message.itemType == ItemTypes.participantAdded.index) {
    text = "$handle added someone to the conversation";
  } else if (message.itemType == ItemTypes.participantLeft.index) {
    text = "$handle left the conversation";
  } else if (message.itemType == ItemTypes.nameChanged.index) {
    text = "$handle renamed the conversation to \"${message.groupTitle}\"";
  }

  return text;
}

Future<MemoryImage> loadAvatar(Chat chat, String address) async {
  if (chat != null) {
    // If the chat hasn't been saved, save it
    if (chat.id == null) await chat.save();

    // If there are no participants, get them
    if (chat.participants == null || chat.participants.length == 0) {
      chat = await chat.getParticipants();
    }

    // If there are no participants, return
    if (chat.participants == null) return null;

    if (address == null) {
      address = chat.participants.first.address;
    }

    // See if the update contains the current conversation
    int matchIdx = chat.participants.map((i) => i.address).toList().indexOf(address);
    if (matchIdx == -1) return null;
  }

  // Get the contact
  Contact contact = await ContactManager().getCachedContact(address);
  if (contact == null || contact.avatar.length == 0) return null;

  // Set the contact image
  // NOTE: Don't compress this. It will increase load time significantly
  // NOTE: These don't need to be compressed. They are usually already small
  return MemoryImage(contact.avatar);
}

List<RegExpMatch> parseLinks(String text) {
  RegExp exp = new RegExp(
      r'((https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}([-a-zA-Z0-9\/()@:%_.~#?&=\*\[\]]{0,})\b');
  return exp.allMatches(text).toList();
}

String getSizeString(double size) {
  int kb = 1000;
  if (size < kb) {
    return "${(size).floor()} KB";
  } else if (size < pow(kb, 2)) {
    return "${(size / kb).toStringAsFixed(1)} MB";
  } else {
    return "${(size / (pow(kb, 2))).toStringAsFixed(1)} GB";
  }
}

String cleansePhoneNumber(String input) {
  String output = input.replaceAll("-", "");
  output = output.replaceAll("(", "");
  output = output.replaceAll(")", "");
  output = output.replaceAll(" ", "");
  return output;
}

Future<dynamic> loadAsset(String path) {
  return rootBundle.load(path);
}

bool validatePhoneNumber(String value) {
  String patttern = r'^(\+?\d{1,2}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}$';
  RegExp regExp = new RegExp(patttern);
  return regExp.hasMatch(value);
}    
