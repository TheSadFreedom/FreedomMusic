import 'package:flutter/material.dart';

const double kPhoneBreakpoint = 600;
const double kWideBreakpoint = 900;

bool isPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kPhoneBreakpoint;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;

EdgeInsets pagePadding(BuildContext context) {
  final phone = isPhone(context);
  return EdgeInsets.fromLTRB(
    phone ? 16 : 24,
    phone ? 12 : 16,
    phone ? 16 : 24,
    phone ? 8 : 8,
  );
}

double screenTitleSize(BuildContext context) => isPhone(context) ? 28 : 36;
