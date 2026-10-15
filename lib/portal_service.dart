import 'dart:convert';
import 'dart:io';
import 'dart:math';

const portalLoginUrl = 'http://192.168.0.18:801/eportal/portal/login';
const portalLogoutUrl = 'http://192.168.0.18:801/eportal/portal/logout';
final portalPageUri = Uri.parse(portalLoginUrl).resolve('/');

Future<Map<String, dynamic>> login({
  required String username,
  required String password,
  String? ip,
  String? mac,
  String? ipv6,
  String acIp = '',
  String acName = '',
}) async {
  final random = Random();
  final callback = 'dr${1000 + random.nextInt(9000)}';
  final networkInfo = await resolvePortalNetworkInfo(
    ip: ip,
    ipv6: ipv6,
  );
  final resolvedIp = networkInfo.ip;
  final resolvedMac = mac == null || mac.trim().isEmpty
      ? await getMacForPortalIp(resolvedIp)
      : _normalizeMac(mac);

  final query = <String, String>{
    'callback': callback,
    'login_method': '1',
    'user_account': username,
    'user_password': password,
    'wlan_user_ip': resolvedIp,
    'wlan_user_ipv6': networkInfo.ipv6,
    'wlan_user_mac': resolvedMac,
    'wlan_ac_ip': acIp,
    'wlan_ac_name': acName,
    'jsVersion': '4.2.1',
    'terminal_type': '1',
    'lang': 'zh',
    'v': (500 + random.nextInt(9500)).toString(),
  };

  final uri = Uri.parse(portalLoginUrl).replace(queryParameters: query);
  final client = HttpClient();

  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'CampusNetworkDart/1.0');

    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Portal 返回 HTTP ${response.statusCode}: ${body.substring(0, min(body.length, 300))}',
        uri: uri,
      );
    }

    return _parseJsonp(body, callback);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> logout({
  String? ip,
  String? mac,
}) async {
  final random = Random();
  final callback = 'dr${1000 + random.nextInt(9000)}';
  final networkInfo = await resolvePortalNetworkInfo(ip: ip);
  final resolvedIp = networkInfo.ip;
  final resolvedMac = mac == null || mac.trim().isEmpty
      ? await getMacForPortalIp(resolvedIp)
      : _normalizeMac(mac);

  final query = <String, String>{
    'callback': callback,
    'login_method': '1',
    'wlan_user_ip': resolvedIp,
    'wlan_user_ipv6': networkInfo.ipv6,
    'wlan_user_mac': resolvedMac,
    'jsVersion': '4.2.1',
    'terminal_type': '1',
    'lang': 'zh',
    'v': (500 + random.nextInt(9500)).toString(),
  };

  final uri = Uri.parse(portalLogoutUrl).replace(queryParameters: query);
  final client = HttpClient();

  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'CampusNetworkDart/1.0');

    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Portal 返回 HTTP ${response.statusCode}: '
        '${body.substring(0, min(body.length, 300))}',
        uri: uri,
      );
    }

    return _parseJsonp(body, callback);
  } finally {
    client.close(force: true);
  }
}

class PortalNetworkInfo {
  const PortalNetworkInfo(this.ip, this.ipv6);

  final String ip;
  final String ipv6;
}

Future<PortalNetworkInfo> resolvePortalNetworkInfo({
  String? ip,
  String? ipv6,
}) async {
  if (ip != null && ip.trim().isNotEmpty) {
    final explicitIpv6 = ipv6?.trim() ?? '';
    return PortalNetworkInfo(
      ip.trim(),
      _isUsableIpv6(explicitIpv6) ? explicitIpv6 : await getLocalIPv6(),
    );
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(portalPageUri);
    request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'CampusNetworkDart/1.0');
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final pageIp = _findPageValue(body, 'v4ip') ??
          _findPageValue(body, 'v46ip') ??
          _findQueryValue(body, 'ip') ??
          _findQueryValue(body, 'wlanuserip');
      final pageIpv6 = _findPageValue(body, 'v6ip') ??
          _findQueryValue(body, 'UserV6IP') ??
          '';
      if (pageIp != null && _isUsableIpv4(pageIp)) {
        final localIp = await getLocalIPv4();
        final resolvedIp = pageIp == localIp ? pageIp : localIp;
        final resolvedIpv6 = _isUsableIpv6(pageIpv6)
            ? pageIpv6
            : await getLocalIPv6();
        return PortalNetworkInfo(
          resolvedIp,
          resolvedIpv6,
        );
      }
    }
  } finally {
    client.close(force: true);
  }

  final localIp = await getLocalIPv4();
  return PortalNetworkInfo(localIp, await getLocalIPv6());
}

String? _findPageValue(String body, String name) {
  final match = RegExp(
    "(?:var\\s+)?${RegExp.escape(name)}\\s*=\\s*['\"]([^'\"]*)['\"]",
    caseSensitive: false,
  ).firstMatch(body);
  return match?.group(1);
}

String? _findQueryValue(String body, String name) {
  final match = RegExp(
    '[?&]${RegExp.escape(name)}=([^&#"\\s]+)',
    caseSensitive: false,
  ).firstMatch(body);
  return match == null ? null : Uri.decodeComponent(match.group(1)!);
}

bool _isUsableIpv4(String value) {
  return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value) &&
      value != '000.000.000.000' &&
      value != '0.0.0.0';
}

bool _isUsableIpv6(String value) {
  if (value.isEmpty || value == '::') {
    return false;
  }
  final address = InternetAddress.tryParse(value);
  return address != null &&
      address.type == InternetAddressType.IPv6 &&
      !address.isLoopback &&
      !address.isLinkLocal &&
      !address.isMulticast &&
      !_isUniqueLocalIpv6(address);
}

bool _isUniqueLocalIpv6(InternetAddress address) {
  final bytes = address.rawAddress;
  return bytes.isNotEmpty && (bytes.first & 0xfe) == 0xfc;
}

Future<String> getLocalIPv4() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final candidates = <String>[];
  for (final networkInterface in interfaces) {
    for (final address in networkInterface.addresses) {
      final value = address.address;
      if (_isUsableIpv4(value) && !value.startsWith('169.254.')) {
        candidates.add(value);
      }
    }
  }
  if (candidates.isEmpty) {
    throw StateError('无法自动获取本机 IPv4，请确认已连接校园网。');
  }
  candidates.sort((a, b) {
    final aCampus = a.startsWith('10.') || a.startsWith('172.') ||
        a.startsWith('192.168.');
    final bCampus = b.startsWith('10.') || b.startsWith('172.') ||
        b.startsWith('192.168.');
    if (aCampus != bCampus) {
      return aCampus ? -1 : 1;
    }
    return 0;
  });
  return candidates.first;
}

Future<String> getLocalIPv6() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv6,
  );
  for (final networkInterface in interfaces) {
    for (final address in networkInterface.addresses) {
      if (_isUsableIpv6(address.address)) {
        return address.address;
      }
    }
  }
  return '';
}

Future<String> getMacForPortalIp(String portalIp) async {
  try {
    return await getMacForIp(portalIp);
  } on StateError {
    // The portal can return an address belonging to another virtual adapter.
    // Use the active local IPv4 to identify the physical campus-network NIC.
    return getMacForIp(await getLocalIPv4());
  }
}

Future<String> getMacForIp(String ip) async {
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
    throw ArgumentError.value(ip, 'ip', '不是有效的 IPv4 地址');
  }

  if (!Platform.isWindows) {
    throw UnsupportedError('当前自动获取 MAC 仅实现了 Windows');
  }

  const command = r'''
$adapter = Get-NetIPAddress -IPAddress '__IP__' -ErrorAction SilentlyContinue |
  ForEach-Object {
    Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue
  } |
  Where-Object { $_.Status -eq 'Up' -and $_.MacAddress } |
  Select-Object -First 1 -ExpandProperty MacAddress
if ($adapter) { $adapter }
''';

  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command.replaceFirst('__IP__', ip),
    ],
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      '获取网卡 MAC 失败：${result.stderr}',
      result.exitCode,
    );
  }

  final output = result.stdout.toString().trim();
  if (output.isEmpty) {
    throw StateError(
      '没有找到 IPv4 $ip 对应的已连接网卡。'
      '请确认 IP 正确，或手动传入 MAC。',
    );
  }

  return _normalizeMac(output.split(RegExp(r'\r?\n')).first.trim());
}

String _normalizeMac(String value) {
  final mac = value.replaceAll(RegExp(r'[:-]'), '').trim().toUpperCase();
  if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(mac)) {
    throw ArgumentError.value(value, 'mac', '不是有效的 MAC 地址');
  }
  return mac;
}

Map<String, dynamic> _parseJsonp(String body, String callback) {
  final pattern = RegExp(
    '^\\s*${RegExp.escape(callback)}\\s*\\((.*)\\)\\s*;?\\s*\$',
    dotAll: true,
  );
  final match = pattern.firstMatch(body);

  if (match == null) {
    throw FormatException(
      'Portal 返回的不是预期 JSONP。响应开头：'
      '${body.substring(0, min(body.length, 300))}',
    );
  }

  final decoded = jsonDecode(match.group(1)!);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('JSONP 内部不是 JSON 对象');
  }
  return decoded;
}

bool isLoginSuccess(Map<String, dynamic> result) {
  final value = result['result'];
  return value == 1 || value == '1' || value == 'ok';
}

Future<String> getCurrentWifiName() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('当前 Wi-Fi 检测仅实现了 Windows');
  }

  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'''
$profile = netsh wlan show interfaces
$match = $profile | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1
if ($match) { $match.Matches[0].Groups[1].Value.Trim() }
''',
    ],
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      '读取 Wi-Fi 名称失败：${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout.toString().trim();
}

Future<void> setWindowsStartup(bool enabled) async {
  if (!Platform.isWindows) return;

  final command = enabled
      ? "Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' "
          "-Name 'SchoolNet2' -Value '${Platform.resolvedExecutable.replaceAll("'", "''")}'"
      : "Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' "
          "-Name 'SchoolNet2' -ErrorAction SilentlyContinue";
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ],
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      '${enabled ? '设置' : '清除'}开机启动失败：${result.stderr}',
      result.exitCode,
    );
  }
}
