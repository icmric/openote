import 'package:flutter/material.dart';
import 'package:mosapad/main.dart'; // Import main.dart to access appPages

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String currentRoute;

  CustomAppBar({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: appPages.map((page) {
          bool isSelected = page.route == currentRoute;
          return TextButton(
            onPressed: () {
              if (!isSelected) {
                Navigator.pushReplacementNamed(context, page.route);
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: isSelected ? Colors.white : Colors.black,
              backgroundColor: isSelected ? Colors.blue : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(0),
              ),
            ),
            child: Text(page.title),
          );
        }).toList(),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}