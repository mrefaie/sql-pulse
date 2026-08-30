// SQL Pulse — driver factory. On native (desktop/mobile) it returns the real
// dart:io drivers; on web it returns the HTTP driver (backend proxy), because
// browsers cannot open raw TCP sockets.
import 'db_driver.dart';
import 'factory_native.dart' if (dart.library.html) 'factory_http.dart' as impl;

DbDriver makeDriver(String engine) => impl.makeDriver(engine);
