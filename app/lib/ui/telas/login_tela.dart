import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/controladores.dart';
import '../componentes/comuns.dart';

/// Entrada e cadastro por e-mail e senha.
class LoginTela extends StatelessWidget {
  const LoginTela({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Entrar')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FormularioDeAcesso(aoConcluir: () => Navigator.of(context).pop()),
        ),
      );
}

class FormularioDeAcesso extends StatefulWidget {
  const FormularioDeAcesso({super.key, this.aoConcluir});

  final VoidCallback? aoConcluir;

  @override
  State<FormularioDeAcesso> createState() => _FormularioDeAcessoState();
}

class _FormularioDeAcessoState extends State<FormularioDeAcesso> {
  final _chave = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _cadastro = false;
  bool _enviando = false;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_chave.currentState!.validate()) return;
    setState(() => _enviando = true);
    final sessao = context.read<SessaoControlador>();
    try {
      if (_cadastro) {
        await sessao.cadastrar(_nome.text, _email.text, _senha.text);
      } else {
        await sessao.entrar(_email.text, _senha.text);
      }
      widget.aoConcluir?.call();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Form(
      key: _chave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _cadastro ? 'Crie sua conta' : 'Entre para colaborar',
            style: tema.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text('Com uma conta você informa filas, recebe alertas e ganha pontos.'),
          const SizedBox(height: 20),
          if (_cadastro) ...[
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Seu nome'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'E-mail'),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: (v) => (v == null || !v.contains('@')) ? 'Informe um e-mail válido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _senha,
            decoration: const InputDecoration(labelText: 'Senha'),
            obscureText: true,
            validator: (v) => (v == null || v.length < 6) ? 'Use pelo menos 6 caracteres' : null,
            onFieldSubmitted: (_) => _enviar(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _enviando ? null : _enviar,
            child: Text(_enviando ? 'Aguarde...' : (_cadastro ? 'Criar conta' : 'Entrar')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _enviando ? null : () => setState(() => _cadastro = !_cadastro),
            child: Text(_cadastro ? 'Já tenho conta' : 'Criar uma conta'),
          ),
        ],
      ),
    );
  }
}
