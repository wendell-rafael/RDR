import 'package:flutter/material.dart';

/// Isola um botão do tema global, que força largura infinita nos botões
/// principais das telas. Dentro de um diálogo isso empilha as ações uma sobre
/// a outra; envolvido aqui, o botão volta a ocupar só o espaço do rótulo.
class DialogAction extends StatelessWidget {
  final Widget child;

  const DialogAction({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: const FilledButtonThemeData(),
        outlinedButtonTheme: const OutlinedButtonThemeData(),
        elevatedButtonTheme: const ElevatedButtonThemeData(),
      ),
      child: child,
    );
  }
}
