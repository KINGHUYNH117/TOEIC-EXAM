import 'dart:async';

import 'package:flutter/material.dart';

import 'api_login_dialog.dart';
import 'exam_api.dart';

const _studentInk = Color(0xFF17233C);
const _studentMuted = Color(0xFF778198);
const _studentViolet = Color(0xFF6956D9);
const _studentCanvas = Color(0xFFF7F8FC);

class StudentPortal extends StatefulWidget {
  const StudentPortal({
    super.key,
    required this.api,
    required this.onBackToTeacher,
    this.durationOverride,
  });

  final ExamApiClient api;
  final VoidCallback onBackToTeacher;
  final Duration? durationOverride;

  @override
  State<StudentPortal> createState() => _StudentPortalState();
}

class _StudentPortalState extends State<StudentPortal> {
  List<ExamSummary> _exams = [];
  ExamDetail? _activeExam;
  ExamSubmissionResult? _result;
  final Map<String, String?> _answers = {};
  int _remainingSeconds = 0;
  int _currentQuestion = 0;
  bool _isLoading = true;
  bool _isTakingExam = false;
  bool _isSubmitted = false;
  bool _isSubmitting = false;
  bool _timeExpired = false;
  bool _warningShown = false;
  String? _loadError;
  String? _submitError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<ExamQuestion> get _questions => _activeExam?.questions ?? const [];

  int get _durationSeconds =>
      widget.durationOverride?.inSeconds ?? (_activeExam?.duration ?? 75) * 60;

  int get _answeredCount =>
      _answers.values.where((answer) => answer != null).length;

  int get _unansweredCount => _questions.length - _answeredCount;

  String get _formattedTime {
    final minutesPart = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  Future<void> _loadExams() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final exams = await widget.api.getPublishedExams();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _isLoading = false;
      });
    } on ExamApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _startExam(ExamSummary exam) async {
    if (!widget.api.isAuthenticated) {
      final authenticated = await showApiLoginDialog(
        context,
        widget.api,
        title: 'Đăng nhập để làm bài',
      );
      if (!authenticated || !mounted) return;
    }

    try {
      final detail = await widget.api.getExamDetail(exam.id);
      if (!mounted) return;
      if (detail.questions.isEmpty) {
        _showMessage('Đề thi chưa có câu hỏi.');
        return;
      }
      _timer?.cancel();
      setState(() {
        _activeExam = detail;
        _answers.clear();
        _result = null;
        _currentQuestion = 0;
        _remainingSeconds = _durationSeconds;
        _isTakingExam = true;
        _isSubmitted = false;
        _isSubmitting = false;
        _timeExpired = false;
        _warningShown = false;
        _submitError = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _isSubmitted || _isSubmitting) return;
        if (_remainingSeconds <= 1) {
          setState(() {
            _remainingSeconds = 0;
            _timeExpired = true;
          });
          _timer?.cancel();
          _submitExam();
          return;
        }
        setState(() => _remainingSeconds--);
        if (_remainingSeconds == 300 && !_warningShown) {
          _warningShown = true;
          _showTimeWarning();
        }
      });
    } on ExamApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _showTimeWarning() async {
    if (!mounted || _isSubmitted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.timer_outlined, color: Color(0xFFE89A38)),
        title: const Text('Còn 5 phút làm bài'),
        content: const Text(
          'Vui lòng kiểm tra lại câu trả lời. Bài thi sẽ tự động nộp khi hết giờ.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tiếp tục làm bài'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestSubmit() async {
    if (_isSubmitted || _isSubmitting || _timeExpired) return;
    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(
          Icons.fact_check_outlined,
          color: _studentViolet,
          size: 30,
        ),
        title: const Text('Xác nhận nộp bài'),
        content: Text(
          _unansweredCount == 0
              ? 'Bạn đã trả lời tất cả câu hỏi. Bạn có chắc chắn muốn nộp bài không?'
              : 'Bạn còn $_unansweredCount câu chưa trả lời. Bạn vẫn muốn nộp bài chứ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục làm bài'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _studentViolet),
            child: const Text('Nộp bài ngay'),
          ),
        ],
      ),
    );
    if (shouldSubmit == true && mounted) await _submitExam();
  }

  Future<void> _submitExam() async {
    final exam = _activeExam;
    if (exam == null || _isSubmitted || _isSubmitting) return;
    _timer?.cancel();
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final result = await widget.api.submitExam(exam.id, _answers);
      if (!mounted) return;
      setState(() {
        _result = result;
        _isSubmitting = false;
        _isSubmitted = true;
        _isTakingExam = false;
      });
    } on ExamApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = error.message;
      });
      if (_timeExpired) {
        _showMessage('Hết giờ nhưng chưa lưu được bài: ${error.message}');
      } else {
        _showMessage(error.message);
      }
    }
  }

  void _selectAnswer(String questionId, String answerId) {
    if (_isSubmitted || _isSubmitting || _timeExpired) return;
    setState(() {
      _answers[questionId] = _answers[questionId] == answerId ? null : answerId;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _pageShell({required Widget child}) => Scaffold(
    backgroundColor: _studentCanvas,
    body: Column(
      children: [
        _header(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: child,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header() => Container(
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEAECF2))),
    ),
    child: Row(
      children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: _studentViolet,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.auto_stories_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'examly',
          style: TextStyle(
            color: _studentInk,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF0EEFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'NGƯỜI HỌC',
            style: TextStyle(
              color: _studentViolet,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Spacer(),
        if (_isTakingExam)
          _timerBadge()
        else
          TextButton.icon(
            onPressed: widget.onBackToTeacher,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Giao diện giáo viên'),
          ),
        const SizedBox(width: 10),
        if (widget.api.isAuthenticated)
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () {
              widget.api.signOut();
              _showMessage('Đã đăng xuất. Cần đăng nhập lại để làm bài.');
            },
            icon: const Icon(Icons.logout, color: _studentMuted, size: 18),
          ),
        const CircleAvatar(
          radius: 16,
          backgroundColor: Color(0xFFE9D9C5),
          child: Text(
            'HV',
            style: TextStyle(
              color: Color(0xFF6F4C35),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'Học viên',
          style: TextStyle(
            color: _studentInk,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _timerBadge() {
    final isWarning = _remainingSeconds <= 300;
    final color = isWarning ? const Color(0xFFCC5656) : _studentViolet;
    return Container(
      key: const ValueKey('exam-timer'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF0EF) : const Color(0xFFF2F0FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: color, size: 17),
          const SizedBox(width: 7),
          Text(
            _formattedTime,
            style: TextStyle(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeScreen() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 37, 24, 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Xin chào, học viên 👋',
          style: TextStyle(
            color: _studentInk,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Chọn một đề thi đã được giảng viên xuất bản để bắt đầu.',
          style: TextStyle(color: _studentMuted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0EEFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: _studentViolet, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Thời gian sẽ bắt đầu đếm ngược ngay sau khi mở đề. Bài làm chỉ được ghi nhận khi bạn nộp bài thành công.',
                  style: TextStyle(
                    color: _studentInk,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Đề thi đã xuất bản',
                style: TextStyle(
                  color: _studentInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!_isLoading && _loadError == null)
              Text(
                '${_exams.length} đề thi',
                style: const TextStyle(color: _studentMuted, fontSize: 11),
              ),
            IconButton(
              tooltip: 'Tải lại danh sách đề thi',
              onPressed: _isLoading ? null : _loadExams,
              icon: const Icon(Icons.refresh, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_loadError != null)
          _loadErrorCard()
        else if (_exams.isEmpty)
          _emptyExamsCard()
        else
          for (final exam in _exams) ...[
            _examCard(exam),
            const SizedBox(height: 14),
          ],
      ],
    ),
  );

  Widget _loadErrorCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: _panelDecoration(),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: _studentViolet, size: 30),
        const SizedBox(height: 10),
        const Text(
          'Không thể tải đề thi từ máy chủ',
          style: TextStyle(
            color: _studentInk,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loadError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _studentMuted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loadExams,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );

  Widget _emptyExamsCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: _panelDecoration(),
    child: const Column(
      children: [
        Icon(Icons.menu_book_outlined, color: _studentMuted, size: 30),
        SizedBox(height: 10),
        Text(
          'Chưa có đề thi được xuất bản',
          style: TextStyle(
            color: _studentInk,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Đề thi sẽ xuất hiện tại đây sau khi giảng viên xuất bản.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _studentMuted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _examCard(ExamSummary exam) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                color: _studentViolet,
                size: 22,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.title,
                    style: const TextStyle(
                      color: _studentInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Đề thi đã được giảng viên xuất bản',
                    style: TextStyle(color: _studentMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F8F2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ĐANG MỞ',
                style: TextStyle(
                  color: Color(0xFF21845F),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(height: 1),
        ),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _ExamDetail(
              icon: Icons.timer_outlined,
              label: '${exam.duration} phút',
            ),
            _ExamDetail(
              icon: Icons.format_list_numbered_rounded,
              label: '${exam.totalQuestions} câu hỏi',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _startExam(exam),
            icon: const Icon(Icons.play_arrow_rounded, size: 19),
            label: const Text('Bắt đầu làm bài'),
            style: FilledButton.styleFrom(
              backgroundColor: _studentViolet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _examScreen() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeExam?.title ?? 'Bài thi',
                        style: const TextStyle(
                          color: _studentInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeExpired ? 'Đã hết giờ. Hệ thống đang nộp bài.' : 'Chọn một đáp án cho mỗi câu. Đáp án được lưu tạm trong phiên thi.',
                        style: const TextStyle(
                          color: _studentMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$_answeredCount/${_questions.length} câu',
                  style: const TextStyle(
                    color: _studentViolet,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_submitError != null)
            MaterialBanner(
              content: Text(_submitError!),
              leading: const Icon(
                Icons.error_outline,
                color: Color(0xFFC45B5B),
              ),
              actions: [
                TextButton(
                  onPressed: _isSubmitting ? null : _submitExam,
                  child: const Text('Thử nộp lại'),
                ),
              ],
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: compact
                  ? Column(
                      children: [
                        _questionNavigator(),
                        const SizedBox(height: 16),
                        _questionCard(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 225, child: _questionNavigator()),
                        const SizedBox(width: 18),
                        Expanded(child: _questionCard()),
                      ],
                    ),
            ),
          ),
          _examFooter(),
        ],
      );
    },
  );

  Widget _questionNavigator() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Danh sách câu hỏi',
          style: TextStyle(
            color: _studentInk,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Nhấn vào số câu để di chuyển',
          style: TextStyle(color: _studentMuted, fontSize: 10),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_questions.length, (index) {
            final question = _questions[index];
            final selected = _currentQuestion == index;
            final answered = _answers[question.id] != null;
            return InkWell(
              key: ValueKey('question-nav-$index'),
              onTap: () => setState(() => _currentQuestion = index),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 38,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? _studentViolet
                      : answered
                      ? const Color(0xFFE9F8F2)
                      : const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? _studentViolet
                        : answered
                        ? const Color(0xFFBCE8D5)
                        : const Color(0xFFE9ECF3),
                  ),
                ),
                child: Text(
                  '${question.order}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : answered
                        ? const Color(0xFF21845F)
                        : _studentMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 13),
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF31A879), size: 15),
            const SizedBox(width: 7),
            Text(
              'Đã trả lời $_answeredCount',
              style: const TextStyle(color: _studentMuted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            const Icon(
              Icons.radio_button_unchecked,
              color: Color(0xFFADB5C3),
              size: 15,
            ),
            const SizedBox(width: 7),
            Text(
              'Còn $_unansweredCount câu',
              style: const TextStyle(color: _studentMuted, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _questionCard() {
    final question = _questions[_currentQuestion];
    final selectedAnswer = _answers[question.id];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEFF),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'CÂU ${question.order}',
                  style: const TextStyle(
                    color: _studentViolet,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${_currentQuestion + 1} / ${_questions.length}',
                style: const TextStyle(color: _studentMuted, fontSize: 10),
              ),
            ],
          ),
          if (question.passage.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                question.passage,
                style: const TextStyle(
                  color: _studentInk,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            question.prompt,
            style: const TextStyle(
              color: _studentInk,
              fontSize: 17,
              height: 1.65,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 25),
          for (final option in question.options)
            _answerOption(question, option, selectedAnswer),
          const SizedBox(height: 8),
          if (selectedAnswer != null && !_timeExpired)
            TextButton.icon(
              onPressed: () => setState(() => _answers[question.id] = null),
              icon: const Icon(Icons.backspace_outlined, size: 15),
              label: const Text('Bỏ chọn đáp án'),
              style: TextButton.styleFrom(
                foregroundColor: _studentMuted,
                textStyle: const TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _answerOption(
    ExamQuestion question,
    ExamOption option,
    String? selectedAnswer,
  ) {
    final selected = selectedAnswer == option.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFF3F1FF) : Colors.white,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: ValueKey('answer-option-${option.key}'),
          onTap: _isSubmitted || _isSubmitting || _timeExpired
              ? null
              : () => _selectAnswer(question.id, option.id),
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? _studentViolet : const Color(0xFFE9ECF3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? _studentViolet : const Color(0xFFF5F6FA),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    option.key,
                    style: TextStyle(
                      color: selected ? Colors.white : _studentMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(
                      color: selected ? _studentViolet : _studentInk,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: _studentViolet,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _examFooter() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFEAECF2))),
    ),
    child: Row(
      children: [
        OutlinedButton.icon(
          onPressed: _currentQuestion == 0 || _timeExpired || _isSubmitting
              ? null
              : () => setState(() => _currentQuestion--),
          icon: const Icon(Icons.arrow_back, size: 15),
          label: const Text('Câu trước'),
        ),
        const Spacer(),
        if (_timeExpired || _submitError != null)
          FilledButton.icon(
            onPressed: _isSubmitting ? null : _submitExam,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 15),
            label: const Text('Nộp lại'),
            style: FilledButton.styleFrom(
              backgroundColor: _studentViolet,
              foregroundColor: Colors.white,
            ),
          )
        else ...[
          TextButton(
            onPressed: _isSubmitting ? null : _requestSubmit,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFCC5656),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Nộp bài'),
          ),
          const SizedBox(width: 9),
          FilledButton.icon(
            onPressed: _isSubmitting
                ? null
                : _currentQuestion == _questions.length - 1
                ? _requestSubmit
                : () => setState(() => _currentQuestion++),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _currentQuestion == _questions.length - 1
                        ? Icons.fact_check_outlined
                        : Icons.arrow_forward,
                    size: 15,
                  ),
            label: Text(
              _isSubmitting
                  ? 'Đang lưu...'
                  : _currentQuestion == _questions.length - 1
                  ? 'Hoàn thành'
                  : 'Câu tiếp',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _studentViolet,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _resultScreen() {
    final exam = _activeExam!;
    final result = _result!;
    final reviewByQuestion = {
      for (final answer in result.answers) answer.questionId: answer,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              const SizedBox(height: 22),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8F2),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Color(0xFF31A879),
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bạn đã hoàn thành bài thi!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _studentInk,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${exam.title} · Kết quả đã được lưu',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _studentMuted, fontSize: 11),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: _panelDecoration(),
                child: Column(
                  children: [
                    const Text(
                      'ĐIỂM THI',
                      style: TextStyle(
                        color: _studentMuted,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      result.score.toStringAsFixed(0),
                      style: const TextStyle(
                        color: _studentViolet,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${result.correctCount} / ${result.totalQuestions} câu đúng',
                      style: const TextStyle(
                        color: _studentMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: Row(
                        children: [
                          Expanded(
                            child: _resultMetric(
                              'Đúng',
                              '${result.correctCount}',
                              const Color(0xFF21845F),
                              const Color(0xFFE9F8F2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _resultMetric(
                              'Sai',
                              '${result.incorrectCount}',
                              const Color(0xFFC45B5B),
                              const Color(0xFFFFF0EF),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _resultMetric(
                              'Bỏ qua',
                              '${result.skippedCount}',
                              const Color(0xFF9A6A18),
                              const Color(0xFFFFF5E6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 17),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(19),
                decoration: _panelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rà soát đáp án',
                      style: TextStyle(
                        color: _studentInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final question in exam.questions)
                      _resultAnswerRow(question, reviewByQuestion[question.id]),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _activeExam = null;
                    _result = null;
                    _isSubmitted = false;
                    _isTakingExam = false;
                    _remainingSeconds = 0;
                    _answers.clear();
                  });
                  _loadExams();
                },
                icon: const Icon(Icons.home_outlined, size: 17),
                label: const Text('Về danh sách đề thi'),
                style: FilledButton.styleFrom(
                  backgroundColor: _studentViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultMetric(
    String label,
    String value,
    Color foreground,
    Color background,
  ) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: foreground,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _resultAnswerRow(ExamQuestion question, ExamAnswerResult? result) {
    final isSkipped = result?.selectedOptionKey == null;
    final isCorrect = result?.isCorrect == true;
    final color = isSkipped
        ? const Color(0xFF9A6A18)
        : isCorrect
        ? const Color(0xFF21845F)
        : const Color(0xFFC45B5B);
    final label = isSkipped
        ? 'Bỏ qua · đúng ${result?.correctOptionKey ?? '?'}'
        : isCorrect
        ? 'Đúng'
        : 'Sai · đúng ${result?.correctOptionKey ?? '?'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSkipped
                  ? const Color(0xFFFFF5E6)
                  : isCorrect
                  ? const Color(0xFFE9F8F2)
                  : const Color(0xFFFFF0EF),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              'Q${question.order}',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              question.prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _studentInk, fontSize: 10),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFEAECF2)),
  );

  @override
  Widget build(BuildContext context) {
    return _pageShell(
      child: _isSubmitted
          ? _resultScreen()
          : _isTakingExam
          ? _examScreen()
          : _homeScreen(),
    );
  }
}

class _ExamDetail extends StatelessWidget {
  const _ExamDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: _studentMuted, size: 16),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          color: _studentMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
