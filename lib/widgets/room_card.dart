
import 'package:flutter/material.dart';


class RoomCard extends StatefulWidget {
  final String serial;
  final String location;
  final bool showLocation;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const RoomCard({
    super.key,
    required this.serial,
    required this.location,
    this.showLocation = true,
    required this.isCompleted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      scale: _pressed ? 0.97 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _pressed ? 0.06 : 0.1),
              blurRadius: _pressed ? 6 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.serial,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: widget.isCompleted
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.showLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.location,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                  if (widget.isCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 14,
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

// -------------------- Camera Page --------------------
