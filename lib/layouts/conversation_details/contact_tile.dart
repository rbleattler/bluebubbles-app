import 'dart:ui';

import 'package:bluebubbles/managers/method_channel_interface.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/blocs/chat_bloc.dart';
import 'package:bluebubbles/helpers/redacted_helper.dart';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/layouts/widgets/contact_avatar_widget.dart';
import 'package:bluebubbles/managers/contact_manager.dart';
import 'package:bluebubbles/managers/settings_manager.dart';
import 'package:bluebubbles/repository/models/chat.dart';
import 'package:bluebubbles/repository/models/handle.dart';
import 'package:bluebubbles/socket_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactTile extends StatefulWidget {
  final Handle handle;
  final Chat chat;
  final Function updateChat;
  final bool canBeRemoved;

  ContactTile({
    Key? key,
    required this.handle,
    required this.chat,
    required this.updateChat,
    required this.canBeRemoved,
  }) : super(key: key);

  @override
  _ContactTileState createState() => _ContactTileState();
}

class _ContactTileState extends State<ContactTile> {
  MemoryImage? contactImage;
  Contact? contact;

  @override
  void initState() {
    super.initState();

    getContact();
    fetchAvatar();
    ContactManager().stream.listen((List<String> addresses) {
      // Check if any of the addresses are members of the chat
      List<Handle> participants = widget.chat.participants;
      List<String?> handles = participants.map((Handle handle) => handle.address).toList();
      for (String addr in addresses) {
        if (handles.contains(addr)) {
          fetchAvatar();
          break;
        }
      }
    });
  }

  void fetchAvatar() async {
    MemoryImage? avatar = await loadAvatar(widget.chat, widget.handle);
    if (contactImage == null || contactImage!.bytes.length != avatar!.bytes.length) {
      contactImage = avatar;
      if (this.mounted) setState(() {});
    }
  }

  void getContact() {
    ContactManager().getCachedContact(widget.handle).then((Contact? contact) {
      if (contact != null) {
        if (this.contact == null || this.contact!.identifier != contact.identifier) {
          this.contact = contact;
          if (this.mounted) setState(() {});
        }
      }
    });
  }

  Future<void> makeCall(String phoneNumber) async {
    if (await Permission.phone.request().isGranted) {
      launch("tel://$phoneNumber");
    }
  }

  Future<void> startEmail(String email) async {
    launch('mailto:$email');
  }

  List<Item> getUniqueNumbers(Iterable<Item> numbers) {
    List<Item> phones = [];
    for (Item phone in numbers) {
      bool exists = false;
      for (Item current in phones) {
        if (cleansePhoneNumber(phone.value!) == cleansePhoneNumber(current.value!)) {
          exists = true;
          break;
        }
      }

      if (!exists) {
        phones.add(phone);
      }
    }

    return phones;
  }

  Widget _buildContactTile() {
    final bool redactedMode = SettingsManager().settings.redactedMode.value;
    final bool hideInfo = redactedMode && SettingsManager().settings.hideContactInfo.value;
    final bool generateName = redactedMode && SettingsManager().settings.generateFakeContactNames.value;
    final bool isEmail = widget.handle.address.isEmail;
    return InkWell(
      onLongPress: () {
        Clipboard.setData(new ClipboardData(text: widget.handle.address));
        showSnackbar('Copied', 'Address copied to clipboard');
      },
      onTap: () async {
        if (contact == null) {
          await MethodChannelInterface().invokeMethod("open-contact-form",
              {'address': widget.handle.address, 'addressType': widget.handle.address.isEmail ? 'email' : 'phone'});
        } else {
          await MethodChannelInterface().invokeMethod("view-contact-form", {'id': contact!.identifier});
        }
      },
      child: ListTile(
        title: (contact?.displayName != null || hideInfo || generateName)
            ? Text(
                getContactName(context, contact?.displayName ?? "", widget.handle.address, currentChat: widget.chat),
                style: Theme.of(context).textTheme.bodyText1,
              )
            : FutureBuilder<String>(
                future: formatPhoneNumber(widget.handle),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Text(
                      widget.handle.address,
                      style: Theme.of(context).textTheme.bodyText1,
                    );
                  }

                  return Text(
                    snapshot.data ?? "Unknown contact details",
                    style: Theme.of(context).textTheme.bodyText1,
                  );
                }),
        subtitle: (contact == null || hideInfo || generateName)
            ? null
            : FutureBuilder<String>(
                future: formatPhoneNumber(widget.handle),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Text(
                      widget.handle.address,
                      style: Theme.of(context).textTheme.subtitle1!.apply(fontSizeDelta: -0.5),
                    );
                  }

                  return Text(
                    snapshot.data ?? "Unknown contact details",
                    style: Theme.of(context).textTheme.subtitle1!.apply(fontSizeDelta: -0.5),
                  );
                }),
        leading: ContactAvatarWidget(
          handle: widget.handle,
          borderThickness: 0.1,
        ),
        trailing: FittedBox(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              if (isEmail)
                ButtonTheme(
                  minWidth: 1,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: CircleBorder(),
                      backgroundColor: Theme.of(context).accentColor,
                    ),
                    onPressed: () {
                      startEmail(widget.handle.address);
                    },
                    child: Icon(Icons.email, color: Theme.of(context).primaryColor, size: 20),
                  ),
                ),
              ((contact == null && !isEmail) || (contact?.phones?.length ?? 0) > 0)
                  ? ButtonTheme(
                      minWidth: 1,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          shape: CircleBorder(),
                          backgroundColor: Theme.of(context).accentColor,
                        ),
                        onLongPress: () => onPressContactTrailing(longPressed: true),
                        onPressed: () => onPressContactTrailing(),
                        child: Icon(Icons.call, color: Theme.of(context).primaryColor, size: 20),
                      ),
                    )
                  : Container()
            ],
          ),
        ),
      ),
    );
  }

  void onPressContactTrailing({bool longPressed = false}) {
    if (contact == null) {
      makeCall(widget.handle.address);
    } else {
      List<Item> phones = getUniqueNumbers(contact!.phones!);
      if (phones.length == 1) {
        makeCall(contact!.phones!.first.value!);
      } else if (widget.handle.defaultPhone != null && !longPressed) {
        makeCall(widget.handle.defaultPhone!);
      } else {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Theme.of(context).accentColor,
              title: new Text("Select a Phone Number",
                  style: TextStyle(color: Theme.of(context).textTheme.bodyText1!.color)),
              content: ObxValue<Rx<bool>>(
                  (data) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < phones.length; i++)
                            TextButton(
                              child: Text("${phones[i].value} (${phones[i].label})",
                                  style: TextStyle(color: Theme.of(context).textTheme.bodyText1!.color),
                                  textAlign: TextAlign.start),
                              onPressed: () async {
                                if (data.value) {
                                  widget.handle.defaultPhone = phones[i].value!;
                                  await widget.handle.updateDefaultPhone(phones[i].value!);
                                }
                                makeCall(phones[i].value!);
                                Navigator.of(context).pop();
                              },
                            ),
                          Row(
                            children: <Widget>[
                              SizedBox(
                                height: 48.0,
                                width: 24.0,
                                child: Checkbox(
                                  value: data.value,
                                  activeColor: Theme.of(context).primaryColor,
                                  onChanged: (bool? value) {
                                    data.value = value!;
                                  },
                                ),
                              ),
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      primary: Colors.transparent, padding: EdgeInsets.only(left: 5), elevation: 0.0),
                                  onPressed: () {
                                    data = data.toggle();
                                  },
                                  child: Text(
                                    "Remember my selection",
                                  )),
                            ],
                          ),
                          Text(
                            "Long press the call button to reset your default selection",
                            style: Theme.of(context).textTheme.subtitle1,
                          )
                        ],
                      ),
                  false.obs),
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.canBeRemoved
        ? Slidable(
            actionExtentRatio: 0.25,
            actionPane: SlidableStrechActionPane(),
            secondaryActions: <Widget>[
              IconSlideAction(
                caption: 'Remove',
                color: Colors.red,
                icon: Icons.delete,
                onTap: () async {
                  showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: SizedBox(
                            height: 40,
                            width: 40,
                            child: CircularProgressIndicator(),
                          ),
                        );
                      });

                  Map<String, dynamic> params = new Map();
                  params["identifier"] = widget.chat.guid;
                  params["address"] = widget.handle.address;
                  SocketManager().sendMessage("remove-participant", params, (response) async {
                    debugPrint("removed participant participant " + response.toString());
                    if (response["status"] == 200) {
                      Chat updatedChat = Chat.fromMap(response["data"]);
                      await updatedChat.save();
                      await ChatBloc().updateChatPosition(updatedChat);
                      Chat chatWithParticipants = await updatedChat.getParticipants();
                      debugPrint("updating chat with ${chatWithParticipants.participants.length} participants");
                      widget.updateChat(chatWithParticipants);
                      Navigator.of(context).pop();
                    }
                  });
                },
              ),
            ],
            child: _buildContactTile(),
          )
        : _buildContactTile();
  }
}
