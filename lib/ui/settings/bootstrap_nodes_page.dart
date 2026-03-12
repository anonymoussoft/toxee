import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/bootstrap_nodes.dart';
import '../../util/lan_bootstrap_service.dart';
import '../../util/prefs.dart';
import '../../util/responsive_layout.dart';
import '../../i18n/app_localizations.dart';
import '../../ui/widgets/loading_shimmer.dart';

class BootstrapNodesPage extends StatefulWidget {
  const BootstrapNodesPage({
    super.key,
    this.service,
    this.onNodeSelected,
  });
  final FfiChatService? service;
  final VoidCallback? onNodeSelected;

  @override
  State<BootstrapNodesPage> createState() => _BootstrapNodesPageState();
}

class _BootstrapNodesPageState extends State<BootstrapNodesPage> {
  List<BootstrapNode> _nodes = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _testingNodes = {};
  final Map<String, String?> _testResults = {};
  final Map<String, int?> _nodeLatencies = {}; // Store latency for each node
  final Map<String, bool> _nodeTestSuccess = {}; // Track test success status

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nodes = await BootstrapNodesService.fetchNodes();
      setState(() {
        _nodes = nodes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _testNode(BootstrapNode node) async {
    setState(() {
      _testingNodes[node.publicKey] = true;
      _testResults[node.publicKey] = null;
      _nodeLatencies[node.publicKey] = null;
      _nodeTestSuccess[node.publicKey] = false;
    });
    try {
      final startTime = DateTime.now();
      bool success;
      if (widget.service != null) {
        success = await widget.service!.addBootstrapNode(
          node.ipv4,
          node.port,
          node.publicKey,
        );
      } else {
        // TCP probe fallback when service is not available (login settings)
        final result = await LanBootstrapServiceManager.probeBootstrapService(
          node.ipv4,
          node.port,
        );
        success = result != null && result.isAvailable;
      }
      final endTime = DateTime.now();
      final latency = endTime.difference(startTime).inMilliseconds;
      
      final appL10n = AppLocalizations.of(context)!;
      setState(() {
        _testResults[node.publicKey] = success ? appL10n.success : appL10n.failed;
        _nodeLatencies[node.publicKey] = success ? latency : null;
        _nodeTestSuccess[node.publicKey] = success;
      });
    } catch (e) {
      final appL10n = AppLocalizations.of(context)!;
      setState(() {
        _testResults[node.publicKey] = appL10n.error(e.toString());
        _nodeLatencies[node.publicKey] = null;
        _nodeTestSuccess[node.publicKey] = false;
      });
    } finally {
      setState(() {
        _testingNodes[node.publicKey] = false;
      });
    }
  }

  Future<void> _selectNode(BootstrapNode node) async {
    // Only allow selecting nodes that are online
    final isOnline = node.status == 'ONLINE';
    final isTestedSuccess = _nodeTestSuccess[node.publicKey] ?? false;
    final hasBeenTested = _testResults[node.publicKey] != null;
    
    final appL10n = AppLocalizations.of(context)!;
    
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appL10n.canOnlySelectOnlineNode),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    
    // Show warning if node hasn't been tested or test failed, but allow selection
    String confirmMessage = appL10n.switchNodeConfirm('${node.ipv4}:${node.port}');
    if (!hasBeenTested) {
      confirmMessage = '${appL10n.switchNodeConfirm('${node.ipv4}:${node.port}')}\n\n${appL10n.nodeNotTestedWarning}';
    } else if (!isTestedSuccess) {
      confirmMessage = '${appL10n.switchNodeConfirm('${node.ipv4}:${node.port}')}\n\n${appL10n.nodeTestFailedWarning}';
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.switchNode),
        content: Text(confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appL10n.ok),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    if (!mounted) return;

    if (widget.service != null) {
      // Full flow with service: add bootstrap node and re-login
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final success = await widget.service!.addBootstrapNode(
          node.ipv4,
          node.port,
          node.publicKey,
        );

        if (!success) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(appL10n.nodeSwitchFailed('Failed to add bootstrap node')),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
          return;
        }

        await widget.service!.login(userId: 'toxee', userSig: 'dummy_sig');

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appL10n.nodeSwitched)),
          );
          widget.onNodeSelected?.call();
          await Future.delayed(const Duration(milliseconds: 100));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appL10n.nodeSwitchFailed(e.toString())),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } else {
      // Prefs-only save when service is not available (login settings)
      try {
        await Prefs.setCurrentBootstrapNode(
          node.ipv4,
          node.port,
          node.publicKey,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appL10n.nodeSwitched)),
          );
          widget.onNodeSelected?.call();
          await Future.delayed(const Duration(milliseconds: 100));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appL10n.nodeSwitchFailed(e.toString())),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context)!;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Scaffold(
        appBar: AppBar(
          title: Text(appL10n.bootstrapNodesTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadNodes,
              tooltip: appL10n.refresh,
            ),
            SizedBox(width: ResponsiveLayout.responsiveHorizontalPadding(context)),
          ],
        ),
        body: SafeArea(
          child: _loading
            ? const LoadingShimmer(itemCount: 5, itemHeight: 56)
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadNodes,
                          child: Text(appL10n.retry),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: _loadNodes,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _nodes.length,
                      itemBuilder: (context, index) {
                        final node = _nodes[index];
                        final isOnline = node.status == 'ONLINE';
                        final isTesting = _testingNodes[node.publicKey] ?? false;
                        final testResult = _testResults[node.publicKey];
                        final latency = _nodeLatencies[node.publicKey];
                        final isTestedSuccess = _nodeTestSuccess[node.publicKey] ?? false;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isOnline ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(
                              '${node.ipv4}:${node.port}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorTheme.primaryTextColor,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (node.location != null) Text(node.location!),
                                if (node.maintainer != null) Text(AppLocalizations.of(context)!.maintainer(node.maintainer!)),
                                if (node.lastPing != null)
                                  Text(appL10n.lastPing(node.lastPing.toString())),
                                if (testResult != null) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        isTestedSuccess ? Icons.check_circle : Icons.error,
                                        size: 14,
                                        color: isTestedSuccess ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        testResult,
                                        style: TextStyle(
                                          color: isTestedSuccess ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                                        ),
                                      ),
                                      if (latency != null && isTestedSuccess) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '${latency}ms',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: isTesting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.network_check),
                                  onPressed: isTesting ? null : () => _testNode(node),
                                  tooltip: appL10n.testNode,
                                ),
                                if (isOnline)
                                  IconButton(
                                    icon: Icon(
                                      isTestedSuccess ? Icons.check_circle : Icons.arrow_forward,
                                      color: isTestedSuccess ? Theme.of(context).colorScheme.primary : null,
                                    ),
                                    onPressed: () => _selectNode(node),
                                    tooltip: AppLocalizations.of(context)!.selectThisNode,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
        ),
    );
  }
}

