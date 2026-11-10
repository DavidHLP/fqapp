import 'package:flutter/foundation.dart';

import 'desktop_platform.dart';

/// 视频播放是否可用。
///
/// 视频依赖原生播放器：Android 走 ExoPlayer 平台通道（`fqapp/native_player`），
/// 桌面走 media_kit。iOS 首版没有播放器实现，直接进入播放页会抛
/// `MissingPluginException`，所以入口整体降级为「暂不支持」。
// Linux stays gated until T29/D02b verifies the native media dependency bundle.
// The desktop frame/file adapters alone do not establish playback capability.
bool get supportsVideoPlayback =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || isWindowsDesktop);
