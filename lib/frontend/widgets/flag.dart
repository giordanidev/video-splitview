/// Bandeiras desenhadas (o Windows não renderiza emojis de bandeira).
library;

import 'package:flutter/material.dart';

import '../../backend/i18n/strings.dart';

class FlagIcon extends StatelessWidget {
  const FlagIcon({
    super.key,
    required this.language,
    this.width = 24,
    this.height = 16,
  });

  final AppLanguage language;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: height,
        child: switch (language) {
          AppLanguage.ptBr => _brazil(),
          AppLanguage.enUs => _usa(),
          AppLanguage.esEs => _spain(),
        },
      ),
    );
  }

  Widget _brazil() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF009C3B)),
        Center(
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: width * 0.62,
              height: width * 0.62,
              color: const Color(0xFFFFDF00),
            ),
          ),
        ),
        Center(
          child: Container(
            width: width * 0.3,
            height: width * 0.3,
            decoration: const BoxDecoration(
              color: Color(0xFF002776),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _usa() {
    const red = Color(0xFFB22234);
    const white = Color(0xFFFFFFFF);
    const blue = Color(0xFF3C3B6E);
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: List.generate(
            7,
            (index) => Expanded(
              child: Container(
                color: index.isEven ? red : white,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: width * 0.42,
          height: height * 0.5,
          child: Container(color: blue),
        ),
      ],
    );
  }

  Widget _spain() {
    return Column(
      children: [
        Expanded(flex: 1, child: Container(color: const Color(0xFFAA151B))),
        Expanded(flex: 2, child: Container(color: const Color(0xFFF1BF00))),
        Expanded(flex: 1, child: Container(color: const Color(0xFFAA151B))),
      ],
    );
  }
}
