import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/exam_api.dart';
import 'package:frontend/main.dart';
import 'package:frontend/student_portal.dart';

class _FakeExamApi extends ExamApiClient {
  _FakeExamApi() : super(baseUrl: 'http://localhost');

  final exams = <ExamSummary>[
    const ExamSummary(
      id: 'published-exam',
      title: 'TOEIC Practice Test 04',
      duration: 75,
      totalQuestions: 5,
      isPublished: true,
      attempts: 12,
      averageScore: 340,
      createdAt: null,
    ),
    const ExamSummary(
      id: 'draft-exam',
      title: 'TOEIC Reading · Part 5–7',
      duration: 75,
      totalQuestions: 5,
      isPublished: false,
      attempts: 0,
      averageScore: 0,
      createdAt: null,
    ),
  ];

  final _questions = List<ExamQuestion>.generate(5, (index) {
    final correctIndex = index == 0 ? 0 : 1;
    return ExamQuestion(
      id: 'question-$index',
      order: index + 1,
      partNumber: 5,
      passage: '',
      prompt: index == 0
          ? 'The marketing team will present the campaign results _____ the quarterly meeting.'
          : 'Question ${index + 1} — choose the correct answer.',
      options: List<ExamOption>.generate(
        4,
        (optionIndex) => ExamOption(
          id: 'answer-$index-$optionIndex',
          key: String.fromCharCode(65 + optionIndex),
          text: index == 0 && optionIndex == 0
              ? 'during'
              : 'Option ${String.fromCharCode(65 + optionIndex)}',
        ),
      ),
      correctOptionKey: String.fromCharCode(65 + correctIndex),
    );
  });

  @override
  bool get isAuthenticated => true;

  @override
  Future<List<ExamSummary>> getTeacherExams() async => exams;

  @override
  Future<ExamStatistics> getStatistics() async => const ExamStatistics(
    totalExams: 2,
    totalAttempts: 12,
    averageScore: 340,
    attemptsLastSevenDays: [0, 1, 3, 2, 0, 4, 2],
    mostMissedQuestions: [
      {
        'questionOrder': 24,
        'examTitle': 'TOEIC Practice Test 04',
        'incorrectCount': 8,
      },
    ],
  );

  @override
  Future<List<ExamSummary>> getPublishedExams() async =>
      exams.where((exam) => exam.isPublished).toList();

  @override
  Future<ExamDetail> getExamDetail(String examId) async => ExamDetail(
    id: examId,
    title: 'TOEIC Practice Test 04',
    duration: 75,
    questions: _questions
        .map(
          (question) => ExamQuestion(
            id: question.id,
            order: question.order,
            partNumber: question.partNumber,
            passage: question.passage,
            prompt: question.prompt,
            options: question.options,
          ),
        )
        .toList(),
  );

  @override
  Future<ExamDetail> getManageExamDetail(String examId) async => ExamDetail(
    id: examId,
    title: 'TOEIC Practice Test 04',
    duration: 75,
    questions: _questions,
  );

  @override
  Future<void> publishExam(String examId) async {
    final index = exams.indexWhere((exam) => exam.id == examId);
    if (index < 0) return;
    final exam = exams[index];
    exams[index] = ExamSummary(
      id: exam.id,
      title: exam.title,
      duration: exam.duration,
      totalQuestions: exam.totalQuestions,
      isPublished: true,
      attempts: exam.attempts,
      averageScore: exam.averageScore,
      createdAt: exam.createdAt,
    );
  }

  @override
  Future<ExamSubmissionResult> submitExam(
    String examId,
    Map<String, String?> selectedAnswers,
  ) async {
    final details = _questions.map((question) {
      final selectedId = selectedAnswers[question.id];
      final selectedOption = selectedId == null
          ? null
          : question.options.firstWhere((option) => option.id == selectedId);
      final correct = selectedOption?.key == question.correctOptionKey;
      return ExamAnswerResult(
        questionId: question.id,
        selectedOptionKey: selectedOption?.key,
        correctOptionKey: question.correctOptionKey!,
        isCorrect: correct,
      );
    }).toList();
    final correct = details.where((answer) => answer.isCorrect).length;
    final answered = details.where(
      (answer) => answer.selectedOptionKey != null,
    );
    final answeredCount = answered.length;
    return ExamSubmissionResult(
      score: correct * 99,
      correctCount: correct,
      incorrectCount: answeredCount - correct,
      skippedCount: details.length - answeredCount,
      totalQuestions: details.length,
      answers: details,
    );
  }
}

WidgetTester _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  return tester;
}

void main() {
  testWidgets('shows the teacher exam dashboard', (tester) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TeacherExamApp(api: _FakeExamApi()));
    await tester.pumpAndSettle();

    expect(find.text('Chào buổi sáng, cô Lan 👋'), findsOneWidget);
    expect(find.text('Tổng số đề thi'), findsOneWidget);
    expect(find.text('Đề thi của tôi'), findsOneWidget);
    expect(find.text('TOEIC Practice Test 04'), findsAtLeastNWidgets(1));
    expect(find.text('Câu hỏi cần lưu ý'), findsOneWidget);
    expect(
      find.text('Top 10 câu hỏi sinh viên trả lời sai nhiều nhất'),
      findsOneWidget,
    );
    expect(find.text('Q.24'), findsOneWidget);
  });

  testWidgets('opens the exam preview for review', (tester) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TeacherExamApp(api: _FakeExamApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TOEIC Practice Test 04').first);
    await tester.pumpAndSettle();

    expect(find.text('Xem trước đề thi'), findsOneWidget);
    expect(find.textContaining('The marketing team'), findsOneWidget);
    expect(
      find.textContaining('Đáp án đúng chỉ hiển thị trong chế độ rà soát.'),
      findsOneWidget,
    );
  });

  testWidgets('publishes a draft when the teacher confirms it', (tester) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TeacherExamApp(api: _FakeExamApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xuất bản'));
    await tester.pump();

    expect(
      find.text('Đã xuất bản “TOEIC Reading · Part 5–7”.'),
      findsOneWidget,
    );
  });

  testWidgets('student can answer, clear, and confirm an incomplete exam', (
    tester,
  ) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TeacherExamApp(api: _FakeExamApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chuyển sang giao diện người học'));
    await tester.pumpAndSettle();

    expect(find.text('Đề thi đã xuất bản'), findsOneWidget);
    expect(find.text('75 phút'), findsOneWidget);
    expect(find.text('5 câu hỏi'), findsOneWidget);

    await tester.tap(find.text('Bắt đầu làm bài'));
    await tester.pump();
    expect(find.text('75:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('answer-option-A')));
    await tester.pump();
    expect(find.text('1/5 câu'), findsOneWidget);

    await tester.tap(find.text('Bỏ chọn đáp án'));
    await tester.pump();
    expect(find.text('0/5 câu'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('answer-option-A')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-nav-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('answer-option-A')));
    await tester.pump();
    expect(find.text('2/5 câu'), findsOneWidget);

    await tester.tap(find.text('Nộp bài'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bạn còn 3 câu chưa trả lời. Bạn vẫn muốn nộp bài chứ?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Tiếp tục làm bài'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('exam-timer')), findsOneWidget);

    await tester.tap(find.text('Nộp bài'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nộp bài ngay'));
    await tester.pumpAndSettle();

    expect(find.text('Bạn đã hoàn thành bài thi!'), findsOneWidget);
    expect(find.text('Đúng'), findsAtLeastNWidgets(1));
    expect(find.text('Sai'), findsAtLeastNWidgets(1));
    expect(find.text('Bỏ qua'), findsAtLeastNWidgets(1));
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Sai · đúng B'), findsOneWidget);
  });

  testWidgets('student exam submits automatically when the timer expires', (
    tester,
  ) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentPortal(
          api: _FakeExamApi(),
          onBackToTeacher: () {},
          durationOverride: const Duration(seconds: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu làm bài'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Bạn đã hoàn thành bài thi!'), findsOneWidget);
    expect(find.text('Bỏ qua'), findsAtLeastNWidgets(1));
  });

  testWidgets('warns when five minutes remain', (tester) async {
    _setDesktopSize(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StudentPortal(
          api: _FakeExamApi(),
          onBackToTeacher: () {},
          durationOverride: const Duration(seconds: 301),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu làm bài'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Còn 5 phút làm bài'), findsOneWidget);
    expect(find.text('Tiếp tục làm bài'), findsOneWidget);
  });
}
