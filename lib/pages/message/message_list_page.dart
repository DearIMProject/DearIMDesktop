import 'dart:async';
import 'dart:convert';

import 'package:desktop_im/components/common/common_theme.dart';
import 'package:desktop_im/components/ui/add_keyboard.dart';
import 'package:desktop_im/components/ui/emj_keyboard.dart';
import 'package:desktop_im/components/ui/message_input.dart';

import 'package:desktop_im/log/log.dart';
import 'package:desktop_im/models/fileBean.dart';
import 'package:desktop_im/models/message/message.dart';
import 'package:desktop_im/models/message/message_enum.dart';
import 'package:desktop_im/models/message/send_success_model.dart';

import 'package:desktop_im/models/user.dart';
import 'package:desktop_im/network/request.dart';
import 'package:desktop_im/pages/base_page.dart';
import 'package:desktop_im/pages/datas/im_database.dart';
import 'package:desktop_im/pages/message/message_item.dart';
import 'package:desktop_im/pages/message/services/message_service.dart';
import 'package:desktop_im/tcpconnect/connect/im_client.dart';
import 'package:desktop_im/tcpconnect/connect/message_factory.dart';
import 'package:desktop_im/user/user_manager.dart';
import 'package:desktop_im/utils/file_utils.dart';
import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:tuple/tuple.dart';

class MessageListPage extends BasePage {
  const MessageListPage({super.key, super.params});

  @override
  State<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends State<MessageListPage>
    implements IMDatabaseListener {
  User? chatUser;
  MessageService service = MessageService();

  User? user = UserManager.getInstance().user;
  List<Message> messages = [];
  IMDatabase database = IMDatabase.getInstance();
  IMClient client = IMClient.getInstance();
  @override
  DatabaseCompleteCallback? completeCallback;

  @override
  DatabaseCompleteCallback? dataChangeCallback;

  @override
  DatabaseUnreadMessageNumberChange? unreadMessageNumberChange;
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _keyboardOpenedListener;
  final KeyboardVisibilityController _keyboardVisibilityController =
      KeyboardVisibilityController();
  @override
  void dispose() {
    database.removeListener(this);
    _scrollController.dispose();
    super.dispose();
  }

  _MessageListPageState() {
    database.addListener(this);
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection !=
          ScrollDirection.idle) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }
// 滚动到底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    }
  }

  @override
  void initState() {
    super.initState();
    if (messages.isNotEmpty) {
      return;
    }
    chatUser = widget.params?["user"];
    if (chatUser == null) {
      throw Exception("chatUser is null");
    }
    if (user == null) {
      throw Exception("user is null");
    }
    if (messages.isEmpty) {
      messages.addAll(database.getChatMessages(chatUser!.userId));
    }
    dataChangeCallback ??= () {
      messages = [];
      messages.addAll(database.getChatMessages(chatUser!.userId));
      // configSendReadMessage();
      Log.debug("收到消息发生了变化 $messages");
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          setState(() {});
          _scrollToBottom();
        },
      );
    };

    // 滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    _keyboardOpenedListener = () {
      _scrollToBottom();
    };
    _keyboardVisibilityController.onChange.listen((bool visible) {
      if (visible) {
        setState(() {
          addVisiable = false;
          emjVisiable = false;
        });
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 300))
              .then((value) => _keyboardOpenedListener());
        });
      }
    });
  }

  bool hasSend = false;
  bool addVisiable = false;
  bool emjVisiable = false;
  @override
  Widget build(BuildContext context) {
    // Log.debug("chatUser = $chatUser");

    return Scaffold(
      appBar: AppBar(
        title: titleFontText(kTitleColor, chatUser?.username ?? ""),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
              child: pagePadding(
            ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (BuildContext context, int index) {
                Message message = messages[index];
                return (message.isChatMessage)
                    ? MesssageItemView(
                        message: message,
                        icon: message.isOwner ? user!.icon : chatUser!.icon)
                    : null;
              },
            ),
          )),
          MessageInputView(
            sendCallback: (text) {
              if (text.isNotEmpty) {
                sendAMessge(text);
                setState(() {});
              }
            },
            addClickCallback: () {
              setState(() {
                FocusScope.of(context).unfocus();
                addVisiable = !addVisiable;
                emjVisiable = false;
                Future.delayed(const Duration(milliseconds: 300),
                    () => {_scrollToBottom()});
              });
            },
            emjClickCallback: () {
              setState(() {
                FocusScope.of(context).unfocus();
                emjVisiable = !emjVisiable;
                addVisiable = false;
                Future.delayed(const Duration(milliseconds: 300),
                    () => {_scrollToBottom()});
              });
            },
          ),
          Visibility(
            visible: addVisiable,
            child: AddKeyboard(
              imageCallback: (filePath) {
                sendAImage(filePath);
              },
            ),
          ),
          Visibility(
            visible: emjVisiable,
            child: const EmjKeyboard(),
          ),
          const SafeArea(
              child: SizedBox(
            height: 0,
          )),
        ],
      ),
    );
  }

  void sendAMessge(String text) {
    Message message = MessageFactory.messageFromType(MessageType.TEXT);
    message.fromId = user!.userId;
    message.fromEntity = MessageEntityType.USER;
    message.toId = chatUser!.userId;
    message.toEntity = MessageEntityType.USER;
    message.content = text;
    client.sendMessage(message);
    messages.add(message);
    Log.debug("发送了一个消息：$message");
  }

  void sendAImage(String filePath) {
    // 先上传图片，上传成功后发送这个图片
    // 先添加一个message，然后上传图片，

    uploadImage(filePath).then((fileBean) {
      Log.debug(fileBean.toString());
      if (fileBean != null) {
        sendAImageMessage(fileBean);
      } else {
        //TODO: wmy 重试
      }
    });
  }

  Future<void> addAImageMessageBeforeSend(String filePath) async {
    Message message = MessageFactory.messageFromType(MessageType.PICTURE);
    message.fromId = user!.userId;
    message.fromEntity = MessageEntityType.USER;
    message.toId = chatUser!.userId;
    message.toEntity = MessageEntityType.USER;
    MultipartFile file =
        await MultipartFile.fromFile(filePath, filename: filePath);
    Tuple3<int, int, String> imageDesc = await FileUtils.imageWidth(file);
    FileBean fileBean = FileBean(
        fileId: 0,
        fileMd5: imageDesc.item3,
        filePath: filePath,
        width: imageDesc.item1,
        height: imageDesc.item2);
    Log.debug(fileBean.toJson().toString());
    String content = jsonEncode(fileBean.toJson());
    message.content = content;
    client.sendMessage(message);
    messages.add(message);
    Log.debug("发送了一个消息：$message");
  }

  void sendAImageMessage(FileBean fileBean) {
    Message message = MessageFactory.messageFromType(MessageType.PICTURE);
    message.fromId = user!.userId;
    message.fromEntity = MessageEntityType.USER;
    message.toId = chatUser!.userId;
    message.toEntity = MessageEntityType.USER;
    Log.debug(fileBean.toJson().toString());
    String content = jsonEncode(fileBean.toJson());
    message.content = content;
    client.sendMessage(message);
    messages.add(message);
    Log.debug("发送了一个消息：$message");
  }

  Future<FileBean?> uploadImage(String filePath) {
    Completer<FileBean?> completer = Completer();
    service.uploadFile(filePath, ImageType.image).then((fileBean) {
      completer.complete(fileBean);
    });
    return completer.future;
  }
}
