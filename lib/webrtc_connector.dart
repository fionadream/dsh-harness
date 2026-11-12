import 'dart:typed_data';

import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// DataChannel 标签，与协议约定一致（protocol v1）。
const String _kChannelLabel = 'dsh';

/// 用 flutter_webrtc 实现的直连通道（LAN / P2P / TURN）。
///
/// 赋值给 `RemoteAccount.peerConnector` 后，连接会优先尝试直连；
/// 直连失败时包内会自动回落到中继，不影响可用性。
Future<RemotePeerConnection> createDshPeerConnector(
  List<RemoteIceServer> iceServers,
  RemotePeerHandlers handlers,
) async {
  final configuration = <String, dynamic>{
    'sdpSemantics': 'unified-plan',
    'iceServers': [
      for (final server in iceServers)
        {
          'urls': server.urls,
          if (server.username != null) 'username': server.username,
          if (server.credential != null) 'credential': server.credential,
        },
    ],
    if (handlers.iceTransportPolicy == RemoteIceTransportPolicy.relay)
      'iceTransportPolicy': 'relay',
  };

  final peer = await rtc.createPeerConnection(configuration);
  var closed = false;

  void closeOnce(String reason) {
    if (closed) return;
    closed = true;
    handlers.onClosed(reason);
  }

  peer.onIceCandidate = (candidate) {
    final value = candidate.candidate;
    if (value == null || value.isEmpty) return;
    handlers.onIceCandidate({
      'candidate': value,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  };

  peer.onConnectionState = (state) {
    switch (state) {
      case rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        closeOnce('ice-failed');
      case rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        closeOnce('closed');
      default:
        break;
    }
  };

  final channel = await peer.createDataChannel(
    _kChannelLabel,
    rtc.RTCDataChannelInit()..ordered = true,
  );
  channel.onDataChannelState = (state) {
    switch (state) {
      case rtc.RTCDataChannelState.RTCDataChannelOpen:
        handlers.onOpen();
      case rtc.RTCDataChannelState.RTCDataChannelClosed:
        closeOnce('datachannel-closed');
      default:
        break;
    }
  };
  channel.onMessage = (message) {
    if (!message.isBinary) return;
    final data = message.binary;
    if (data != null && data.isNotEmpty) handlers.onMessage(data);
  };

  return _DshPeerConnection(peer, channel);
}

class _DshPeerConnection implements RemotePeerConnection {
  _DshPeerConnection(this._peer, this._channel);

  final rtc.RTCPeerConnection _peer;
  final rtc.RTCDataChannel _channel;

  @override
  Future<String> createOffer(String channelLabel) async {
    final offer = await _peer.createOffer();
    await _peer.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<void> setAnswer(String sdp) async {
    await _peer.setRemoteDescription(rtc.RTCSessionDescription(sdp, 'answer'));
  }

  @override
  Future<void> addIceCandidate(Map<String, Object?> candidate) async {
    final value = candidate['candidate'];
    if (value is! String || value.isEmpty) return;
    await _peer.addCandidate(rtc.RTCIceCandidate(
      value,
      candidate['sdpMid'] as String?,
      candidate['sdpMLineIndex'] as int?,
    ));
  }

  @override
  Future<void> send(Uint8List data) async {
    await _channel.send(rtc.RTCDataChannelMessage.fromBinary(data));
  }

  @override
  Future<List<Map<String, Object?>>> stats() async {
    final out = <Map<String, Object?>>[];
    final report = await _peer.getStats();
    if (report is List) {
      for (final item in report) {
        if (item is rtc.StatsReport) {
          out.add(<String, Object?>{
            'type': item.type,
            'id': item.id,
            ...item.values,
          });
        }
      }
    }
    return out;
  }

  @override
  Future<void> close() async {
    try {
      await _channel.close();
    } catch (_) {}
    try {
      await _peer.close();
    } catch (_) {}
  }
}