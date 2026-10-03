import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/network/network_proxy.dart';

/// Owns the app-lifetime triggers; NetworkProxy coalesces concurrent lookups.
class AutomaticGatewayBinding extends StatefulWidget {
  final Widget child;
  const AutomaticGatewayBinding({super.key, required this.child});

  @override
  State<AutomaticGatewayBinding> createState() =>
      _AutomaticGatewayBindingState();
}

class _AutomaticGatewayBindingState extends State<AutomaticGatewayBinding>
    with WidgetsBindingObserver {
  NetworkProxy? _proxy;
  Timer? _timer;
  Timer? _debounce;
  StreamSubscription<List<ConnectivityResult>>? _network;

  @override
  void initState() {
    super.initState();
    _proxy = context.read<NetworkProxy?>();
    if (_proxy == null) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
    _network = Connectivity().onConnectivityChanged.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(seconds: 1),
        () => unawaited(_proxy?.refreshGatewayCountry(networkChanged: true)),
      );
    }, onError: (Object _) {});
  }

  void _refresh() => unawaited(_proxy?.refreshGatewayCountry());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _debounce?.cancel();
    unawaited(_network?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
