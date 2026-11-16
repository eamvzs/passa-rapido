import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

/// Aberta quando a pessoa chega pelo link do e-mail de recuperação de senha.
class NovaSenhaTela extends StatefulWidget {
  const NovaSenhaTela({super.key});

  @override
  State<NovaSenhaTela> createState() => _NovaSenhaTelaState();
}

class _NovaSenhaTelaState extends State<NovaSenhaTela> {
  final _chave = GlobalKey<FormState>();
  final _senha = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_chave.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.read<SessaoControlador>().definirNovaSenha(_senha.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      mostrarSucesso(context, 'Senha alterada.');
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nova senha')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Espaco.gg),
          child: LarguraMaxima(
            child: Form(
              key: _chave,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Escolha uma nova senha', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: Espaco.g),
                  TextFormField(
                    controller: _senha,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'Nova senha', helperText: 'Pelo menos 6 caracteres'),
                    validator: (v) => (v == null || v.length < 6) ? 'Use pelo menos 6 caracteres' : null,
                    onFieldSubmitted: (_) => _salvar(),
                  ),
                  if (_erro != null) CaixaDeErro(mensagem: _erro!),
                  const SizedBox(height: Espaco.g),
                  FilledButton(
                    onPressed: _enviando ? null : _salvar,
                    child: _enviando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Salvar senha'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
