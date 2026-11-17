import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// The Acquiretech AQ junction mark, exactly as on the website.
class AqMark extends StatelessWidget {
  const AqMark({super.key, this.size = 32, this.color = Brand.logo});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/brand/aq-mark.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        semanticsLabel: 'Acquiretech',
      );
}

/// Mark + lowercase wordmark, the way the website header sets it.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.onDark = false, this.size = 30, this.caption = 'CRM'});
  final bool onDark;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? const Color(0xFFF6F1E8) : Brand.ink;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AqMark(size: size),
      SizedBox(width: size * .32),
      Text(
        'acquiretech',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * .74,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
          color: fg,
          height: 1,
        ),
      ),
      if (caption != null) ...[
        SizedBox(width: size * .28),
        Container(
          padding: EdgeInsets.symmetric(horizontal: size * .2, vertical: size * .07),
          decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: .28)),
            borderRadius: BorderRadius.circular(size * .2),
          ),
          child: Text(
            caption!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size * .34,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: fg.withValues(alpha: .8),
            ),
          ),
        ),
      ],
    ]);
  }
}
