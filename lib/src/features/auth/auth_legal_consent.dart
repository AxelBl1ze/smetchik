import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class SignupConsentRow extends StatelessWidget {
  const SignupConsentRow({
    super.key,
    required this.value,
    required this.label,
    required this.documentTitle,
    required this.onChanged,
    required this.onOpen,
  });

  final bool value;
  final String label;
  final String documentTitle;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: (next) => onChanged(next ?? false),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$label ',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orangeDark,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    documentTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
