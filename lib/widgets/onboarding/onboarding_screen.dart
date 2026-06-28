import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_service_profile.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/settings_service.dart';
/// 3-step first-run guide: welcome → pick library root → choose AI protocol.
///
/// Each step gets its own radial-gradient backdrop (blue / teal / violet)
/// matching the design mockups. The flow can be skipped at any step; finishing
/// flips `SettingsService.onboardingSeen` and the host app swaps in
/// `HomeScreen`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0 / 1 / 2
  String? _pickedRoot;
  AiProviderType? _pickedProvider;

  static const _blue = Color(0xFF3B6FF5);
  static const _teal = Color(0xFF22C9A9);
  static const _violet = Color(0xFF8B5CF6);

  Color get _accent => switch (_step) {
        0 => _blue,
        1 => _teal,
        _ => _violet,
      };

  Future<void> _finish() async {
    // Grab everything synchronously before awaiting; the host swaps screens
    // when onboardingSeen flips, so `mounted` may be false after the awaits.
    final settings = context.read<SettingsService>();
    final profiles = context.read<AiProfilesService>();
    final ai = context.read<AiService>();
    final browser = context.read<FileBrowserService>();
    final openAiName = AppLocalizations.of(context)!.onboardingProviderOpenAi;

    if (_pickedRoot != null) {
      browser.setCurrentDirectory(_pickedRoot);
      await settings.pushRecent(_pickedRoot!);
    }
    if (_pickedProvider != null) {
      final profile = AiServiceProfile.create(
        provider: _pickedProvider!,
        name: _pickedProvider == AiProviderType.googleGenAi
            ? 'Google GenAI'
            : openAiName,
      );
      await profiles.add(profile);
      ai.updateConfig(profiles.aiConfig);
    }
    await settings.setOnboardingSeen(true);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && mounted) {
      setState(() {
        _pickedRoot = dir;
        _step = 2;
      });
    }
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step = _step + 1);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFF06070D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Per-step radial backdrop, cross-faded between steps.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            child: Container(
              key: ValueKey(_step),
              decoration: BoxDecoration(gradient: _backdropFor(_step)),
            ),
          ),
          // Faint vignette to deepen the corners like the mockups.
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
          ),
          // Step indicator (top-right).
          Positioned(
            top: 28,
            right: 32,
            child: Text(
              l10n.onboardingStepCounter(_step + 1, 3),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(_step),
              ),
            ),
          ),
          // Bottom page-dots.
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Center(child: _PageDots(active: _step, accent: _accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _StepWelcome(
          onSkip: _finish,
          onStart: _next,
        );
      case 1:
        return _StepRoot(
          pickedPath: _pickedRoot,
          onPick: _pickFolder,
          onSkip: _finish,
        );
      case 2:
      default:
        return _StepAi(
          picked: _pickedProvider,
          onPick: (p) => setState(() => _pickedProvider = p),
          onLater: _finish,
          onEnter: _finish,
        );
    }
  }

  Gradient _backdropFor(int step) {
    return switch (step) {
      0 => const RadialGradient(
          center: Alignment(-0.2, -0.4),
          radius: 1.1,
          colors: [Color(0xFF1F2161), Color(0xFF12122E), Color(0xFF07081A)],
          stops: [0.0, 0.55, 1.0],
        ),
      1 => const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.2,
          colors: [Color(0xFF124441), Color(0xFF0A2730), Color(0xFF05121E)],
          stops: [0.0, 0.5, 1.0],
        ),
      _ => const RadialGradient(
          center: Alignment(0.2, -0.4),
          radius: 1.2,
          colors: [Color(0xFF35216A), Color(0xFF1B143E), Color(0xFF080820)],
          stops: [0.0, 0.55, 1.0],
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Step 1 · Welcome
// ---------------------------------------------------------------------------

class _StepWelcome extends StatelessWidget {
  final VoidCallback onSkip;
  final VoidCallback onStart;
  const _StepWelcome({required this.onSkip, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _GlowingOrb(),
              const SizedBox(height: 56),
              Text(
                l10n.onboardingWelcomeTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.onboardingWelcomeBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 44),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GhostButton(label: l10n.onboardingSkip, onTap: onSkip),
                  const SizedBox(width: 14),
                  _PrimaryButton(
                    label: l10n.onboardingStart,
                    onTap: onStart,
                    accent: const Color(0xFF3B6FF5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The luminous purple/blue sphere with a centered "J".
class _GlowingOrb extends StatelessWidget {
  const _GlowingOrb();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer soft glow halo.
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF8B7BFF).withValues(alpha: 0.45),
                  const Color(0xFF8B7BFF).withValues(alpha: 0.0),
                ],
                stops: const [0.35, 1.0],
              ),
            ),
          ),
          // The orb itself: layered radial gradient + rim highlight.
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 0.95,
                colors: [
                  Color(0xFFD9CFFF),
                  Color(0xFFA38BFF),
                  Color(0xFF6E5BFF),
                  Color(0xFF4D3FCC),
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6E5BFF).withValues(alpha: 0.55),
                  blurRadius: 60,
                  spreadRadius: 8,
                ),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
            ),
          ),
          // Top-left specular highlight.
          Positioned(
            top: 50,
            left: 70,
            child: Container(
              width: 36,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.7),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          const Text(
            'J',
            style: TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 · Pick library root
// ---------------------------------------------------------------------------

class _StepRoot extends StatelessWidget {
  final String? pickedPath;
  final VoidCallback onPick;
  final VoidCallback onSkip;
  const _StepRoot({
    required this.pickedPath,
    required this.onPick,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.onboardingStep1Eyebrow,
                style: const TextStyle(
                  color: Color(0xFF22C9A9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.onboardingRootTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.onboardingRootBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 36),
              _DashDropTarget(
                pickedPath: pickedPath,
                onPick: onPick,
              ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.6),
                ),
                child: Text(l10n.onboardingSkipForNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashDropTarget extends StatelessWidget {
  final String? pickedPath;
  final VoidCallback onPick;
  const _DashDropTarget({required this.pickedPath, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
          ),
          child: CustomPaint(
            painter: _DashedRRectPainter(
              color: const Color(0xFF22C9A9).withValues(alpha: 0.55),
              radius: 20,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FolderIcon(picked: pickedPath != null),
                  const SizedBox(height: 22),
                  Text(
                    pickedPath ?? l10n.onboardingDropFolder,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.onboardingOr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GhostButton(
                    label: l10n.onboardingPickFolder,
                    onTap: onPick,
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      l10n.onboardingRootHint,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderIcon extends StatelessWidget {
  final bool picked;
  const _FolderIcon({required this.picked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: picked
              ? const [Color(0xFF1FA897), Color(0xFF177D6F)]
              : const [Color(0xFF1F584F), Color(0xFF153F39)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C9A9).withValues(alpha: 0.32),
            blurRadius: 26,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.folder_rounded,
        size: 48,
        color: Colors.white,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 8.0, gap = 6.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Step 3 · AI provider
// ---------------------------------------------------------------------------

class _StepAi extends StatelessWidget {
  final AiProviderType? picked;
  final ValueChanged<AiProviderType> onPick;
  final VoidCallback onLater;
  final VoidCallback onEnter;
  const _StepAi({
    required this.picked,
    required this.onPick,
    required this.onLater,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                l10n.onboardingStep2Eyebrow,
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.onboardingAiTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.onboardingAiBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 32),
              _ProviderCard(
                title: l10n.onboardingProviderOpenAi,
                subtitle: 'OpenAI · DeepSeek · LM Studio · Ollama…',
                badge: 'O',
                badgeColor: const Color(0xFF1FA66E),
                selected: picked == AiProviderType.openAi,
                onTap: () => onPick(AiProviderType.openAi),
              ),
              const SizedBox(height: 14),
              _ProviderCard(
                title: 'Google GenAI',
                subtitle: 'Gemini 2.0 Flash · Pro',
                badge: 'G',
                badgeColor: const Color(0xFF4285F4),
                selected: picked == AiProviderType.googleGenAi,
                onTap: () => onPick(AiProviderType.googleGenAi),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GhostButton(label: l10n.onboardingConfigureLater, onTap: onLater),
                  const SizedBox(width: 14),
                  _PrimaryButton(
                    label: l10n.onboardingEnterWorkspace,
                    onTap: onEnter,
                    accent: const Color(0xFF6E5BFF),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final bool selected;
  final VoidCallback onTap;
  const _ProviderCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: border, width: selected ? 1.2 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [badgeColor, badgeColor.withValues(alpha: 0.75)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: selected ? 0.95 : 0.4),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

class _PageDots extends StatelessWidget {
  final int active;
  final Color accent;
  const _PageDots({required this.active, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: isActive ? 28 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? accent : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;
  const _PrimaryButton({required this.label, required this.onTap, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, accent.withValues(alpha: 0.82)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

