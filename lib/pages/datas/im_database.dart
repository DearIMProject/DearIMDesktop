import 'package:desktop_im/log/log.dart';
import 'package:desktop_im/models/message/message.dart';
import 'package:desktop_im/models/user.dart';
import 'package:desktop_im/pages/datas/db_message.dart';
import 'package:desktop_im/pages/datas/db_user.dart';
import 'package:desktop_im/tcpconnect/connect/im_client.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:path_provider/path_provider.dart';

class IMDatabase implements IMClientListener {
  // 未读消息
  int _badgeValue = 0;
  int get badgeValue => _badgeValue;

  @override
  IMClientReceiveMessageCallback? messageCallback;
  final DBMessage _dbMessage = DBMessage();
  final DBUser _dbUser = DBUser();
  void install(String boxName) {
    _dbMessage.install(boxName);
    _dbUser.install(boxName);
    messageCallback = (message) {
      addMessage(message);
    };
  }

  Future<void> init() async {
    Log.debug("database init");
    WidgetsFlutterBinding.ensureInitialized();
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
    await Hive.initFlutter();
    Hive.registerAdapter(UserAdapter());
  }

  void uninstall() {
    _dbMessage.uninstall();
    _dbUser.uninstall();
  }

  // 添加一条消息
  void addMessage(Message message) {
    _dbMessage.addItem(message);
    _badgeValue++;
  }

// 获取消息列表最新的时间戳
  int getMaxTimestamp() {
    return _dbMessage.maxTimestamp();
  }
}
