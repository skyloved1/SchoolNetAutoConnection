import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'portal_service.dart';

const targetWifiName = '济宁学院校园网';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    title: '济宁学院校园网',
    size: Size(520, 760),
    minimumSize: Size(420, 600),
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const CampusNetworkApp());
}

class CampusNetworkApp extends StatelessWidget {
  const CampusNetworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '校园网认证',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TrayListener, WindowListener {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _detectionIntervalController = TextEditingController(text: '1');
  Timer? _wifiTimer;
  SharedPreferences? _preferences;
  String _wifiName = '正在检测...';
  String _networkIp = '';
  String _networkIpv6 = '';
  String _networkMac = '';
  String _status = '正在初始化';
  bool _busy = false;
  bool _autoLogin = true;
  bool _autoStart = false;
  bool _loopDetection = true;
  int _detectionIntervalMinutes = 1;
  bool _obscurePassword = true;
  bool _loggedIn = false;
  bool _autoLoginInProgress = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initializeTray();
    _initialize();
  }

  Future<void> _initializeTray() async {
    await trayManager.setIcon('assets/app_icon.ico');
    await trayManager.setToolTip('济宁学院校园网');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(label: '显示主窗口', onClick: (_) => _showWindow()),
          MenuItem(label: '立即检测并登录', onClick: (_) => _checkWifiAndAutoLogin()),
          MenuItem(label: '注销', onClick: (_) => _logout()),
          MenuItem.separator(),
          MenuItem(label: '退出程序', onClick: (_) => _exitApplication()),
        ],
      ),
    );
    await windowManager.setPreventClose(true);
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    if (_exiting) return;
    _exiting = true;

    // Let the native tray menu callback return before closing the window.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_showTrayMenu());
  }

  Future<void> _showTrayMenu() async {
    final wasVisible = await windowManager.isVisible();
    // Windows requires the owner window to be foreground for outside clicks
    // to dismiss TrackPopupMenu correctly.
    // ignore: deprecated_member_use
    await trayManager.popUpContextMenu(bringAppToFront: true);
    if (!wasVisible && !_exiting) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    windowManager.hide();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    _preferences = preferences;
    _usernameController.text = preferences.getString('username') ?? '';
    _passwordController.text = preferences.getString('password') ?? '';
    _autoLogin = preferences.getBool('autoLogin') ?? true;
    _autoStart = preferences.getBool('autoStart') ?? false;
    _loopDetection = preferences.getBool('loopDetection') ?? true;
    _detectionIntervalMinutes =
        preferences.getInt('detectionIntervalMinutes') ?? 1;
    if (_detectionIntervalMinutes < 1) {
      _detectionIntervalMinutes = 1;
    }
    _detectionIntervalController.text = '$_detectionIntervalMinutes';
    setState(() => _status = '等待 Wi-Fi 连接');
    await _checkWifiAndAutoLogin();
    _updateWifiTimer();
  }

  @override
  void dispose() {
    _wifiTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _usernameController.dispose();
    _passwordController.dispose();
    _detectionIntervalController.dispose();
    super.dispose();
  }

  Future<void> _checkWifiAndAutoLogin() async {
    if (_busy) return;
    try {
      final wifiName = await getCurrentWifiName();
      if (!mounted) return;
      setState(() => _wifiName = wifiName.isEmpty ? '未连接 Wi-Fi' : wifiName);
      if (wifiName == targetWifiName &&
          _autoLogin &&
          !_loggedIn &&
          _usernameController.text.trim().isNotEmpty &&
          _passwordController.text.isNotEmpty) {
        await _login(auto: true);
      } else if (wifiName != targetWifiName && !_loggedIn) {
        setState(() => _status = '未连接目标 Wi-Fi');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _wifiName = '检测失败';
          _status = 'Wi-Fi 检测失败：$error';
        });
      }
    }
  }

  Future<void> _saveCredentials() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    await preferences.setString('username', _usernameController.text.trim());
    await preferences.setString('password', _passwordController.text);
    await preferences.setBool('autoLogin', _autoLogin);
    _preferences = preferences;
  }

  Future<void> _setAutoStart(bool enabled) async {
    final previousValue = _autoStart;
    setState(() => _autoStart = enabled);
    try {
      await setWindowsStartup(enabled);
      final preferences =
          _preferences ?? await SharedPreferences.getInstance();
      await preferences.setBool('autoStart', enabled);
      _preferences = preferences;
    } catch (error) {
      if (!mounted) return;
      setState(() => _autoStart = previousValue);
      setState(() => _status = '${enabled ? '设置' : '清除'}开机启动失败：$error');
    }

  }

  Future<void> _setLoopDetection(bool enabled) async {
    final previousValue = _loopDetection;
    setState(() => _loopDetection = enabled);
    _updateWifiTimer();
    try {
      final preferences =
          _preferences ?? await SharedPreferences.getInstance();
      await preferences.setBool('loopDetection', enabled);
      _preferences = preferences;
    } catch (error) {
      if (!mounted) return;
      setState(() => _loopDetection = previousValue);
      _updateWifiTimer();
      setState(() => _status = '保存循环检测设置失败：$error');
    }
  }

  void _updateWifiTimer() {
    _wifiTimer?.cancel();
    _wifiTimer = _loopDetection
        ? Timer.periodic(
            Duration(minutes: _detectionIntervalMinutes),
            (_) => _checkWifiAndAutoLogin(),
          )
        : null;
  }

  Future<void> _saveDetectionInterval() async {
    final minutes = int.tryParse(_detectionIntervalController.text.trim());
    if (minutes == null || minutes < 1) {
      if (mounted) {
        setState(() => _status = '检测间隔必须是大于等于 1 的整数分钟');
      }
      return;
    }

    final preferences =
        _preferences ?? await SharedPreferences.getInstance();
    await preferences.setInt('detectionIntervalMinutes', minutes);
    _preferences = preferences;
    _detectionIntervalMinutes = minutes;
    _updateWifiTimer();
    if (mounted) {
      setState(() => _status = '检测间隔已设置为 $minutes 分钟');
    }
  }

  Future<void> _login({bool auto = false}) async {
    if (_busy) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _status = '请输入账号和密码');
      return;
    }
    if (auto && _autoLoginInProgress) return;
    if (auto) _autoLoginInProgress = true;
    setState(() {
      _busy = true;
      _status = auto ? '已连接目标 Wi-Fi，正在自动登录...' : '正在登录...';
    });
    try {
      await _saveCredentials();
      final networkInfo = await resolvePortalNetworkInfo();
      final networkMac = await getMacForPortalIp(networkInfo.ip);
      final result = await login(
        username: username,
        password: password,
        ip: networkInfo.ip,
        ipv6: networkInfo.ipv6,
        mac: networkMac,
      );
      final success = isLoginSuccess(result);
      if (!mounted) return;
      setState(() {
        _loggedIn = success;
        if (success) {
          _networkIp = networkInfo.ip;
          _networkIpv6 = networkInfo.ipv6;
          _networkMac = networkMac;
        }
        _status = success
            ? (auto ? '自动登录成功' : '登录成功')
            : '登录失败：${result['msg'] ?? '认证服务器未接受请求'}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '登录失败：$error');
    } finally {
      _autoLoginInProgress = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在注销...';
    });
    try {
      final result = await logout();
      final success = isLoginSuccess(result);
      if (!mounted) return;
      setState(() {
        _loggedIn = !success;
        _status = success
            ? '注销成功'
            : '注销失败：${result['msg'] ?? '认证服务器未接受请求'}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '注销失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('济宁学院校园网'),
        actions: [
          IconButton(
            tooltip: '重新检测 Wi-Fi',
            onPressed: _busy ? null : _checkWifiAndAutoLogin,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '网络状态',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('当前 Wi-Fi：$_wifiName'),
                        if (_loggedIn) ...[
                          const SizedBox(height: 6),
                          Text('IPv4：$_networkIp'),
                          const SizedBox(height: 6),
                          Text(
                            'IPv6：${_networkIpv6.isEmpty ? '未检测到全局 IPv6' : _networkIpv6}',
                          ),
                          const SizedBox(height: 6),
                          Text('MAC：$_networkMac'),
                        ],
                        const SizedBox(height: 6),
                        Text(_status),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _usernameController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('连接目标 Wi-Fi 后自动登录'),
                  subtitle: const Text('仅当 Wi-Fi 名称为“济宁学院校园网”时触发'),
                  value: _autoLogin,
                  onChanged: _busy
                      ? null
                      : (value) async {
                          setState(() => _autoLogin = value);
                          await _saveCredentials();
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开机自动启动'),
                  subtitle: const Text('关闭后会删除 Windows 启动项'),
                  value: _autoStart,
                  onChanged: _busy ? null : _setAutoStart,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('循环检测 Wi-Fi'),
                  subtitle: Text(
                    '开启后每 $_detectionIntervalMinutes 分钟检测一次并按设置自动登录',
                  ),
                  value: _loopDetection,
                  onChanged: _busy ? null : _setLoopDetection,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _detectionIntervalController,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '循环检测间隔（分钟）',
                    hintText: '请输入大于等于 1 的整数',
                    prefixIcon: Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _saveDetectionInterval(),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _saveDetectionInterval,
                  child: const Text('保存检测间隔'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _login(),
                  icon: const Icon(Icons.login),
                  label: const Text('登录'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('注销'),
                ),
                const SizedBox(height: 18),
                Text(
                  '账号和密码保存在本机应用配置中。门户使用 HTTP 通信，请注意凭据安全。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
