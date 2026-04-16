import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                          hintText: "Ask me anything...",
                          hintStyle: TextStyle(color: AppColors.textSub(context)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primaryBlue : AppColors.card(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppColors.borderCol(context)),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: isUser ? Colors.white : AppColors.text(context),
            fontSize: 14,
            height: 1.4,
          ),
        ),
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
