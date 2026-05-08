import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../providers/mood_provider.dart';
import '../../services/ai_agent_service.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<Map<String, dynamic>> _apiMessages = [];
  bool _isLoading = false;

  // Voice input — speech_to_text streams partial transcripts that we
  // pipe directly into the text field. The user can stop manually or
  // wait for the recognizer's natural pause-detection to end the session.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Voice error: ${e.errorMsg}'),
              backgroundColor: AppColors.accentRed,
            ),
          );
        },
      );
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission was denied.'),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _isListening = true);
    final locale = (await _speech.systemLocale())?.localeId ?? 'en_US';
    _speech.listen(
      localeId: locale,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _controller.text = r.recognizedWords);
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      },
    );
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = preset ?? _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (preset == null) _controller.clear();

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _isLoading = true;
    });
    _scrollToBottom();

    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString() ?? '';

    _apiMessages.add({'role': 'user', 'content': text});

    final response = await AiAgentService.chat(
      messages: _apiMessages,
      homeId: homeId,
      onToolAction: (action) {
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(role: 'assistant', content: action, isToolAction: true));
          });
          _scrollToBottom();
        }
      },
      onSetMood: (mood, confidence) {
        ref.read(moodProvider.notifier).set(mood, confidence, source: 'chatbot');
      },
    );

    _messages.removeWhere((m) => m.isToolAction);
    _apiMessages.add({'role': 'assistant', 'content': response});

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: response));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (_isListening) _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AiAgentService.isConfigured) {
      return Scaffold(
        backgroundColor: AppColors.bg(context),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smart_toy, color: AppColors.textSub(context), size: 64),
                  const SizedBox(height: 24),
                  Text("AI Assistant", style: TextStyle(color: AppColors.text(context), fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    "API key is not configured.\nCopy .env.example to .env and\nset your Anthropic API key.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSub(context), fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.smart_toy, color: AppColors.primaryBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("AI Assistant", style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("Claude Haiku", style: TextStyle(color: AppColors.textSub(context), fontSize: 12)),
                      ],
                    ),
                  ),
                  if (_messages.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: AppColors.textSub(context), size: 22),
                      onPressed: () {
                        setState(() {
                          _messages.clear();
                          _apiMessages.clear();
                        });
                      },
                      tooltip: "Clear chat",
                    ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) return _buildTypingIndicator(context);
                        return _buildMessageBubble(context, _messages[index]);
                      },
                    ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.only(left: 16, right: 8, top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                border: Border(top: BorderSide(color: AppColors.borderCol(context))),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: AppColors.text(context)),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: _isListening
                              ? "Listening — speak now…"
                              : "Ask me anything...",
                          hintStyle:
                              TextStyle(color: AppColors.textSub(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    _MicButton(
                      isListening: _isListening,
                      enabled: !_isLoading,
                      onTap: _toggleVoice,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _isLoading ? null : () => _sendMessage(),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isLoading ? AppColors.textSub(context) : AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy, color: AppColors.primaryBlue, size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            "How can I help?",
            style: TextStyle(color: AppColors.text(context), fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "I can control your devices, read sensors, and manage automations.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSub(context), fontSize: 14),
          ),
          const SizedBox(height: 32),
          _buildSuggestion(context, Icons.lightbulb_outline, "Turn on the lights"),
          const SizedBox(height: 10),
          _buildSuggestion(context, Icons.thermostat, "What's the temperature?"),
          const SizedBox(height: 10),
          _buildSuggestion(context, Icons.devices, "Show my devices"),
          const SizedBox(height: 10),
          _buildSuggestion(context, Icons.auto_awesome, "List my automations"),
        ],
      ),
    );
  }

  Widget _buildSuggestion(BuildContext context, IconData icon, String text) {
    return GestureDetector(
      onTap: () => _sendMessage(text),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryBlue, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: TextStyle(color: AppColors.text(context), fontSize: 14))),
            Icon(Icons.arrow_forward_ios, color: AppColors.textSub(context), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    final isUser = message.role == 'user';

    if (message.isToolAction) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue)),
            const SizedBox(width: 8),
            Text(message.content, style: TextStyle(color: AppColors.textSub(context), fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }

    final bubbleBg = isUser
        ? AppColors.primaryBlue
        : AppColors.card(context);
    final fgColor = isUser ? Colors.white : AppColors.text(context);

    final bubble = Flexible(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        ),
        child: GestureDetector(
          onLongPress: () async {
            HapticFeedback.mediumImpact();
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: message.content));
            if (!mounted) return;
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isUser
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2196F3), Color(0xFF00BFA5)],
                    )
                  : null,
              color: isUser ? null : bubbleBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border:
                  isUser ? null : Border.all(color: AppColors.borderCol(context)),
              boxShadow: isUser
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: isUser
                ? SelectableText(
                    message.content,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  )
                : MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: _buildMarkdownStyle(context),
                  ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _avatar(context, isUser: false),
            const SizedBox(width: 8),
          ],
          bubble,
          if (isUser) ...[
            const SizedBox(width: 8),
            _avatar(context, isUser: true),
          ],
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, {required bool isUser}) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF00BFA5)],
              )
            : LinearGradient(
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.85),
                  Colors.deepPurpleAccent.withValues(alpha: 0.85),
                ],
              ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isUser ? AppColors.primaryBlue : Colors.deepPurpleAccent)
                .withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 16,
        color: Colors.white,
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(BuildContext context) {
    final base = AppColors.text(context);
    final sub = AppColors.textSub(context);
    return MarkdownStyleSheet(
      p: TextStyle(color: base, fontSize: 14.5, height: 1.45),
      h1: TextStyle(
          color: base, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
      h2: TextStyle(
          color: base, fontSize: 16, fontWeight: FontWeight.w700, height: 1.25),
      h3: TextStyle(
          color: base, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
      strong: TextStyle(color: base, fontWeight: FontWeight.w800),
      em: TextStyle(color: base, fontStyle: FontStyle.italic),
      listBullet:
          TextStyle(color: base, fontSize: 14.5, fontWeight: FontWeight.w600),
      blockquote: TextStyle(color: sub, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: AppColors.primaryBlue, width: 3),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      code: TextStyle(
        color: AppColors.accentGreen,
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: AppColors.bg(context).withValues(alpha: 0.6),
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.bg(context),
        border: Border.all(color: AppColors.borderCol(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: const TextStyle(
        color: AppColors.primaryBlue,
        decoration: TextDecoration.underline,
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue)),
            const SizedBox(width: 10),
            Text("Thinking...", style: TextStyle(color: AppColors.textSub(context), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Mic button that pulses red while [isListening] is true. Disabled while
/// the assistant is thinking ([enabled] = false). Tap toggles listening.
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.isListening,
    required this.enabled,
    required this.onTap,
  });

  final bool isListening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isListening) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MicButton old) {
    super.didUpdateWidget(old);
    if (widget.isListening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isListening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.enabled ? widget.onTap : null,
      tooltip: widget.isListening ? 'Stop listening' : 'Speak',
      icon: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final t = _pulse.value;
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isListening
                  ? Color.lerp(AppColors.accentRed,
                      AppColors.accentRed.withValues(alpha: 0.7), t)
                  : AppColors.card(context),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isListening
                    ? AppColors.accentRed
                    : AppColors.borderCol(context),
              ),
              boxShadow: widget.isListening
                  ? [
                      BoxShadow(
                        color: AppColors.accentRed
                            .withValues(alpha: 0.45 + 0.35 * t),
                        blurRadius: 10 + 8 * t,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.isListening ? Icons.stop : Icons.mic,
              size: 18,
              color: widget.isListening
                  ? Colors.white
                  : AppColors.textSub(context),
            ),
          );
        },
      ),
    );
  }
}
