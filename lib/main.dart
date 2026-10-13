import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
Future<void> _notificacoesInicializadas = Future<void>.value();
String? _payloadNotificacaoPendente;

Future<void> _abrirDestinoDaNotificacao(String payload) async {
  try {
    final mapa = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    final pacienteNome = (mapa['pacienteNome'] ?? '').toString();
    final data = (mapa['data'] ?? '').toString();
    final horario = (mapa['horario'] ?? '').toString();
    final tipo = (mapa['tipo'] ?? 'Aplicação').toString();
    if (pacienteNome.isEmpty) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      _payloadNotificacaoPendente = payload;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final dadosPacientes = prefs.getString('lista_pacientes');
    Paciente? pacienteEncontrado;
    if (dadosPacientes != null) {
      final lista = (jsonDecode(dadosPacientes) as List)
          .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      for (final p in lista) {
        if (p.nome == pacienteNome) {
          pacienteEncontrado = p;
          break;
        }
      }
    }

    if (pacienteEncontrado != null) {
      final compromisso = Compromisso(
        pacienteNome: pacienteEncontrado.nome,
        data: data,
        horario: horario,
        tipo: tipo,
        descricao: '',
        telefone: pacienteEncontrado.telefone,
      );
      nav.push(
        MaterialPageRoute(
          builder: (_) => DetalhesPacientePage(
            paciente: pacienteEncontrado!,
            compromissoConfirmacao: compromisso,
          ),
        ),
      );
    } else {
      nav.push(
        MaterialPageRoute(
          builder: (_) => AgendaPage(dataInicial: _lerData(data)),
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro ao abrir notificação: $e');
  }
}

Future<void> _enviarWhatsApp({
  required BuildContext context,
  required String telefone,
  required String mensagem,
}) async {
  final limpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
  if (limpo.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telefone do paciente não informado.')),
    );
    return;
  }
  final numeroCompleto = limpo.startsWith('55') ? limpo : '55$limpo';
  final url = Uri.parse(
    'https://wa.me/$numeroCompleto?text=${Uri.encodeComponent(mensagem)}',
  );

  try {
    final lancou = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!lancou) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o WhatsApp: $e')),
      );
    }
  }
}

DateTime? _lerData(String valor) {
  final partes = valor.split('/');
  if (partes.length != 3 ||
      partes[0].length != 2 ||
      partes[1].length != 2 ||
      partes[2].length != 4) {
    return null;
  }

  final dia = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final ano = int.tryParse(partes[2]);
  if (dia == null || mes == null || ano == null) return null;

  final data = DateTime(ano, mes, dia);
  if (data.day != dia || data.month != mes || data.year != ano) return null;
  return data;
}

String _formatarData(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

String gerarMensagemConfirmacao(Compromisso compromisso) =>
  'Olá ${compromisso.pacienteNome}, tudo bem? passando para confirmar seu agendamento dia ${compromisso.data} e hora ${compromisso.horario}, qualquer dúvida, fico à disposição 👩🏽‍⚕️';

int? _diasDoCiclo(String frequencia) {
  final matchNumero = RegExp(r'\d+').firstMatch(frequencia);
  if (matchNumero != null) {
    final dias = int.tryParse(matchNumero.group(0)!);
    return dias != null && dias > 0 ? dias : null;
  }

  final texto = frequencia.toLowerCase();
  if (texto.contains('quinzen')) return 15;
  if (texto.contains('seman')) return 7;
  if (texto.contains('mensal')) return 30;
  if (texto.contains('diári') || texto.contains('diari')) return 1;
  return null;
}

String? calcularProximaDataCiclo(String dataInicio, String frequencia) {
  final inicio = _lerData(dataInicio);
  final dias = _diasDoCiclo(frequencia);
  if (inicio == null || dias == null) return null;
  return _formatarData(inicio.add(Duration(days: dias)));
}

String? calcularProximaDataRecorrencia(
  String ultimaDataAplicada,
  String frequencia, {
  String? dataInicio,
}) {
  final referencia = _lerData(ultimaDataAplicada) ??
      (dataInicio != null && dataInicio.isNotEmpty ? _lerData(dataInicio) : null);
  final dias = _diasDoCiclo(frequencia);
  if (referencia == null || dias == null) return null;
  return _formatarData(referencia.add(Duration(days: dias)));
}

TextInputFormatter _formatadorData() =>
    TextInputFormatter.withFunction((oldValue, newValue) {
      final digitos = newValue.text.replaceAll(RegExp(r'\D'), '');
      final limitados = digitos.length > 8 ? digitos.substring(0, 8) : digitos;
      final buffer = StringBuffer();
      for (var i = 0; i < limitados.length; i++) {
        if (i == 2 || i == 4) buffer.write('/');
        buffer.write(limitados[i]);
      }
      final texto = buffer.toString();
      return TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    });

TextInputFormatter _formatadorHorario() =>
    TextInputFormatter.withFunction((oldValue, newValue) {
      final digitos = newValue.text.replaceAll(RegExp(r'\D'), '');
      final limitados = digitos.length > 4 ? digitos.substring(0, 4) : digitos;
      final texto = limitados.length > 2
          ? '${limitados.substring(0, 2)}:${limitados.substring(2)}'
          : limitados;
      return TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
    });

Future<DateTime?> agendarNotificacaoCompromisso({
  required int notificacaoId,
  required String pacienteNome,
  required String tipo,
  required String data,
  required String horario,
}) async {
  if (kIsWeb) return null;

  try {
    final dataCompromisso = _lerData(data);
    final partesHora = horario.split(':');
    if (partesHora.length != 2) return null;
    final hora = int.tryParse(partesHora[0].trim());
    final minuto = int.tryParse(partesHora[1].trim());

    if (dataCompromisso == null ||
        hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }

    final dataAplicacao = tz.TZDateTime(
      tz.local,
      dataCompromisso.year,
      dataCompromisso.month,
      dataCompromisso.day,
      hora,
      minuto,
    );

    final agora = tz.TZDateTime.now(tz.local);
    if (!dataAplicacao.isAfter(agora)) return null;
    final doisDiasAntes = dataAplicacao.subtract(const Duration(days: 2));
    final dataNotificacao = doisDiasAntes.isAfter(agora)
        ? doisDiasAntes
        : agora.add(const Duration(seconds: 5));

    await _notificacoesInicializadas;
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    try {
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {
      debugPrint('Permissão de notificação do Android não pôde ser solicitada.');
    }

    bool podeUsarAlarmeExato = true;
    try {
      podeUsarAlarmeExato = await androidPlugin?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      podeUsarAlarmeExato = true;
    }

    final iosPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    await flutterLocalNotificationsPlugin.cancel(notificacaoId);

    final scheduleMode = podeUsarAlarmeExato
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificacaoId,
      'Lembrete (2 dias antes): confirmar agendamento',
      gerarMensagemConfirmacao(
        Compromisso(
          pacienteNome: pacienteNome,
          data: data,
          horario: horario,
          tipo: tipo,
          descricao: '',
        ),
      ),
      dataNotificacao,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nursehome_lembretes_2dias',
          'Lembretes WhatsApp (2 dias antes)',
          channelDescription:
              'Aviso 2 dias antes da aplicação para envio de WhatsApp ao paciente',
          icon: 'ic_launcher',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: jsonEncode({
        'pacienteNome': pacienteNome,
        'data': data,
        'horario': horario,
        'tipo': tipo,
      }),
    );
    debugPrint('Notificação da agenda agendada para: $dataNotificacao');
    return dataNotificacao;
  } catch (e) {
    debugPrint('Erro ao agendar notificação da agenda: $e');
    return null;
  }
}

Future<void> _inicializarNotificacoes() async {
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  try {
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _abrirDestinoDaNotificacao(payload);
        }
      },
    );
    final launchDetails =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _payloadNotificacaoPendente = payload;
      }
    }
  } catch (e) {
    debugPrint('Erro ao inicializar notificações: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    tz.initializeTimeZones();
    // Configura o fuso horário local para o Brasil (Horário de Brasília)
    try {
      if (tz.timeZoneDatabase.locations.containsKey('America/Sao_Paulo')) {
        tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
      }
    } catch (e) {
      debugPrint('Erro ao configurar timezone local: $e');
    }
  }

  runApp(const MeuApp());
  if (!kIsWeb) {
    _notificacoesInicializadas = _inicializarNotificacoes();
  }
}

// ============================================================
// APP
// ============================================================
class MeuApp extends StatelessWidget {
  const MeuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Nursehome',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 41, 36, 142),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// MODELO MEDICAMENTO
// ============================================================
class Medicamento {
  String nome;
  String dose;
  String via;
  String frequencia;
  String dataInicio;
  String dataValidade;
  String observacoes;
  String proximaData;
  String horario;

  Medicamento({
    required this.nome,
    required this.dose,
    required this.via,
    required this.frequencia,
    required this.dataInicio,
    required this.dataValidade,
    required this.observacoes,
    required this.proximaData,
    this.horario = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'dose': dose,
      'via': via,
      'frequencia': frequencia,
      'dataInicio': dataInicio,
      'dataValidade': dataValidade,
      'observacoes': observacoes,
      'proximaData': proximaData,
      'horario': horario,
    };
  }

  factory Medicamento.fromMap(Map<String, dynamic> map) {
    return Medicamento(
      nome: map['nome'] ?? '',
      dose: map['dose'] ?? '',
      via: map['via'] ?? '',
      frequencia: map['frequencia'] ?? '',
      dataInicio: map['dataInicio'] ?? '',
      dataValidade: map['dataValidade'] ?? '',
      observacoes: map['observacoes'] ?? '',
      proximaData: map['proximaData'] ?? '',
      horario: map['horario'] ?? '',
    );
  }
}

// ============================================================
// MODELO PACIENTE
// ============================================================
class RegistroProntuario {
  String data;
  String tipo;
  String descricao;
  List<String> medicamentos;
  String observacoes;
  bool realizado;
  String proximaData;

  RegistroProntuario({
    required this.data,
    this.tipo = 'Aplicação',
    this.descricao = '',
    this.medicamentos = const [],
    this.observacoes = '',
    this.realizado = true,
    this.proximaData = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'data': data,
      'tipo': tipo,
      'descricao': descricao,
      'medicamentos': medicamentos,
      'observacoes': observacoes,
      'realizado': realizado,
      'proximaData': proximaData,
    };
  }

  factory RegistroProntuario.fromMap(Map<String, dynamic> map) {
    return RegistroProntuario(
      data: map['data'] ?? '',
      tipo: map['tipo'] ?? 'Aplicação',
      descricao: map['descricao'] ?? '',
      medicamentos: (map['medicamentos'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
      observacoes: map['observacoes'] ?? '',
      realizado: map['realizado'] ?? true,
      proximaData: map['proximaData'] ?? '',
    );
  }
}

class Paciente {
  String nome;
  String nascimento;
  String telefone;
  String endereco;
  String alergias;
  String observacoes;
  String prontuario;
  List<Medicamento> medicamentos;
  List<RegistroProntuario> prontuarioRegistros;

  Paciente({
    required this.nome,
    required this.nascimento,
    required this.telefone,
    required this.endereco,
    required this.alergias,
    required this.observacoes,
    required this.prontuario,
    required this.medicamentos,
    List<RegistroProntuario>? prontuarioRegistros,
  }) : prontuarioRegistros = prontuarioRegistros ?? const [];

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'nascimento': nascimento,
      'telefone': telefone,
      'endereco': endereco,
      'alergias': alergias,
      'observacoes': observacoes,
      'prontuario': prontuario,
      'medicamentos': medicamentos.map((m) => m.toMap()).toList(),
      'prontuarioRegistros':
          prontuarioRegistros.map((registro) => registro.toMap()).toList(),
    };
  }

  factory Paciente.fromMap(Map<String, dynamic> map) {
    final listaMedicamentos = map['medicamentos'] as List? ?? [];
    final listaRegistros = map['prontuarioRegistros'] as List? ?? [];
    return Paciente(
      nome: map['nome'] ?? '',
      nascimento: map['nascimento'] ?? '',
      telefone: map['telefone'] ?? '',
      endereco: map['endereco'] ?? '',
      alergias: map['alergias'] ?? '',
      observacoes: map['observacoes'] ?? '',
      prontuario: map['prontuario'] ?? '',
      medicamentos: listaMedicamentos
          .map((item) => Medicamento.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      prontuarioRegistros: listaRegistros
          .map(
            (item) => RegistroProntuario.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

// ============================================================
// MODELO COMPROMISSO
// ============================================================
class Compromisso {
  String pacienteNome;
  String data;
  String horario;
  String tipo;
  String descricao;
  String dataInicio;
  String frequencia;
  String telefone;
  List<String> medicamentos;
  int notificacaoId;
  String ultimaDataAplicada;
  String proximaData;

  Compromisso({
    required this.pacienteNome,
    required this.data,
    required this.horario,
    required this.tipo,
    required this.descricao,
    this.dataInicio = '',
    this.frequencia = '',
    this.telefone = '',
    this.medicamentos = const [],
    this.notificacaoId = 0,
    this.ultimaDataAplicada = '',
    this.proximaData = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'pacienteNome': pacienteNome,
      'data': data,
      'horario': horario,
      'tipo': tipo,
      'descricao': descricao,
      'dataInicio': dataInicio,
      'frequencia': frequencia,
      'telefone': telefone,
      'medicamentos': medicamentos,
      'notificacaoId': notificacaoId,
      'ultimaDataAplicada': ultimaDataAplicada,
      'proximaData': proximaData,
    };
  }

  factory Compromisso.fromMap(Map<String, dynamic> map) {
    return Compromisso(
      pacienteNome: map['pacienteNome'] ?? '',
      data: map['data'] ?? '',
      horario: map['horario'] ?? '',
      tipo: map['tipo'] ?? '',
      descricao: map['descricao'] ?? '',
      dataInicio: map['dataInicio'] ?? '',
      frequencia: map['frequencia'] ?? '',
      telefone: map['telefone'] ?? '',
      medicamentos: (map['medicamentos'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
      notificacaoId: map['notificacaoId'] ?? 0,
      ultimaDataAplicada: map['ultimaDataAplicada'] ?? '',
      proximaData: map['proximaData'] ?? '',
    );
  }
}

// ============================================================
// LOGIN
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  String emailCadastrado = '';
  String senhaCadastrada = '';
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
  }

  Future<void> _carregarUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final senha = prefs.getString('senha') ?? '';
    final acessoSalvo = prefs.getBool('logado') ?? false;

    if (!mounted) return;

    if (acessoSalvo && email.isNotEmpty && senha.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PainelPrincipalPage()),
      );
      return;
    }

    setState(() {
      emailCadastrado = email;
      senhaCadastrada = senha;
      carregando = false;
    });
  }

  Future<void> _abrirCadastroConta() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CadastroPage()),
    );

    if (!mounted) return;

    if (resultado == true) {
      await _carregarUsuario();
    }
  }

  void _entrar() {
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (emailCadastrado.isEmpty || senhaCadastrada.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Primeiro crie sua conta.')));
      return;
    }

    if (email == emailCadastrado && senha == senhaCadastrada) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool('logado', true);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PainelPrincipalPage()),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail ou senha incorretos.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final existeConta =
        emailCadastrado.isNotEmpty && senhaCadastrada.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Nursehome'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Logo de + estilizado do Nursehome (Rosé + Azul bebê)
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5C4C9), // Fundo Rosé
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.15),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  size: 60,
                  color: Color(0xFF53A6E4), // Azul bebê
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nursehome',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 41, 36, 142),
                ),
              ),
              const SizedBox(height: 30),
              if (!existeConta) ...[
                const Text(
                  'Ainda não existe uma conta cadastrada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _abrirCadastroConta,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Criar minha conta'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: senhaController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _entrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Entrar'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _abrirCadastroConta,
                  child: const Text(
                    'Criar outra conta',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CADASTRO DA CONTA
// ============================================================
class CadastroPage extends StatefulWidget {
  const CadastroPage({super.key});

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();

  Future<void> _salvarConta() async {
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preencha e-mail e senha.')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', email);
    await prefs.setString('senha', senha);
    await prefs.setBool('logado', false);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Conta criada com sucesso!')));

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: const Text('Criar conta')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: senhaController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvarConta,
                child: const Text('Salvar conta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PAINEL PRINCIPAL
// ============================================================
class PainelPrincipalPage extends StatefulWidget {
  const PainelPrincipalPage({super.key});

  @override
  State<PainelPrincipalPage> createState() => _PainelPrincipalPageState();
}

class _PainelPrincipalPageState extends State<PainelPrincipalPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendente = _payloadNotificacaoPendente;
      if (pendente != null && pendente.isNotEmpty) {
        _payloadNotificacaoPendente = null;
        _abrirDestinoDaNotificacao(pendente);
      }
    });
  }

  void _abrir(BuildContext context, Widget pagina) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Nursehome'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('logado', false);

              if (!context.mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bem-vindo ao Nursehome',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            _botao(context, 'Home', Icons.home, () {}),
            const SizedBox(height: 14),
            _botao(
              context,
              'Agenda',
              Icons.calendar_month,
              () => _abrir(context, const AgendaPage()),
            ),
            const SizedBox(height: 14),
            _botao(
              context,
              'Pacientes',
              Icons.people,
              () => _abrir(context, const PacientesPage()),
            ),
            const SizedBox(height: 14),
            _botao(
              context,
              'Prontuários',
              Icons.assignment,
              () => _abrir(context, const PacientesParaProntuarioPage()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botao(
    BuildContext context,
    String titulo,
    IconData icone,
    VoidCallback onTap,
  ) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icone),
      label: Text(titulo),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color.fromARGB(255, 41, 36, 142),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 17),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ============================================================
// PACIENTES
// ============================================================
class PacientesPage extends StatefulWidget {
  const PacientesPage({super.key});

  @override
  State<PacientesPage> createState() => _PacientesPageState();
}

class _PacientesPageState extends State<PacientesPage> {
  List<Paciente> pacientes = [];

  @override
  void initState() {
    super.initState();
    _carregarPacientes();
  }

  Future<void> _carregarPacientes() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');

    if (dados == null) {
      if (mounted) {
        setState(() {
          pacientes = [];
        });
      }
      return;
    }

    final lista = jsonDecode(dados) as List;

    if (!mounted) return;

    setState(() {
      pacientes = lista
          .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    });
  }

  Future<void> _salvarPacientes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lista_pacientes',
      jsonEncode(pacientes.map((p) => p.toMap()).toList()),
    );
  }

  Future<void> _novoPaciente() async {
    final paciente = await Navigator.push<Paciente>(
      context,
      MaterialPageRoute(builder: (_) => const CadastroPacientePage()),
    );

    if (!mounted) return;

    if (paciente != null) {
      setState(() {
        pacientes.add(paciente);
      });
      await _salvarPacientes();
    }
  }

  Future<void> _abrirPaciente(Paciente paciente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalhesPacientePage(paciente: paciente),
      ),
    );

    if (!mounted) return;
    await _carregarPacientes();
  }

  Future<void> _excluirPaciente(int index) async {
    setState(() {
      pacientes.removeAt(index);
    });
    await _salvarPacientes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: const Text('Pacientes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: pacientes.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum paciente cadastrado.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                itemCount: pacientes.length,
                itemBuilder: (context, index) {
                  final paciente = pacientes[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                        paciente.nome,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        paciente.telefone.isEmpty
                            ? 'Telefone não informado'
                            : paciente.telefone,
                      ),
                      onTap: () => _abrirPaciente(paciente),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _excluirPaciente(index),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novoPaciente,
        icon: const Icon(Icons.person_add),
        label: const Text('Paciente'),
      ),
    );
  }
}

// ============================================================
// CADASTRO / EDIÇÃO COMPLETA DO PACIENTE
// ============================================================
class CadastroPacientePage extends StatefulWidget {
  final Paciente? pacienteParaEditar;

  const CadastroPacientePage({super.key, this.pacienteParaEditar});

  @override
  State<CadastroPacientePage> createState() => _CadastroPacientePageState();
}

class _CadastroPacientePageState extends State<CadastroPacientePage> {
  late TextEditingController nomeController;
  late TextEditingController nascimentoController;
  late TextEditingController telefoneController;
  late TextEditingController enderecoController;
  late TextEditingController alergiasController;
  late TextEditingController observacoesController;

  @override
  void initState() {
    super.initState();
    final p = widget.pacienteParaEditar;
    nomeController = TextEditingController(text: p?.nome ?? '');
    nascimentoController = TextEditingController(text: p?.nascimento ?? '');
    telefoneController = TextEditingController(text: p?.telefone ?? '');
    enderecoController = TextEditingController(text: p?.endereco ?? '');
    alergiasController = TextEditingController(text: p?.alergias ?? '');
    observacoesController = TextEditingController(text: p?.observacoes ?? '');
  }

  @override
  void dispose() {
    nomeController.dispose();
    nascimentoController.dispose();
    telefoneController.dispose();
    enderecoController.dispose();
    alergiasController.dispose();
    observacoesController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do paciente.')),
      );
      return;
    }

    final paciente = Paciente(
      nome: nomeController.text.trim(),
      nascimento: nascimentoController.text.trim(),
      telefone: telefoneController.text.trim(),
      endereco: enderecoController.text.trim(),
      alergias: alergiasController.text.trim(),
      observacoes: observacoesController.text.trim(),
      prontuario: widget.pacienteParaEditar?.prontuario ?? '',
      medicamentos: widget.pacienteParaEditar?.medicamentos ?? [],
    );

    Navigator.pop(context, paciente);
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ehEdicao = widget.pacienteParaEditar != null;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: Text(ehEdicao ? 'Editar Paciente' : 'Novo Paciente'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _campo('Nome completo *', nomeController),
            const SizedBox(height: 12),
            _campo(
              'Data de nascimento',
              nascimentoController,
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 12),
            _campo(
              'Telefone (com DDD)',
              telefoneController,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _campo('Endereço', enderecoController),
            const SizedBox(height: 12),
            _campo('Alergias', alergiasController, maxLines: 3),
            const SizedBox(height: 12),
            _campo('Observações gerais', observacoesController, maxLines: 4),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save),
                label: Text(ehEdicao ? 'Salvar alterações' : 'Salvar paciente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DETALHES DO PACIENTE
// ============================================================
class DetalhesPacientePage extends StatefulWidget {
  final Paciente paciente;
  final Compromisso? compromissoConfirmacao;

  const DetalhesPacientePage({
    super.key,
    required this.paciente,
    this.compromissoConfirmacao,
  });

  @override
  State<DetalhesPacientePage> createState() => _DetalhesPacientePageState();
}

class _DetalhesPacientePageState extends State<DetalhesPacientePage> {
  Compromisso? _proximoCompromisso;

  @override
  void initState() {
    super.initState();
    _proximoCompromisso = widget.compromissoConfirmacao;
    _carregarProximoCompromisso();
  }

  Future<void> _carregarProximoCompromisso() async {
    if (_proximoCompromisso != null) return;
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_compromissos');
    if (dados == null) return;
    try {
      final lista = (jsonDecode(dados) as List)
          .map((item) => Compromisso.fromMap(Map<String, dynamic>.from(item)))
          .where((c) => c.pacienteNome == widget.paciente.nome)
          .toList();
      if (lista.isEmpty || !mounted) return;
      final hoje = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      lista.sort((a, b) {
        final da = _lerData(a.data) ?? DateTime(2100);
        final db = _lerData(b.data) ?? DateTime(2100);
        return da.compareTo(db);
      });
      final futuro = lista.firstWhere(
        (c) {
          final d = _lerData(c.data);
          return d != null && !d.isBefore(hoje);
        },
        orElse: () => lista.last,
      );
      setState(() => _proximoCompromisso = futuro);
    } catch (_) {}
  }

  Future<void> _salvarAlteracoes() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');

    if (dados == null) return;

    final lista = (jsonDecode(dados) as List)
        .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
        .toList();

    final index = lista.indexWhere((p) => p.nome == widget.paciente.nome);

    if (index != -1) {
      lista[index] = widget.paciente;
    }

    await prefs.setString(
      'lista_pacientes',
      jsonEncode(lista.map((p) => p.toMap()).toList()),
    );
  }

  Future<void> _editarPaciente() async {
    final Paciente? pacienteAtualizado = await Navigator.push<Paciente>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CadastroPacientePage(pacienteParaEditar: widget.paciente),
      ),
    );

    if (pacienteAtualizado != null) {
      setState(() {
        widget.paciente.nome = pacienteAtualizado.nome;
        widget.paciente.nascimento = pacienteAtualizado.nascimento;
        widget.paciente.telefone = pacienteAtualizado.telefone;
        widget.paciente.endereco = pacienteAtualizado.endereco;
        widget.paciente.alergias = pacienteAtualizado.alergias;
        widget.paciente.observacoes = pacienteAtualizado.observacoes;
      });
      await _salvarAlteracoes();
    }
  }

  Future<void> _abrirMedicamentos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicamentosPage(paciente: widget.paciente),
      ),
    );

    if (!mounted) return;
    await _salvarAlteracoes();
    setState(() {});
  }

  Future<void> _abrirProntuario() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProntuarioPacientePage(paciente: widget.paciente),
      ),
    );

    if (!mounted) return;
    await _salvarAlteracoes();
    setState(() {});
  }

  Widget _info(String titulo, String valor, IconData icone) {
    return Card(
      child: ListTile(
        leading: Icon(icone),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(valor.isEmpty ? 'Não informado' : valor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paciente = widget.paciente;
    final agendamento = _proximoCompromisso;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: Text(paciente.nome),
        actions: [
          IconButton(
            tooltip: 'Editar dados do paciente',
            icon: const Icon(Icons.edit),
            onPressed: _editarPaciente,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _info('Nascimento', paciente.nascimento, Icons.cake),
            _info('Telefone', paciente.telefone, Icons.phone),
            _info('Endereço', paciente.endereco, Icons.location_on),
            _info('Alergias', paciente.alergias, Icons.warning),
            _info('Observações', paciente.observacoes, Icons.notes),
            const SizedBox(height: 12),
            if (agendamento != null && paciente.telefone.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _enviarWhatsApp(
                      context: context,
                      telefone: paciente.telefone,
                      mensagem: gerarMensagemConfirmacao(agendamento),
                    );
                  },
                  icon: const Icon(Icons.notifications_active, color: Colors.white),
                  label: Text(
                    'Confirmar agendamento (${agendamento.data} às ${agendamento.horario}) no WhatsApp',
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF128C7E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (paciente.telefone.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final msg =
                        'Olá ${paciente.nome}! Aqui é do Nursehome. Como você está? 👩🏽‍⚕️';
                    _enviarWhatsApp(
                      context: context,
                      telefone: paciente.telefone,
                      mensagem: msg,
                    );
                  },
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: const Text('Conversar no WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _editarPaciente,
                icon: const Icon(Icons.edit),
                label: const Text('Editar dados do paciente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _abrirMedicamentos,
                icon: const Icon(Icons.medication),
                label: Text('Medicamentos (${paciente.medicamentos.length})'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _abrirProntuario,
                icon: const Icon(Icons.assignment),
                label: const Text('Prontuário'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LISTA DE PACIENTES PARA SELECIONAR PRONTUÁRIO
// ============================================================
class PacientesParaProntuarioPage extends StatefulWidget {
  const PacientesParaProntuarioPage({super.key});

  @override
  State<PacientesParaProntuarioPage> createState() =>
      _PacientesParaProntuarioPageState();
}

class _PacientesParaProntuarioPageState
    extends State<PacientesParaProntuarioPage> {
  List<Paciente> pacientes = [];

  @override
  void initState() {
    super.initState();
    _carregarPacientes();
  }

  Future<void> _carregarPacientes() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');

    if (dados == null) return;

    final lista = jsonDecode(dados) as List;

    if (!mounted) return;

    setState(() {
      pacientes = lista
          .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: const Text('Prontuários')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: pacientes.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum paciente cadastrado.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                itemCount: pacientes.length,
                itemBuilder: (context, index) {
                  final paciente = pacientes[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.assignment),
                      ),
                      title: Text(
                        paciente.nome,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        paciente.prontuario.isEmpty
                            ? 'Prontuário em branco'
                            : 'Possui anotações',
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProntuarioPacientePage(paciente: paciente),
                          ),
                        );
                        _carregarPacientes();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ============================================================
// PRONTUÁRIO DO PACIENTE
// ============================================================
class ProntuarioPacientePage extends StatefulWidget {
  final Paciente paciente;

  const ProntuarioPacientePage({super.key, required this.paciente});

  @override
  State<ProntuarioPacientePage> createState() => _ProntuarioPacientePageState();
}

class _ProntuarioPacientePageState extends State<ProntuarioPacientePage> {
  late final TextEditingController prontuarioController;

  @override
  void initState() {
    super.initState();
    prontuarioController = TextEditingController(text: widget.paciente.prontuario);
  }

  String _gerarResumoTexto() {
    final registros = widget.paciente.prontuarioRegistros;
    if (registros.isEmpty) {
      return widget.paciente.prontuario;
    }

    final linhas = <String>[];
    for (final registro in registros) {
      final med = registro.medicamentos.isEmpty ? 'Sem medicamento' : registro.medicamentos.join(', ');
      linhas.add(
        '${registro.data} - ${registro.tipo}${registro.realizado ? ' (realizado)' : ' (pendente)'}\n'
        'Medicamentos: $med\n'
        '${registro.descricao.isEmpty ? registro.observacoes : registro.descricao}${registro.observacoes.isNotEmpty && registro.descricao.isNotEmpty ? ' - ${registro.observacoes}' : ''}\n'
        '${registro.proximaData.isEmpty ? '' : 'Próxima data: ${registro.proximaData}\n'}',
      );
    }
    return linhas.join('\n');
  }

  String _gerarRelatorioMensal() {
    final agora = DateTime.now();
    final registros = widget.paciente.prontuarioRegistros
      ..sort((a, b) {
        final dataA = _lerData(a.data);
        final dataB = _lerData(b.data);
        if (dataA == null && dataB == null) return 0;
        if (dataA == null) return 1;
        if (dataB == null) return -1;
        return dataA.compareTo(dataB);
      });

    final doMes = registros.where((registro) {
      final data = _lerData(registro.data);
      return data != null && data.year == agora.year && data.month == agora.month;
    }).toList();

    if (doMes.isEmpty) {
      return 'Relatório mensal de ${widget.paciente.nome}\n\nNenhum atendimento registrado no mês atual.';
    }

    final buffer = StringBuffer();
    buffer.writeln('RELATÓRIO MENSAL - ${widget.paciente.nome}');
    buffer.writeln('Período: ${_formatarData(DateTime(agora.year, agora.month, 1))} a ${_formatarData(DateTime(agora.year, agora.month + 1, 0))}');
    buffer.writeln('');

    for (final registro in doMes) {
      final medicamentos = registro.medicamentos.isEmpty
          ? 'Sem medicamento específico'
          : registro.medicamentos.join(', ');
      buffer.writeln('• ${registro.data} | ${registro.tipo}');
      if (registro.descricao.isNotEmpty) {
        buffer.writeln('  Descrição: ${registro.descricao}');
      }
      buffer.writeln('  Medicamentos: $medicamentos');
      if (registro.observacoes.isNotEmpty) {
        buffer.writeln('  Observações: ${registro.observacoes}');
      }
      if (registro.proximaData.isNotEmpty) {
        buffer.writeln('  Próxima data: ${registro.proximaData}');
      }
      buffer.writeln('');
    }

    return buffer.toString().trim();
  }

  Future<void> _exportarRelatorioMensal() async {
    final relatorio = _gerarRelatorioMensal();
    await Clipboard.setData(ClipboardData(text: relatorio));

    final assunto = Uri.encodeComponent('Relatório mensal - ${widget.paciente.nome}');
    final corpo = Uri.encodeComponent(relatorio);
    final uri = Uri.parse('mailto:?subject=$assunto&body=$corpo');

    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (!abriu) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório copiado. Você pode colar em WhatsApp, e-mail ou documento.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório gerado e enviado para o app de e-mail/compartilhamento.')),
    );
  }

  Future<void> _salvarProntuario() async {
    widget.paciente.prontuario = prontuarioController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');

    if (dados != null) {
      final lista = (jsonDecode(dados) as List)
          .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
          .toList();

      final index = lista.indexWhere((p) => p.nome == widget.paciente.nome);
      if (index != -1) {
        lista[index] = widget.paciente;
      }

      await prefs.setString(
        'lista_pacientes',
        jsonEncode(lista.map((p) => p.toMap()).toList()),
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prontuário salvo com sucesso!')),
    );
  }

  Future<void> _abrirRegistro([RegistroProntuario? registroExistente]) async {
    final controladorData = TextEditingController(
      text: registroExistente?.data ?? _formatarData(DateTime.now()),
    );
    final controladorTipo = TextEditingController(
      text: registroExistente?.tipo ?? 'Aplicação',
    );
    final controladorDescricao = TextEditingController(
      text: registroExistente?.descricao ?? '',
    );
    final controladorObservacoes = TextEditingController(
      text: registroExistente?.observacoes ?? '',
    );
    final medicamentosSelecionados = <String>{
      if (registroExistente != null) ...registroExistente.medicamentos,
    };

    final resultado = await showDialog<RegistroProntuario>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(
                registroExistente == null
                    ? 'Novo registro'
                    : 'Editar registro',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controladorData,
                      decoration: const InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                      ),
                      inputFormatters: [_formatadorData()],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controladorTipo,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controladorDescricao,
                      decoration: const InputDecoration(
                        labelText: 'Descrição do atendimento',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Medicamentos do paciente'),
                    ),
                    const SizedBox(height: 8),
                    if (widget.paciente.medicamentos.isEmpty)
                      const Text('Nenhum medicamento cadastrado para este paciente.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.paciente.medicamentos.map((med) {
                          final selecionado = medicamentosSelecionados.contains(med.nome);
                          return FilterChip(
                            label: Text(med.nome),
                            selected: selecionado,
                            onSelected: (valor) {
                              setStateModal(() {
                                if (valor) {
                                  medicamentosSelecionados.add(med.nome);
                                } else {
                                  medicamentosSelecionados.remove(med.nome);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controladorObservacoes,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final novoRegistro = RegistroProntuario(
                      data: controladorData.text.trim(),
                      tipo: controladorTipo.text.trim().isEmpty
                          ? 'Aplicação'
                          : controladorTipo.text.trim(),
                      descricao: controladorDescricao.text.trim(),
                      medicamentos: medicamentosSelecionados.toList(),
                      observacoes: controladorObservacoes.text.trim(),
                      realizado: true,
                    );
                    Navigator.pop(context, novoRegistro);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado == null) return;

    setState(() {
      if (registroExistente == null) {
        widget.paciente.prontuarioRegistros.add(resultado);
      } else {
        final index = widget.paciente.prontuarioRegistros.indexOf(registroExistente);
        if (index >= 0) {
          widget.paciente.prontuarioRegistros[index] = resultado;
        }
      }
      widget.paciente.prontuario = _gerarResumoTexto();
    });

    await _salvarProntuario();
  }

  Future<void> _excluirRegistro(int index) async {
    setState(() {
      widget.paciente.prontuarioRegistros.removeAt(index);
      widget.paciente.prontuario = _gerarResumoTexto();
    });
    await _salvarProntuario();
  }

  @override
  Widget build(BuildContext context) {
    final registros = widget.paciente.prontuarioRegistros;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: Text('Prontuário - ${widget.paciente.nome}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: prontuarioController,
                      maxLines: 6,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: 'Notas rápidas do prontuário...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Registros do prontuário',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _exportarRelatorioMensal,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Relatório'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => _abrirRegistro(),
                        icon: const Icon(Icons.add),
                        label: const Text('Novo registro'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (registros.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Nenhum registro cadastrado ainda.'),
                      )
                    else
                      ...List.generate(registros.length, (index) {
                        final registro = registros[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${registro.data} • ${registro.tipo}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _abrirRegistro(registro),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _excluirRegistro(index),
                                    ),
                                  ],
                                ),
                                if (registro.descricao.isNotEmpty)
                                  Text(registro.descricao),
                                if (registro.medicamentos.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Medicamentos: ${registro.medicamentos.join(', ')}',
                                    ),
                                  ),
                                if (registro.observacoes.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Observações: ${registro.observacoes}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvarProntuario,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Prontuário'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MEDICAMENTOS
// ============================================================
class MedicamentosPage extends StatefulWidget {
  final Paciente paciente;

  const MedicamentosPage({super.key, required this.paciente});

  @override
  State<MedicamentosPage> createState() => _MedicamentosPageState();
}

class _MedicamentosPageState extends State<MedicamentosPage> {
  Future<void> novoMedicamento() async {
    final Medicamento? medicamento = await Navigator.push<Medicamento>(
      context,
      MaterialPageRoute<Medicamento>(
        builder: (context) => const CadastroMedicamentoPage(),
      ),
    );

    if (medicamento != null) {
      setState(() {
        widget.paciente.medicamentos.add(medicamento);
      });
    }
  }

  Future<void> editarMedicamento(int index) async {
    final Medicamento medicamentoAtual = widget.paciente.medicamentos[index];
    final Medicamento? medicamentoEditado = await Navigator.push<Medicamento>(
      context,
      MaterialPageRoute<Medicamento>(
        builder: (context) =>
            CadastroMedicamentoPage(medicamentoParaEditar: medicamentoAtual),
      ),
    );

    if (medicamentoEditado != null) {
      setState(() {
        widget.paciente.medicamentos[index] = medicamentoEditado;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicamento atualizado com sucesso!')),
      );
    }
  }

  void _excluirMedicamento(int index) {
    setState(() {
      widget.paciente.medicamentos.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final medicamentos = widget.paciente.medicamentos;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: Text('Medicamentos - ${widget.paciente.nome}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: medicamentos.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum medicamento cadastrado.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                itemCount: medicamentos.length,
                itemBuilder: (context, index) {
                  final m = medicamentos[index];
                  return Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.medication),
                      title: Text(
                        m.nome,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${m.dose} • ${m.horario}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: 'Editar medicamento',
                            onPressed: () => editarMedicamento(index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Excluir medicamento',
                            onPressed: () => _excluirMedicamento(index),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Via: ${m.via}'),
                              Text('Frequência: ${m.frequencia}'),
                              Text('Início: ${m.dataInicio}'),
                              Text('Validade: ${m.dataValidade}'),
                              Text(
                                'Próxima Aplicação: ${m.proximaData} às ${m.horario}',
                              ),
                              if (m.observacoes.isNotEmpty)
                                Text('Observações: ${m.observacoes}'),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        final msg =
                                            'Olá ${widget.paciente.nome}! Passando para lembrar da sua aplicação de ${m.nome} agendada para ${m.proximaData} às ${m.horario}. Qualquer dúvida estou à disposição! 🩺';
                                        _enviarWhatsApp(
                                          context: context,
                                          telefone: widget.paciente.telefone,
                                          mensagem: msg,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.chat,
                                        color: Colors.white,
                                      ),
                                      label: const Text('Avisar no WhatsApp'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF25D366,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => editarMedicamento(index),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Editar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                        255,
                                        41,
                                        36,
                                        142,
                                      ),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: novoMedicamento,
        icon: const Icon(Icons.add),
        label: const Text('Medicamento'),
      ),
    );
  }
}

// ============================================================
// CADASTRO / EDIÇÃO MEDICAMENTO
// ============================================================
class CadastroMedicamentoPage extends StatefulWidget {
  final Medicamento? medicamentoParaEditar;

  const CadastroMedicamentoPage({super.key, this.medicamentoParaEditar});

  @override
  State<CadastroMedicamentoPage> createState() =>
      _CadastroMedicamentoPageState();
}

class _CadastroMedicamentoPageState extends State<CadastroMedicamentoPage> {
  late TextEditingController nomeController;
  late TextEditingController doseController;
  late TextEditingController viaController;
  late TextEditingController dataInicioController;
  late TextEditingController frequenciaController;
  late TextEditingController proximaDataController;
  late TextEditingController horarioController;
  late TextEditingController validadeController;
  late TextEditingController observacoesController;
  String _ultimoInicio = '';
  String _ultimaFrequencia = '';

  @override
  void initState() {
    super.initState();
    final m = widget.medicamentoParaEditar;
    nomeController = TextEditingController(text: m?.nome ?? '');
    doseController = TextEditingController(text: m?.dose ?? '');
    viaController = TextEditingController(text: m?.via ?? '');
    dataInicioController = TextEditingController(text: m?.dataInicio ?? '');
    frequenciaController = TextEditingController(text: m?.frequencia ?? '');
    proximaDataController = TextEditingController(text: m?.proximaData ?? '');
    horarioController = TextEditingController(text: m?.horario ?? '');
    validadeController = TextEditingController(text: m?.dataValidade ?? '');
    observacoesController = TextEditingController(text: m?.observacoes ?? '');
    _ultimoInicio = dataInicioController.text.trim();
    _ultimaFrequencia = frequenciaController.text.trim();
    dataInicioController.addListener(_atualizarProximaDataMedicamento);
    frequenciaController.addListener(_atualizarProximaDataMedicamento);
  }

  void _atualizarProximaDataMedicamento() {
    final inicio = dataInicioController.text.trim();
    final frequencia = frequenciaController.text.trim();
    if (inicio == _ultimoInicio && frequencia == _ultimaFrequencia) return;
    _ultimoInicio = inicio;
    _ultimaFrequencia = frequencia;

    final calculada = frequencia.isEmpty
        ? inicio
        : calcularProximaDataCiclo(inicio, frequencia);
    if (calculada != null && proximaDataController.text != calculada) {
      proximaDataController.text = calculada;
    }
  }

  @override
  void dispose() {
    dataInicioController.removeListener(_atualizarProximaDataMedicamento);
    frequenciaController.removeListener(_atualizarProximaDataMedicamento);
    nomeController.dispose();
    doseController.dispose();
    viaController.dispose();
    dataInicioController.dispose();
    frequenciaController.dispose();
    proximaDataController.dispose();
    horarioController.dispose();
    validadeController.dispose();
    observacoesController.dispose();
    super.dispose();
  }

  void _salvar() {
    if (nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do medicamento.')),
      );
      return;
    }

    final m = Medicamento(
      nome: nomeController.text.trim(),
      dose: doseController.text.trim(),
      via: viaController.text.trim(),
      frequencia: frequenciaController.text.trim(),
      dataInicio: dataInicioController.text.trim(),
      dataValidade: validadeController.text.trim(),
      proximaData: proximaDataController.text.trim(),
      horario: horarioController.text.trim(),
      observacoes: observacoesController.text.trim(),
    );

    Navigator.pop(context, m);
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    String? hint,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ehEdicao = widget.medicamentoParaEditar != null;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: Text(ehEdicao ? 'Editar Medicamento' : 'Novo Medicamento'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _campo('Nome do medicamento *', nomeController),
            const SizedBox(height: 12),
            _campo('Dose (ex: 500mg)', doseController),
            const SizedBox(height: 12),
            _campo('Via de administração (ex: Oral, IM, SC)', viaController),
            const SizedBox(height: 12),
            _campo(
              'Data da aplicação / início (DD/MM/AAAA)',
              dataInicioController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/AAAA',
              inputFormatters: [_formatadorData()],
            ),
            const SizedBox(height: 12),
            _campo(
              'Ciclo / periodicidade (ex: 15 dias)',
              frequenciaController,
            ),
            const SizedBox(height: 12),
            _campo(
              'Próxima aplicação (DD/MM/AAAA) - editável',
              proximaDataController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/AAAA',
              inputFormatters: [_formatadorData()],
            ),
            const SizedBox(height: 12),
            _campo(
              'Horário da aplicação (HH:MM) - editável',
              horarioController,
              keyboardType: TextInputType.datetime,
              hint: 'HH:MM',
              inputFormatters: [_formatadorHorario()],
            ),
            const SizedBox(height: 12),
            _campo(
              'Validade do remédio (DD/MM/AAAA)',
              validadeController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/AAAA',
              inputFormatters: [_formatadorData()],
            ),
            const SizedBox(height: 12),
            _campo('Observações', observacoesController),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save),
                label: Text(
                  ehEdicao ? 'Salvar alterações' : 'Salvar Medicamento',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// AGENDA DE COMPROMISSOS
// ============================================================
class AgendaPage extends StatefulWidget {
  final DateTime? dataInicial;

  const AgendaPage({super.key, this.dataInicial});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  List<Compromisso> compromissos = [];
  late DateTime diaSelecionado;

  @override
  void initState() {
    super.initState();
    diaSelecionado = widget.dataInicial ?? DateTime.now();
    _carregarCompromissos();
  }

  List<Compromisso> _deduplicarCompromissos(List<Compromisso> lista) {
    final unicos = <Compromisso>[];
    final chaves = <String>{};

    for (final item in lista) {
      final chave = '${item.pacienteNome}|${item.data}|${item.horario}|${item.tipo}|${item.descricao}';
      if (!chaves.contains(chave)) {
        chaves.add(chave);
        unicos.add(item);
      }
    }

    return unicos;
  }

  Future<void> _carregarCompromissos() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_compromissos');

    if (dados == null) return;

    try {
      final lista = jsonDecode(dados) as List;

      if (!mounted) return;

      setState(() {
        compromissos = _deduplicarCompromissos(
          lista
              .map((item) => Compromisso.fromMap(Map<String, dynamic>.from(item)))
              .toList(),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => compromissos = []);
    }
  }

  Future<bool> _salvarCompromissos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(
      'lista_compromissos',
      jsonEncode(compromissos.map((c) => c.toMap()).toList()),
    );
  }

  Future<void> novoCompromisso() async {
    final Compromisso? c = await Navigator.push<Compromisso>(
      context,
      MaterialPageRoute<Compromisso>(
        builder: (context) =>
            CadastroCompromissoPage(dataInicial: diaSelecionado),
      ),
    );

    if (c == null) return;

    final dataAplicacaoInicial =
        c.dataInicio.isNotEmpty ? c.dataInicio : c.data;
    final dataProximaAplicacao =
        c.proximaData.isNotEmpty ? c.proximaData : c.data;

    final baseId = DateTime.now().microsecondsSinceEpoch.remainder(2147483000);
    final novosParaSalvar = <Compromisso>[];

    final compromissoInicial = Compromisso(
      pacienteNome: c.pacienteNome,
      data: dataAplicacaoInicial,
      horario: c.horario,
      tipo: c.tipo,
      descricao: c.descricao,
      dataInicio: dataAplicacaoInicial,
      frequencia: c.frequencia,
      telefone: c.telefone,
      medicamentos: c.medicamentos,
      notificacaoId: baseId,
      ultimaDataAplicada: dataAplicacaoInicial,
      proximaData: dataProximaAplicacao,
    );

    final jaExisteInicial = compromissos.any(
      (item) =>
          item.pacienteNome == compromissoInicial.pacienteNome &&
          item.data == compromissoInicial.data &&
          item.horario == compromissoInicial.horario &&
          item.tipo == compromissoInicial.tipo,
    );
    if (!jaExisteInicial) {
      novosParaSalvar.add(compromissoInicial);
    }

    if (dataProximaAplicacao.isNotEmpty &&
        dataProximaAplicacao != dataAplicacaoInicial) {
      final compromissoProximo = Compromisso(
        pacienteNome: c.pacienteNome,
        data: dataProximaAplicacao,
        horario: c.horario,
        tipo: c.tipo,
        descricao: c.descricao,
        dataInicio: dataAplicacaoInicial,
        frequencia: c.frequencia,
        telefone: c.telefone,
        medicamentos: c.medicamentos,
        notificacaoId: baseId + 1,
        ultimaDataAplicada: dataAplicacaoInicial,
        proximaData: dataProximaAplicacao,
      );

      final jaExisteProximo = compromissos.any(
        (item) =>
            item.pacienteNome == compromissoProximo.pacienteNome &&
            item.data == compromissoProximo.data &&
            item.horario == compromissoProximo.horario &&
            item.tipo == compromissoProximo.tipo,
      );
      if (!jaExisteProximo) {
        novosParaSalvar.add(compromissoProximo);
      }
    }

    if (novosParaSalvar.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este agendamento já foi cadastrado.')),
        );
      }
      return;
    }

    final listaAnterior = [...compromissos];
    final listaAtualizada = [...compromissos, ...novosParaSalvar];
    setState(() => compromissos = _deduplicarCompromissos(listaAtualizada));

    final salvo = await _salvarCompromissos();
    if (!salvo) {
      setState(() => compromissos = listaAnterior);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar o compromisso.')),
      );
      return;
    }

    DateTime? lembrete;
    for (final item in novosParaSalvar) {
      final agendado = await agendarNotificacaoCompromisso(
        notificacaoId: item.notificacaoId,
        pacienteNome: item.pacienteNome,
        tipo: item.tipo.isEmpty ? 'Atendimento' : item.tipo,
        data: item.data,
        horario: item.horario,
      );
      lembrete ??= agendado;
    }

    final dataInicialDt = _lerData(dataAplicacaoInicial);
    if (dataInicialDt != null) {
      setState(() => diaSelecionado = dataInicialDt);
    }
    if (!mounted) return;
    final msgSucesso = novosParaSalvar.length > 1
        ? 'Agendado em $dataAplicacaoInicial e próxima aplicação em $dataProximaAplicacao!'
        : 'Compromisso salvo em ${novosParaSalvar.first.data}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lembrete == null
              ? '$msgSucesso (Verifique as permissões de notificação).'
              : '$msgSucesso Lembrete de 2 dias antes ativado.',
        ),
      ),
    );
  }

  Future<void> _editarCompromisso(int index) async {
    final original = compromissos[index];
    final atualizado = await Navigator.push<Compromisso>(
      context,
      MaterialPageRoute<Compromisso>(
        builder: (context) =>
            CadastroCompromissoPage(compromissoParaEditar: original),
      ),
    );
    if (atualizado == null) return;

    atualizado.notificacaoId = original.notificacaoId == 0
        ? DateTime.now().microsecondsSinceEpoch.remainder(2147483647)
        : original.notificacaoId;
    setState(() {
      compromissos[index] = atualizado;
      final data = _lerData(atualizado.data);
      if (data != null) diaSelecionado = data;
    });
    final salvo = await _salvarCompromissos();
    if (!salvo) {
      setState(() => compromissos[index] = original);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar as alterações.')),
        );
      }
      return;
    }
    await agendarNotificacaoCompromisso(
      notificacaoId: atualizado.notificacaoId,
      pacienteNome: atualizado.pacienteNome,
      tipo: atualizado.tipo.isEmpty ? 'Atendimento' : atualizado.tipo,
      data: atualizado.data,
      horario: atualizado.horario,
    );
  }

  Future<void> _excluirCompromisso(int index) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    final compromisso = compromissos[index];
    setState(() {
      compromissos.remove(compromisso);
    });
    final salvo = await _salvarCompromissos();
    if (!salvo) {
      setState(() => compromissos.insert(index, compromisso));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível excluir o compromisso.')),
        );
      }
      return;
    }
    if (compromisso.notificacaoId != 0) {
      await flutterLocalNotificationsPlugin.cancel(compromisso.notificacaoId);
    }
  }

  List<int> _indicesDoDia(DateTime dia) {
    final indices = <int>[];
    for (var index = 0; index < compromissos.length; index++) {
      final data = _lerData(compromissos[index].data);
      if (data != null &&
          data.year == dia.year &&
          data.month == dia.month &&
          data.day == dia.day) {
        indices.add(index);
      }
    }
    indices.sort(
      (a, b) => compromissos[a].horario.compareTo(compromissos[b].horario),
    );
    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final indicesDoDia = _indicesDoDia(diaSelecionado);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(title: const Text('Agenda')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CalendarDatePicker(
              key: ValueKey(
                '${diaSelecionado.year}-${diaSelecionado.month}-${diaSelecionado.day}',
              ),
              initialDate: diaSelecionado,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              onDateChanged: (data) {
                setState(() => diaSelecionado = data);
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pacientes em ${_formatarData(diaSelecionado)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text('${indicesDoDia.length} agendado(s)'),
                ],
              ),
            ),
            Expanded(
              child: indicesDoDia.isEmpty
                  ? const Center(
                      child: Text('Nenhum paciente agendado para este dia.'),
                    )
                  : ListView.builder(
                      itemCount: indicesDoDia.length,
                      itemBuilder: (context, itemIndex) {
                        final index = indicesDoDia[itemIndex];
                        final compromisso = compromissos[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.event),
                                  title: Text(
                                    compromisso.pacienteNome,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${compromisso.horario} · '
                                    '${compromisso.tipo.isEmpty ? 'Atendimento' : compromisso.tipo}'
                                    '${compromisso.frequencia.isEmpty ? '' : '\nCiclo: ${compromisso.frequencia}'}'
                                    '${compromisso.descricao.isEmpty ? '' : '\n${compromisso.descricao}'}',
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.chat,
                                        color: Color(0xFF25D366),
                                      ),
                                      tooltip: 'Avisar no WhatsApp',
                                      onPressed: () => _enviarWhatsApp(
                                        context: context,
                                        telefone: compromisso.telefone,
                                        mensagem: gerarMensagemConfirmacao(
                                          compromisso,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Editar compromisso',
                                      onPressed: () =>
                                          _editarCompromisso(index),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Excluir compromisso',
                                      onPressed: () =>
                                          _excluirCompromisso(index),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: novoCompromisso,
        icon: const Icon(Icons.add_task),
        label: const Text('Compromisso'),
      ),
    );
  }
}

// ============================================================
// CADASTRO DE COMPROMISSO
// ============================================================
class CadastroCompromissoPage extends StatefulWidget {
  final Compromisso? compromissoParaEditar;
  final DateTime? dataInicial;

  const CadastroCompromissoPage({
    super.key,
    this.compromissoParaEditar,
    this.dataInicial,
  });

  @override
  State<CadastroCompromissoPage> createState() =>
      _CadastroCompromissoPageState();
}

class _CadastroCompromissoPageState extends State<CadastroCompromissoPage> {
  final dataInicioController = TextEditingController();
  final frequenciaController = TextEditingController();
  final proximaDataController = TextEditingController();
  final horarioController = TextEditingController();
  final tipoController = TextEditingController();
  final descricaoController = TextEditingController();
  List<Paciente> pacientes = [];
  List<String> medicamentosSelecionados = [];
  Paciente? pacienteSelecionado;
  bool carregandoPacientes = true;
  bool salvando = false;
  String _ultimoInicio = '';
  String _ultimaFrequencia = '';

  @override
  void initState() {
    super.initState();
    final compromisso = widget.compromissoParaEditar;
    final hoje = _formatarData(widget.dataInicial ?? DateTime.now());
    final dataInicial = compromisso?.dataInicio.isNotEmpty == true
        ? compromisso!.dataInicio
        : compromisso?.data ?? hoje;
    dataInicioController.text = dataInicial;
    frequenciaController.text = compromisso?.frequencia ?? '';
    proximaDataController.text = compromisso?.data ?? dataInicial;
    horarioController.text = compromisso?.horario ?? '';
    tipoController.text = compromisso?.tipo ?? '';
    descricaoController.text = compromisso?.descricao ?? '';
    _ultimoInicio = dataInicioController.text.trim();
    _ultimaFrequencia = frequenciaController.text.trim();
    dataInicioController.addListener(_calcularProximaData);
    frequenciaController.addListener(_calcularProximaData);
    _carregarPacientes();
  }

  @override
  void dispose() {
    dataInicioController.removeListener(_calcularProximaData);
    frequenciaController.removeListener(_calcularProximaData);
    dataInicioController.dispose();
    frequenciaController.dispose();
    proximaDataController.dispose();
    horarioController.dispose();
    tipoController.dispose();
    descricaoController.dispose();
    super.dispose();
  }

  Future<void> _carregarPacientes() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');
    final lista = dados == null
        ? <Paciente>[]
        : (jsonDecode(dados) as List)
              .map((item) => Paciente.fromMap(Map<String, dynamic>.from(item)))
              .toList();
    if (!mounted) return;
    setState(() {
      pacientes = lista;
      carregandoPacientes = false;
      final nome = widget.compromissoParaEditar?.pacienteNome;
      if (nome != null) {
        for (final paciente in lista) {
          if (paciente.nome == nome) {
            pacienteSelecionado = paciente;
            medicamentosSelecionados = widget
                    .compromissoParaEditar
                    ?.medicamentos
                    .where(
                      (nomeMedicamento) => paciente.medicamentos.any(
                        (medicamento) => medicamento.nome == nomeMedicamento,
                      ),
                    )
                    .toList() ??
                [];
            break;
          }
        }
      }
    });
  }

  void _aplicarCicloDoMedicamento(Medicamento med) {
    if (med.dataInicio.isNotEmpty) {
      dataInicioController.text = med.dataInicio;
    }
    if (med.frequencia.isNotEmpty) {
      frequenciaController.text = med.frequencia;
    }
    if (med.horario.isNotEmpty && horarioController.text.trim().isEmpty) {
      horarioController.text = med.horario;
    }
    if (tipoController.text.trim().isEmpty) {
      tipoController.text = 'Aplicação';
    }
  }

  Future<void> _selecionarPaciente() async {
    final paciente = await showModalBottomSheet<Paciente>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in pacientes)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(item.nome),
                subtitle: Text(
                  item.telefone.isEmpty
                      ? 'Telefone não informado'
                      : item.telefone,
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (paciente != null && mounted) {
      setState(() {
        pacienteSelecionado = paciente;
        if (paciente.medicamentos.length == 1) {
          final unico = paciente.medicamentos.first;
          medicamentosSelecionados = [unico.nome];
          _aplicarCicloDoMedicamento(unico);
        } else {
          medicamentosSelecionados = [];
        }
      });
    }
  }

  Future<void> _selecionarMedicamentos() async {
    final paciente = pacienteSelecionado;
    if (paciente == null || paciente.medicamentos.isEmpty) return;

    final selecionados = Set<String>.from(medicamentosSelecionados);
    final resultado = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, atualizarModal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Medicamentos de ${paciente.nome}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final medicamento in paciente.medicamentos)
                CheckboxListTile(
                  value: selecionados.contains(medicamento.nome),
                  title: Text(medicamento.nome),
                  subtitle: Text(
                    [
                      medicamento.dose,
                      medicamento.via,
                      if (medicamento.frequencia.isNotEmpty)
                        'Ciclo: ${medicamento.frequencia}',
                    ].where((detalhe) => detalhe.isNotEmpty).join(' · '),
                  ),
                  onChanged: (marcado) => atualizarModal(() {
                    if (marcado == true) {
                      selecionados.add(medicamento.nome);
                    } else {
                      selecionados.remove(medicamento.nome);
                    }
                  }),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, selecionados.toList()),
                    child: const Text('Concluir'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (resultado != null && mounted) {
      setState(() {
        medicamentosSelecionados = resultado;
        if (resultado.isNotEmpty) {
          final medComCiclo = paciente.medicamentos.firstWhere(
            (m) => resultado.contains(m.nome) && m.frequencia.isNotEmpty,
            orElse: () => paciente.medicamentos.firstWhere(
              (m) => resultado.contains(m.nome),
            ),
          );
          _aplicarCicloDoMedicamento(medComCiclo);
        }
      });
    }
  }

  void _calcularProximaData() {
    final inicio = dataInicioController.text.trim();
    final frequencia = frequenciaController.text.trim();
    if (inicio == _ultimoInicio && frequencia == _ultimaFrequencia) return;
    _ultimoInicio = inicio;
    _ultimaFrequencia = frequencia;

    final proxima = frequencia.isEmpty
        ? inicio
        : calcularProximaDataCiclo(
            inicio,
            frequencia,
          );
    final texto = proxima ?? '';
    if (texto.isNotEmpty && proximaDataController.text != texto) {
      proximaDataController.text = texto;
    }
  }

  void _salvar() {
    if (salvando) return;

    final dataInicio = dataInicioController.text.trim();
    final dataAgendada = proximaDataController.text.trim();
    final partesHora = horarioController.text.trim().split(':');
    final horaCompleta =
        partesHora.length == 2 &&
        partesHora[0].length == 2 &&
        partesHora[1].length == 2;
    final hora = horaCompleta ? int.tryParse(partesHora[0]) : null;
    final minuto = horaCompleta ? int.tryParse(partesHora[1]) : null;

    if (pacienteSelecionado == null ||
        _lerData(dataInicio) == null ||
        _lerData(dataAgendada) == null ||
        hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione um paciente e informe data e horário válidos.',
          ),
        ),
      );
      return;
    }

    setState(() => salvando = true);

    final frequencia = frequenciaController.text.trim();
    final ultimaDataAplicada = dataInicio;

    final c = Compromisso(
      pacienteNome: pacienteSelecionado!.nome,
      data: dataAgendada,
      horario: horarioController.text.trim(),
      tipo: tipoController.text.trim(),
      descricao: descricaoController.text.trim(),
      dataInicio: dataInicio,
      frequencia: frequencia,
      telefone: pacienteSelecionado!.telefone,
      medicamentos: medicamentosSelecionados,
      notificacaoId: widget.compromissoParaEditar?.notificacaoId ?? 0,
      ultimaDataAplicada: ultimaDataAplicada,
      proximaData: dataAgendada,
    );

    Future.microtask(() {
      if (!mounted) return;
      Navigator.pop(context, c);
    });
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: Text(
          widget.compromissoParaEditar == null
              ? 'Novo Compromisso'
              : 'Editar Compromisso',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.person),
              title: Text(
                carregandoPacientes
                    ? 'Carregando pacientes...'
                    : pacienteSelecionado?.nome ?? 'Selecionar paciente *',
              ),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: carregandoPacientes || pacientes.isEmpty
                  ? null
                  : _selecionarPaciente,
            ),
            if (!carregandoPacientes && pacientes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Cadastre um paciente antes de criar um compromisso.',
                ),
              ),
            const SizedBox(height: 12),
            _campo(
              'Data inicial (DD/MM/AAAA) *',
              dataInicioController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [_formatadorData()],
            ),
            const SizedBox(height: 12),
            _campo('Periodicidade / ciclo (ex: 15 dias)', frequenciaController),
            const SizedBox(height: 12),
            _campo(
              'Próxima data (DD/MM/AAAA)',
              proximaDataController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [_formatadorData()],
            ),
            const SizedBox(height: 12),
            _campo(
              'Horário (HH:MM) *',
              horarioController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [_formatadorHorario()],
            ),
            const SizedBox(height: 12),
            _campo('Tipo (Ex: Consulta, Curativo, Medicação)', tipoController),
            const SizedBox(height: 12),
            _campo('Descrição / Observações', descricaoController),
            const SizedBox(height: 12),
            if (pacienteSelecionado != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _selecionarMedicamentos,
                  icon: const Icon(Icons.medication),
                  label: Text(
                    medicamentosSelecionados.isEmpty
                        ? 'Selecionar medicamentos do paciente'
                        : 'Medicamentos selecionados (${medicamentosSelecionados.length})',
                  ),
                ),
              ),
            if (pacienteSelecionado != null && medicamentosSelecionados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: medicamentosSelecionados
                      .map(
                        (nome) => Chip(
                          label: Text(nome),
                          avatar: const Icon(Icons.medication, size: 18),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: salvando ? null : _salvar,
                icon: const Icon(Icons.save),
                label: Text(
                  salvando
                      ? 'Salvando...'
                      : (widget.compromissoParaEditar == null
                          ? 'Salvar Compromisso'
                          : 'Salvar alterações'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 41, 36, 142),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
