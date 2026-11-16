import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../state/controladores.dart';
import '../componentes/comuns.dart';

/// Entrada e cadastro por e-mail e senha.
class LoginTela extends StatelessWidget {
  const LoginTela({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Espaco.gg),
          child: LarguraMaxima(
            child: FormularioDeAcesso(aoConcluir: () => Navigator.of(context).pop()),
          ),
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
  bool _senhaVisivel = false;
  bool _aceitouTermos = false;
  bool _mostrouErroDeTermos = false;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _alternarModo() => setState(() {
        _cadastro = !_cadastro;
        _erro = null;
        _aviso = null;
      });

  Future<void> _enviar() async {
    final formularioOk = _chave.currentState!.validate();
    if (_cadastro && !_aceitouTermos) setState(() => _mostrouErroDeTermos = true);
    if (!formularioOk || (_cadastro && !_aceitouTermos)) return;

    setState(() {
      _enviando = true;
      _erro = null;
      _aviso = null;
    });
    final sessao = context.read<SessaoControlador>();
    try {
      if (_cadastro) {
        await sessao.cadastrar(_nome.text, _email.text, _senha.text, aceitouTermos: _aceitouTermos);
      } else {
        await sessao.entrar(_email.text, _senha.text);
      }
      widget.aoConcluir?.call();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _esqueciASenha() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _erro = 'Digite seu e-mail no campo acima para receber o link de recuperação.';
        _aviso = null;
      });
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.read<SessaoControlador>().enviarRecuperacaoDeSenha(email);
      if (mounted) {
        setState(() => _aviso = 'Se esse e-mail tiver cadastro, enviamos um link para criar uma nova senha.');
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Form(
      key: _chave,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(alignment: Alignment.centerLeft, child: LogoPassaRapido()),
            const SizedBox(height: Espaco.g),
            Text(_cadastro ? 'Crie sua conta' : 'Entre para colaborar', style: tema.textTheme.headlineSmall),
            const SizedBox(height: Espaco.pp),
            Text(
              'Com uma conta você informa filas, recebe alerta quando a fila baixar e ganha pontos.',
              style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Espaco.gg),
            if (_cadastro) ...[
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Seu nome', prefixIcon: Icon(Icons.person_outline_rounded)),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (v) => (v == null || v.trim().length < 2) ? 'Informe seu nome' : null,
              ),
              const SizedBox(height: Espaco.m),
            ],
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline_rounded)),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (v) => (v == null || !v.contains('@')) ? 'Informe um e-mail válido' : null,
            ),
            const SizedBox(height: Espaco.m),
            TextFormField(
              controller: _senha,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                helperText: _cadastro ? 'Pelo menos 8 caracteres' : null,
                suffixIcon: IconButton(
                  tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                  icon: Icon(_senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                ),
              ),
              obscureText: !_senhaVisivel,
              autofillHints: [_cadastro ? AutofillHints.newPassword : AutofillHints.password],
              validator: (v) => (v == null || v.length < (_cadastro ? 8 : 6)) ? 'Use pelo menos ${_cadastro ? 8 : 6} caracteres' : null,
              onFieldSubmitted: (_) => _enviar(),
            ),
            if (_cadastro) ...[
              const SizedBox(height: Espaco.p),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _aceitouTermos,
                onChanged: (v) => setState(() => _aceitouTermos = v ?? false),
                title: Text.rich(
                  TextSpan(
                    text: 'Li e aceito os ',
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed('/termos'),
                          child: Text('Termos de uso', style: TextStyle(color: tema.colorScheme.primary, decoration: TextDecoration.underline)),
                        ),
                      ),
                      const TextSpan(text: ' e a '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed('/privacidade'),
                          child: Text('Política de privacidade', style: TextStyle(color: tema.colorScheme.primary, decoration: TextDecoration.underline)),
                        ),
                      ),
                    ],
                  ),
                  style: tema.textTheme.bodyMedium,
                ),
              ),
              if (_mostrouErroDeTermos && !_aceitouTermos)
                Padding(
                  padding: const EdgeInsets.only(left: Espaco.p),
                  child: Text('Aceite os termos para criar a conta.', style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.error)),
                ),
            ],
            if (_erro != null) CaixaDeErro(mensagem: _erro!),
            if (_aviso != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: Espaco.m),
                  child: Text(_aviso!, style: tema.textTheme.bodyMedium),
                ),
              ),
            const SizedBox(height: Espaco.gg),
            FilledButton(
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_cadastro ? 'Criar conta' : 'Entrar'),
            ),
            const SizedBox(height: Espaco.p),
            if (!_cadastro)
              TextButton(onPressed: _enviando ? null : _esqueciASenha, child: const Text('Esqueci minha senha')),
            TextButton(
              onPressed: _enviando ? null : _alternarModo,
              child: Text(_cadastro ? 'Já tenho conta' : 'Criar uma conta'),
            ),
          ],
        ),
      ),
    );
  }
}
