// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  test('calcula próxima data do ciclo na agenda', () {
    expect(calcularProximaDataCiclo('15/05/2026', '15'), '30/05/2026');
    expect(calcularProximaDataCiclo('28/02/2024', '1 dia'), '29/02/2024');
    expect(calcularProximaDataCiclo('01/03/2024', 'quinzenal'), '16/03/2024');
    expect(calcularProximaDataCiclo('01/01/2024', 'mensal'), '31/01/2024');
  });

  test('não calcula ciclo com data ou periodicidade inválida', () {
    expect(calcularProximaDataCiclo('31/02/2024', '15 dias'), isNull);
    expect(calcularProximaDataCiclo('01/01/2024', ''), isNull);
  });

  testWidgets('puxa próxima data pelo ciclo e permite editar data e hora', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: CadastroCompromissoPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Data inicial (DD/MM/AAAA) *'),
      '15052026',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Periodicidade / ciclo (ex: 15 dias)'),
      '15',
    );
    await tester.pump();

    final campoProximaData = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Próxima data (DD/MM/AAAA)'),
    );
    expect(campoProximaData.readOnly, isFalse);
    expect(campoProximaData.controller?.text, '30/05/2026');

    // Caso o paciente não consiga naquele dia, permite editar data e horário
    await tester.enterText(
      find.widgetWithText(TextField, 'Próxima data (DD/MM/AAAA)'),
      '31052026',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Horário (HH:MM) *'),
      '1430',
    );
    await tester.pump();

    expect(campoProximaData.controller?.text, '31/05/2026');
    final campoHorario = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Horário (HH:MM) *'),
    );
    expect(campoHorario.controller?.text, '14:30');
  });

  testWidgets('agenda mostra calendário e pacientes do dia', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: AgendaPage()));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(
      find.text('Nenhum paciente agendado para este dia.'),
      findsOneWidget,
    );
  });

  testWidgets('agenda lista o paciente e ações do compromisso', (tester) async {
    final hoje = DateTime.now();
    final data =
        '${hoje.day.toString().padLeft(2, '0')}/${hoje.month.toString().padLeft(2, '0')}/${hoje.year}';
    SharedPreferences.setMockInitialValues({
      'lista_compromissos': jsonEncode([
        {
          'pacienteNome': 'Ana Souza',
          'data': data,
          'horario': '09:30',
          'tipo': 'Consulta',
          'descricao': '',
          'dataInicio': data,
          'frequencia': '',
          'telefone': '',
          'notificacaoId': 123,
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: AgendaPage()));
    await tester.pumpAndSettle();

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.byTooltip('Marcar como realizado'), findsNothing);
    expect(find.byTooltip('Editar compromisso'), findsOneWidget);
    expect(find.byTooltip('Excluir compromisso'), findsOneWidget);
  });
}
