import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';

/// A full-screen in-ride chat between the passenger and the driver.
///
/// Usage (from either ride progress screen):
/// ```dart
/// Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
///   rideId: widget.rideId,
///   senderId: myId,
///   senderModel: 'user',  // or 'driver'
///   otherPartyName: 'Driver',
///   receiverId: driverId, // pass the other party's ID (required before driver assigned)
/// )));
/// ```
class ChatScreen extends StatefulWidget {
  final String rideId;
  final String senderId;
  final String senderModel; // 'user' or 'driver'
  final String otherPartyName;

  /// The ID of the message recipient. When null, ChatScreen will resolve it
  /// automatically by fetching the ride from the backend.
  final String? receiverId;

  const ChatScreen({
    super.key,
    required this.rideId,
    required this.senderId,
    required this.senderModel,
    required this.otherPartyName,
    this.receiverId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _loadingHistory = true;
  bool _sending = false;
  String? _error;

  /// Resolved receiver ID — either from widget.receiverId or fetched from ride.
  String? _resolvedReceiverId;

  /// FCM foreground subscription — triggers refresh on new_chat_message
  StreamSubscription<RemoteMessage>? _fcmSub;

  /// Polling timer — refreshes history every 3 s so both sides stay in sync
  /// regardless of whether FCM delivers the push.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchHistory();
    _resolveReceiverId();
    _startPolling();

    // Also listen for FCM data messages as a faster-path refresh
    _fcmSub = FirebaseMessaging.onMessage.listen((msg) {
      final pushType = msg.data['push_type']?.toString() ?? '';
      final rideId = msg.data['rideId']?.toString() ?? '';
      if (pushType == 'new_chat_message' && rideId == widget.rideId) {
        debugPrint('[CHAT] FCM new_chat_message → refreshing history');
        _fetchHistory(scrollToBottom: true);
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _fetchHistory(scrollToBottom: true);
    });
  }

  /// Refresh history when app returns to foreground (e.g. driver switches back).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchHistory(scrollToBottom: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  /// Resolves the receiverId from widget param or by fetching the ride.
  Future<void> _resolveReceiverId() async {
    // Use widget value if already provided
    if (widget.receiverId != null && widget.receiverId!.isNotEmpty) {
      _resolvedReceiverId = widget.receiverId;
      return;
    }
    if (widget.rideId.isEmpty) return;
    try {
      final res = await ApiService.getRide(widget.rideId);
      if (!res.success) return;
      final data = ApiService.unwrapRidePayload(res.data);
      // Sender is 'user' → receiver is the driver
      // Sender is 'driver' → receiver is the user
      final id = widget.senderModel == 'user'
          ? (data['driverId']?.toString() ??
                data['assignedDriverId']?.toString() ??
                (data['driver'] is Map
                    ? (data['driver']['_id'] ?? data['driver']['id'])
                          ?.toString()
                    : null))
          : (data['userId']?.toString() ??
                data['passengerId']?.toString() ??
                (data['user'] is Map
                    ? (data['user']['_id'] ?? data['user']['id'])?.toString()
                    : null));
      if (id != null && id.isNotEmpty && id != 'null') {
        _resolvedReceiverId = id;
        debugPrint('[CHAT] Resolved receiverId=$_resolvedReceiverId');
      }
    } catch (e) {
      debugPrint('[CHAT] Could not resolve receiverId: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fcmSub?.cancel();
    _pollTimer?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  Future<void> _fetchHistory({bool scrollToBottom = false}) async {
    if (widget.rideId.isEmpty) return;
    try {
      final res = await ApiService.getChatHistory(widget.rideId);
      if (!mounted) return;
      if (res.success) {
        final raw = res.data['messages'];
        final msgs = raw is List
            ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        // Only scroll to bottom if there are new messages
        final hasNew = msgs.length != _messages.length;
        setState(() {
          _messages = msgs;
          _loadingHistory = false;
          _error = null;
        });
        if (scrollToBottom && hasNew) _scrollToBottom();
      } else {
        setState(() {
          _loadingHistory = false;
          _error = res.errorMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _messageCtrl.clear();
    await _performSend(text);
  }

  Future<void> _sendPresetMessage(String text) async {
    if (text.isEmpty || _sending) return;
    await _performSend(text);
  }

  Future<void> _performSend(String text) async {
    setState(() => _sending = true);

    // Optimistically add to list
    final optimistic = <String, dynamic>{
      '_id': 'local_${DateTime.now().millisecondsSinceEpoch}',
      'senderId': widget.senderId,
      'senderModel': widget.senderModel,
      'message': text,
      'createdAt': DateTime.now().toIso8601String(),
      'read': false,
    };
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    try {
      final res = await ApiService.sendChatMessage(
        rideId: widget.rideId,
        senderId: widget.senderId,
        senderModel: widget.senderModel,
        message: text,
        receiverId: _resolvedReceiverId,
        receiverModel: widget.senderModel == 'user' ? 'driver' : 'user',
      );
      if (!mounted) return;
      if (res.success) {
        // Replace optimistic entry with confirmed one from server
        await _fetchHistory(scrollToBottom: true);
      } else {
        // Remove optimistic and show error
        setState(() {
          _messages.removeWhere((m) => m['_id'] == optimistic['_id']);
          _error = res.errorMessage ?? 'Failed to send message.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['_id'] == optimistic['_id']);
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<String> get _quickMessages {
    if (widget.senderModel == 'user') {
      return [
        'I am at the pickup location.',
        'Where are you?',
        'I am at the main gate.',
        'Please wait for 2 minutes.',
      ];
    } else {
      return [
        'I am coming, please do not cancel the ride.',
        'I have arrived at the pickup location.',
        'Please come outside.',
        'Traffic is heavy, I might be slightly late.',
      ];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isMine(Map<String, dynamic> msg) {
    final sid = msg['senderId']?.toString() ?? '';
    final sm = msg['senderModel']?.toString() ?? '';
    return sid == widget.senderId && sm == widget.senderModel;
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.55)
        : AppColors.textGrey;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: BackButton(color: textColor),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherPartyName,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'In-ride chat',
              style: TextStyle(color: subColor, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: subColor, size: 20),
            tooltip: 'Refresh',
            onPressed: () => _fetchHistory(scrollToBottom: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Column(
        children: [
          // ── Message list ──────────────────────────────────────────────────
          Expanded(
            child: _loadingHistory
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentStrong,
                    ),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 52,
                          color: subColor.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet.\nSay hello!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _buildBubble(_messages[i], isDark, subColor),
                  ),
          ),

          // ── Error banner ──────────────────────────────────────────────────
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.accentRed.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.accentRed,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.accentRed,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.accentRed,
                    ),
                    onPressed: () => setState(() => _error = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // ── Quick Messages ────────────────────────────────────────────────
          if (!_loadingHistory)
            Container(
              height: 42,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickMessages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final msg = _quickMessages[index];
                  return ActionChip(
                    label: Text(msg, style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500)),
                    backgroundColor: isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft,
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    onPressed: () => _sendPresetMessage(msg),
                  );
                },
              ),
            ),

          // ── Input bar ─────────────────────────────────────────────────────
          SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                border: Border(top: BorderSide(color: border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceSoft
                            : AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _messageCtrl,
                        style: TextStyle(color: textColor, fontSize: 14),
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          hintStyle: TextStyle(color: subColor, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _sending
                            ? AppColors.accentStrong.withValues(alpha: 0.5)
                            : AppColors.accentStrong,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentStrong.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isDark, Color subColor) {
    final mine = _isMine(msg);
    final text = msg['message']?.toString() ?? '';
    final time = _formatTime(msg['createdAt']?.toString());
    final isOptimistic = msg['_id']?.toString().startsWith('local_') ?? false;

    final bubbleColor = mine
        ? AppColors.accentStrong
        : (isDark ? AppColors.darkSurfaceSoft : const Color(0xFFEEEEEE));
    final textColor = mine
        ? Colors.white
        : (isDark ? AppColors.darkOnSurface : AppColors.textDark);
    final timeColor = mine ? Colors.white.withValues(alpha: 0.65) : subColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.secondary.withValues(alpha: 0.2),
              child: const Icon(
                Icons.person,
                size: 14,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: TextStyle(color: timeColor, fontSize: 10),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isOptimistic
                              ? Icons.access_time_rounded
                              : Icons.done_all_rounded,
                          size: 12,
                          color: timeColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
