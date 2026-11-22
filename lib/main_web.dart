import 'package:flutter/material.dart';

import 'features/cloud_sync/data/folio_cloud_sync_service.dart';
import 'features/mobile/folio_cross_platform_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FolioCloudSyncService.instance.ensureInitialized();
  runApp(const FolioCrossPlatformApp());
}
