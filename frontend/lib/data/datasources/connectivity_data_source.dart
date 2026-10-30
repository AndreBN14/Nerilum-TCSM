import 'package:connectivity_plus/connectivity_plus.dart';

/// La conectividad solo dispara un intento; HTTP determina si Render responde.
class ConnectivityDataSource {
  const ConnectivityDataSource();

  Stream<bool> get available => Connectivity().onConnectivityChanged.map(
    (results) => results.any((result) => result != ConnectivityResult.none),
  );
}
