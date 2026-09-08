import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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

Future<void> agendarNotificacaoMedicamento({
  required String pacienteNome,
  required String medicamentoNome,
  required String data,
  required String horario,
}) async {
  if (kIsWeb) return; // Notificações locais rodam no Android / iOS

  try {
    final partesData = data.split('/');
    final partesHora = horario.split(':');

    if (partesData.length < 2 || partesHora.length != 2) {
      return;
    }

    final dia = int.tryParse(partesData[0].trim());
    final mes = int.tryParse(partesData[1].trim());
    int? ano;
    if (partesData.length >= 3) {
      ano = int.tryParse(partesData[2].trim());
      if (ano != null && ano < 100) ano += 2000;
    } else {
      ano = DateTime.now().year;
    }

    final hora = int.tryParse(partesHora[0].trim());
    final minuto = int.tryParse(partesHora[1].trim());

    if (dia == null ||
        mes == null ||
        ano == null ||
        hora == null ||
        minuto == null) {
      return;
    }

    // Data da aplicação calculada pelo ciclo com o fuso horário local correto
    final dataAplicacao = tz.TZDateTime(
      tz.local,
      ano,
      mes,
      dia,
      hora,
      minuto,
    );

    // Agenda o lembrete exatamente 5 dias antes (na semana da aplicação)
    final dataNotificacao = dataAplicacao.subtract(const Duration(days: 5));
    final agora = tz.TZDateTime.now(tz.local);

    if (dataNotificacao.isBefore(agora)) {
      debugPrint('Aviso: Data da notificação ($dataNotificacao) já passou em relação a agora ($agora).');
      return;
    }

    final id =
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      'Nursehome 📲 Aviso WhatsApp',
      'Lembrete: Aplicação de $medicamentoNome para $pacienteNome agendada para $data às $horario (em 5 dias). Enviar mensagem para o paciente!',
      dataNotificacao,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nursehome_lembretes_semana',
          'Lembretes WhatsApp (5 dias antes)',
          channelDescription:
              'Aviso na semana da aplicação para envio de WhatsApp ao paciente',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode:
          AndroidScheduleMode.exactAllowWhileIdle,
    );
    debugPrint('Notificação agendada com sucesso para: $dataNotificacao');
  } catch (e) {
    debugPrint('Erro ao agendar notificação: $e');
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

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );

    // Solicita permissões de notificação no Android 13+
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  runApp(const MeuApp());
}

// ============================================================
// APP
// ============================================================
class MeuApp extends StatelessWidget {
  const MeuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
class Paciente {
  String nome;
  String nascimento;
  String telefone;
  String endereco;
  String alergias;
  String observacoes;
  String prontuario;
  List<Medicamento> medicamentos;

  Paciente({
    required this.nome,
    required this.nascimento,
    required this.telefone,
    required this.endereco,
    required this.alergias,
    required this.observacoes,
    required this.prontuario,
    required this.medicamentos,
  });

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
    };
  }

  factory Paciente.fromMap(Map<String, dynamic> map) {
    final listaMedicamentos = map['medicamentos'] as List? ?? [];
    return Paciente(
      nome: map['nome'] ?? '',
      nascimento: map['nascimento'] ?? '',
      telefone: map['telefone'] ?? '',
      endereco: map['endereco'] ?? '',
      alergias: map['alergias'] ?? '',
      observacoes: map['observacoes'] ?? '',
      prontuario: map['prontuario'] ?? '',
      medicamentos: listaMedicamentos
          .map(
            (item) => Medicamento.fromMap(
              Map<String, dynamic>.from(item),
            ),
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

  Compromisso({
    required this.pacienteNome,
    required this.data,
    required this.horario,
    required this.tipo,
    required this.descricao,
  });

  Map<String, dynamic> toMap() {
    return {
      'pacienteNome': pacienteNome,
      'data': data,
      'horario': horario,
      'tipo': tipo,
      'descricao': descricao,
    };
  }

  factory Compromisso.fromMap(Map<String, dynamic> map) {
    return Compromisso(
      pacienteNome: map['pacienteNome'] ?? '',
      data: map['data'] ?? '',
      horario: map['horario'] ?? '',
      tipo: map['tipo'] ?? '',
      descricao: map['descricao'] ?? '',
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
        MaterialPageRoute(
          builder: (context) => const PainelPrincipalPage(),
        ),
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
      MaterialPageRoute(
        builder: (context) => const CadastroPage(),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primeiro crie sua conta.'),
        ),
      );
      return;
    }

    if (email == emailCadastrado && senha == senhaCadastrada) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setBool('logado', true);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const PainelPrincipalPage(),
          ),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-mail ou senha incorretos.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _abrirCadastroConta,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color.fromARGB(255, 41, 36, 142),
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
                      backgroundColor:
                          const Color.fromARGB(255, 41, 36, 142),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha e-mail e senha.'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', email);
    await prefs.setString('senha', senha);
    await prefs.setBool('logado', false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conta criada com sucesso!'),
      ),
    );

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Criar conta'),
      ),
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
class PainelPrincipalPage extends StatelessWidget {
  const PainelPrincipalPage({super.key});

  void _abrir(
    BuildContext context,
    Widget pagina,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pagina,
      ),
    );
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
            icon: const Icon(
              Icons.logout,
              color: Colors.white,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('logado', false);

              if (!context.mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const HomePage(),
                ),
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
            _botao(
              context,
              'Home',
              Icons.home,
              () {},
            ),
            const SizedBox(height: 14),
            _botao(
              context,
              'Agenda',
              Icons.calendar_month,
              () => _abrir(
                context,
                const AgendaPage(),
              ),
            ),
            const SizedBox(height: 14),
            _botao(
              context,
              'Pacientes',
              Icons.people,
              () => _abrir(
                context,
                const PacientesPage(),
              ),
            ),
            const SizedBox(height: 14),
            _botao(
              context,
              'Prontuários',
              Icons.assignment,
              () => _abrir(
                context,
                const PacientesParaProntuarioPage(),
              ),
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
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
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
          .map(
            (item) => Paciente.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    });
  }

  Future<void> _salvarPacientes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lista_pacientes',
      jsonEncode(
        pacientes.map((p) => p.toMap()).toList(),
      ),
    );
  }

  Future<void> _novoPaciente() async {
    final paciente = await Navigator.push<Paciente>(
      context,
      MaterialPageRoute(
        builder: (_) => const CadastroPacientePage(),
      ),
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
        builder: (_) => DetalhesPacientePage(
          paciente: paciente,
        ),
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
      appBar: AppBar(
        title: const Text('Pacientes'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: pacientes.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum paciente cadastrado.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              )
            : ListView.builder(
                itemCount: pacientes.length,
                itemBuilder: (context, index) {
                  final paciente = pacientes[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text(
                        paciente.nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        paciente.telefone.isEmpty
                            ? 'Telefone não informado'
                            : paciente.telefone,
                      ),
                      onTap: () => _abrirPaciente(paciente),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
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
  State<CadastroPacientePage> createState() =>
      _CadastroPacientePageState();
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
        const SnackBar(
          content: Text('Informe o nome do paciente.'),
        ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
            _campo(
              'Alergias',
              alergiasController,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _campo(
              'Observações gerais',
              observacoesController,
              maxLines: 4,
            ),
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

  const DetalhesPacientePage({
    super.key,
    required this.paciente,
  });

  @override
  State<DetalhesPacientePage> createState() => _DetalhesPacientePageState();
}

class _DetalhesPacientePageState extends State<DetalhesPacientePage> {
  Future<void> _salvarAlteracoes() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_pacientes');

    if (dados == null) return;

    final lista = (jsonDecode(dados) as List)
        .map(
          (item) => Paciente.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();

    final index = lista.indexWhere(
      (p) => p.nome == widget.paciente.nome,
    );

    if (index != -1) {
      lista[index] = widget.paciente;
    }

    await prefs.setString(
      'lista_pacientes',
      jsonEncode(
        lista.map((p) => p.toMap()).toList(),
      ),
    );
  }

  Future<void> _editarPaciente() async {
    final Paciente? pacienteAtualizado = await Navigator.push<Paciente>(
      context,
      MaterialPageRoute(
        builder: (_) => CadastroPacientePage(
          pacienteParaEditar: widget.paciente,
        ),
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
        builder: (_) => MedicamentosPage(
          paciente: widget.paciente,
        ),
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
        builder: (_) => ProntuarioPacientePage(
          paciente: widget.paciente,
        ),
      ),
    );

    if (!mounted) return;
    await _salvarAlteracoes();
    setState(() {});
  }

  Widget _info(
    String titulo,
    String valor,
    IconData icone,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icone),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          valor.isEmpty ? 'Não informado' : valor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paciente = widget.paciente;

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
            _info(
              'Nascimento',
              paciente.nascimento,
              Icons.cake,
            ),
            _info(
              'Telefone',
              paciente.telefone,
              Icons.phone,
            ),
            _info(
              'Endereço',
              paciente.endereco,
              Icons.location_on,
            ),
            _info(
              'Alergias',
              paciente.alergias,
              Icons.warning,
            ),
            _info(
              'Observações',
              paciente.observacoes,
              Icons.notes,
            ),
            const SizedBox(height: 12),
            if (paciente.telefone.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final msg =
                        'Olá ${paciente.nome}! Aqui é do Nursehome. Como você está?';
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
                label: Text(
                  'Medicamentos (${paciente.medicamentos.length})',
                ),
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
          .map(
            (item) => Paciente.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Prontuários'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: pacientes.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum paciente cadastrado.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
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
                            builder: (_) => ProntuarioPacientePage(
                              paciente: paciente,
                            ),
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

  const ProntuarioPacientePage({
    super.key,
    required this.paciente,
  });

  @override
  State<ProntuarioPacientePage> createState() =>
      _ProntuarioPacientePageState();
}

class _ProntuarioPacientePageState extends State<ProntuarioPacientePage> {
  late TextEditingController prontuarioController;

  @override
  void initState() {
    super.initState();
    prontuarioController = TextEditingController(
      text: widget.paciente.prontuario,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: Text('Prontuário - ${widget.paciente.nome}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: prontuarioController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Digite as anotações do prontuário...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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

  const MedicamentosPage({
    super.key,
    required this.paciente,
  });

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

      if (medicamento.proximaData.isNotEmpty &&
          medicamento.horario.isNotEmpty) {
        await agendarNotificacaoMedicamento(
          pacienteNome: widget.paciente.nome,
          medicamentoNome: medicamento.nome,
          data: medicamento.proximaData,
          horario: medicamento.horario,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Medicamento salvo! Aviso prévio agendado para 5 dias antes da aplicação.',
            ),
          ),
        );
      }
    }
  }

  Future<void> editarMedicamento(int index) async {
    final Medicamento medicamentoAtual = widget.paciente.medicamentos[index];
    final Medicamento? medicamentoEditado = await Navigator.push<Medicamento>(
      context,
      MaterialPageRoute<Medicamento>(
        builder: (context) => CadastroMedicamentoPage(
          medicamentoParaEditar: medicamentoAtual,
        ),
      ),
    );

    if (medicamentoEditado != null) {
      setState(() {
        widget.paciente.medicamentos[index] = medicamentoEditado;
      });

      if (medicamentoEditado.proximaData.isNotEmpty &&
          medicamentoEditado.horario.isNotEmpty) {
        await agendarNotificacaoMedicamento(
          pacienteNome: widget.paciente.nome,
          medicamentoNome: medicamentoEditado.nome,
          data: medicamentoEditado.proximaData,
          horario: medicamentoEditado.horario,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medicamento atualizado com sucesso!'),
        ),
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
      appBar: AppBar(
        title: Text('Medicamentos - ${widget.paciente.nome}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: medicamentos.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum medicamento cadastrado.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
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
                                  'Próxima Aplicação: ${m.proximaData} às ${m.horario}'),
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
                                      icon: const Icon(Icons.chat,
                                          color: Colors.white),
                                      label: const Text('Avisar no WhatsApp'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF25D366),
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
                                          255, 41, 36, 142),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
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
// CADASTRO / EDIÇÃO MEDICAMENTO (Com cálculo automático)
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
  late TextEditingController frequenciaController;
  late TextEditingController inicioController;
  late TextEditingController validadeController;
  late TextEditingController proximaDataController;
  late TextEditingController horarioController;
  late TextEditingController observacoesController;

  @override
  void initState() {
    super.initState();
    final m = widget.medicamentoParaEditar;
    nomeController = TextEditingController(text: m?.nome ?? '');
    doseController = TextEditingController(text: m?.dose ?? '');
    viaController = TextEditingController(text: m?.via ?? '');
    frequenciaController = TextEditingController(text: m?.frequencia ?? '');
    inicioController = TextEditingController(text: m?.dataInicio ?? '');
    validadeController = TextEditingController(text: m?.dataValidade ?? '');
    proximaDataController = TextEditingController(text: m?.proximaData ?? '');
    horarioController = TextEditingController(text: m?.horario ?? '');
    observacoesController = TextEditingController(text: m?.observacoes ?? '');

    inicioController.addListener(_calcularProximaData);
    frequenciaController.addListener(_calcularProximaData);
  }

  @override
  void dispose() {
    inicioController.removeListener(_calcularProximaData);
    frequenciaController.removeListener(_calcularProximaData);
    nomeController.dispose();
    doseController.dispose();
    viaController.dispose();
    frequenciaController.dispose();
    inicioController.dispose();
    validadeController.dispose();
    proximaDataController.dispose();
    horarioController.dispose();
    observacoesController.dispose();
    super.dispose();
  }

  void _calcularProximaData() {
    final strInicio = inicioController.text.trim();
    final strFreq = frequenciaController.text.trim();

    if (strInicio.isEmpty) return;

    final partes = strInicio.split('/');
    if (partes.length != 3) return;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);

    if (dia == null || mes == null || ano == null) return;

    DateTime dataBase;
    try {
      dataBase = DateTime(ano, mes, dia);
    } catch (_) {
      return;
    }

    int diasAAcrescentar = 0;
    final matchNumero = RegExp(r'\d+').firstMatch(strFreq);

    if (matchNumero != null) {
      diasAAcrescentar = int.tryParse(matchNumero.group(0)!) ?? 0;
    } else if (strFreq.toLowerCase().contains('seman')) {
      diasAAcrescentar = 7;
    } else if (strFreq.toLowerCase().contains('quinzen')) {
      diasAAcrescentar = 15;
    } else if (strFreq.toLowerCase().contains('mensal')) {
      diasAAcrescentar = 30;
    } else if (strFreq.toLowerCase().contains('diári') ||
        strFreq.toLowerCase().contains('diari')) {
      diasAAcrescentar = 1;
    }

    if (diasAAcrescentar > 0) {
      final proxima = dataBase.add(Duration(days: diasAAcrescentar));
      final diaStr = proxima.day.toString().padLeft(2, '0');
      final mesStr = proxima.month.toString().padLeft(2, '0');
      final anoStr = proxima.year.toString();
      proximaDataController.text = '$diaStr/$mesStr/$anoStr';
    }
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
      dataInicio: inicioController.text.trim(),
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
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
              'Periodicidade / Ciclo (ex: 15 dias, 30 dias)',
              frequenciaController,
              hint: 'Ex: 15 dias (calcula a próxima automaticamente)',
            ),
            const SizedBox(height: 12),
            _campo(
              'Data de início (DD/MM/AAAA)',
              inicioController,
              keyboardType: TextInputType.datetime,
              hint: 'DD/MM/AAAA',
            ),
            const SizedBox(height: 12),
            _campo(
              'Próxima aplicação (DD/MM/AAAA)',
              proximaDataController,
              keyboardType: TextInputType.datetime,
              hint: 'Calculado automaticamente pelo ciclo',
            ),
            const SizedBox(height: 12),
            _campo(
              'Horário (HH:MM)',
              horarioController,
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 12),
            _campo('Validade do remédio', validadeController),
            const SizedBox(height: 12),
            _campo('Observações', observacoesController),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save),
                label: Text(
                    ehEdicao ? 'Salvar alterações' : 'Salvar Medicamento'),
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
  const AgendaPage({super.key});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  List<Compromisso> compromissos = [];

  @override
  void initState() {
    super.initState();
    _carregarCompromissos();
  }

  Future<void> _carregarCompromissos() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = prefs.getString('lista_compromissos');

    if (dados == null) return;

    final lista = jsonDecode(dados) as List;

    if (!mounted) return;

    setState(() {
      compromissos = lista
          .map((item) => Compromisso.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    });
  }

  Future<void> _salvarCompromissos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lista_compromissos',
      jsonEncode(compromissos.map((c) => c.toMap()).toList()),
    );
  }

  Future<void> novoCompromisso() async {
    final Compromisso? c = await Navigator.push<Compromisso>(
      context,
      MaterialPageRoute<Compromisso>(
        builder: (context) => const CadastroCompromissoPage(),
      ),
    );

    if (c != null) {
      setState(() {
        compromissos.add(c);
      });
      await _salvarCompromissos();
    }
  }

  void _excluirCompromisso(int index) async {
    setState(() {
      compromissos.removeAt(index);
    });
    await _salvarCompromissos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Agenda'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: compromissos.isEmpty
            ? const Center(
                child: Text(
                  'Nenhum compromisso agendado.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                itemCount: compromissos.length,
                itemBuilder: (context, index) {
                  final c = compromissos[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(
                        '${c.pacienteNome} - ${c.tipo}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle:
                          Text('${c.data} às ${c.horario}\n${c.descricao}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _excluirCompromisso(index),
                      ),
                    ),
                  );
                },
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
  const CadastroCompromissoPage({super.key});

  @override
  State<CadastroCompromissoPage> createState() =>
      _CadastroCompromissoPageState();
}

class _CadastroCompromissoPageState extends State<CadastroCompromissoPage> {
  final pacienteController = TextEditingController();
  final dataController = TextEditingController();
  final horarioController = TextEditingController();
  final tipoController = TextEditingController();
  final descricaoController = TextEditingController();

  void _salvar() {
    if (pacienteController.text.trim().isEmpty ||
        dataController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha ao menos o nome e a data.')),
      );
      return;
    }

    final c = Compromisso(
      pacienteNome: pacienteController.text.trim(),
      data: dataController.text.trim(),
      horario: horarioController.text.trim(),
      tipo: tipoController.text.trim(),
      descricao: descricaoController.text.trim(),
    );

    Navigator.pop(context, c);
  }

  Widget _campo(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 109, 175, 214),
      appBar: AppBar(
        title: const Text('Novo Compromisso'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _campo('Nome do Paciente *', pacienteController),
            const SizedBox(height: 12),
            _campo('Data (DD/MM/AAAA) *', dataController),
            const SizedBox(height: 12),
            _campo('Horário (HH:MM)', horarioController),
            const SizedBox(height: 12),
            _campo('Tipo (Ex: Consulta, Curativo, Medicação)', tipoController),
            const SizedBox(height: 12),
            _campo('Descrição / Observações', descricaoController),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Compromisso'),
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
