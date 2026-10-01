import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'web_login_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      setState(() => _error = context.l10n.pleasePasteCookie);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppController>().addAccountFromCookie(cookie);
      if (!mounted) return;
      if (!widget.firstRun) Navigator.of(context).pop();
    } on CookieFormatException {
      setState(() => _error = context.l10n.cookieMissingYlogin);
    } on CookieInvalidException {
      setState(() => _error = context.l10n.cookieInvalid);
    } on LanzouException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _webLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WebLoginPage()),
    );
    if (!mounted || ok != true) return;
    if (!widget.firstRun) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: widget.firstRun
          ? null
          : AppBar(
              title: Text(l10n.addAccount),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.firstRun) ...[
            const SizedBox(height: 24),
            Icon(
              Icons.cloud_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'LanCloud',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.lanCloudSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.howToGetCookie,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l10n.cookieSteps),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _webLogin,
            icon: const Icon(Icons.public),
            label: Text(l10n.webLoginRecommended),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.orPasteCookie,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.lanzouCookie,
              hintText: l10n.cookieHint,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_busy ? l10n.verifying : l10n.saveAndLogin),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.cookiePrivacy,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
