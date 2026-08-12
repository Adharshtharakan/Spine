import 'package:flutter/material.dart';

/// The prototype's `.tap:active { transform: scale(0.96) }` — every interactive
/// element in Spine dips slightly under the finger instead of splashing.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.enabled = true,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;
  final String? semanticLabel;
  final HitTestBehavior behavior;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  void _set(bool value) {
    if (!_active || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: _active ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1 : 0.4,
            duration: const Duration(milliseconds: 120),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
