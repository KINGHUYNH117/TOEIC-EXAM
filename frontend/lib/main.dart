import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frontend/api_login_dialog.dart';
import 'package:frontend/exam_api.dart';
import 'package:frontend/student_portal.dart';

void main() {
  runApp(const TeacherExamApp());
}

const _ink = Color(0xFF17233C);
const _muted = Color(0xFF778198);
const _violet = Color(0xFF6956D9);
const _canvas = Color(0xFFF7F8FC);

class TeacherExamApp extends StatelessWidget {
  const TeacherExamApp({super.key, this.api});

  final ExamApiClient? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Examly · Quản lý đề thi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: _violet),
        fontFamily: 'Arial',
      ),
      home: _ExamlyHome(api: api ?? ExamApiClient()),
    );
  }
}

class _ExamlyHome extends StatefulWidget {
  const _ExamlyHome({required this.api});

  final ExamApiClient api;

  @override
  State<_ExamlyHome> createState() => _ExamlyHomeState();
}

class _ExamlyHomeState extends State<_ExamlyHome> {
  bool _isStudent = false;

  @override
  Widget build(BuildContext context) {
    if (_isStudent) {
      return StudentPortal(
        api: widget.api,
        onBackToTeacher: () => setState(() => _isStudent = false),
      );
    }
    return TeacherDashboard(
      api: widget.api,
      onOpenStudent: () => setState(() => _isStudent = true),
    );
  }
}

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key, required this.api, this.onOpenStudent});

  final ExamApiClient api;
  final VoidCallback? onOpenStudent;

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  List<ExamSummary> _exams = [];
  ExamStatistics? _statistics;
  ExamApiException? _loadError;
  bool _isLoading = true;
  bool _isImporting = false;

  String _filter = 'Tất cả';
  String _search = '';
  String? _selectedFileName;
  int _selectedNavigation = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getTeacherExams(),
        widget.api.getStatistics(),
      ]);
      if (!mounted) return;
      setState(() {
        _exams = results[0] as List<ExamSummary>;
        _statistics = results[1] as ExamStatistics;
        _isLoading = false;
      });
    } on ExamApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  List<ExamSummary> get _visibleExams => _exams.where((exam) {
    final matchesFilter =
        _filter == 'Tất cả' ||
        (_filter == 'Đã xuất bản' && exam.isPublished) ||
        (_filter == 'Bản nháp' && !exam.isPublished);
    final matchesSearch = exam.title.toLowerCase().contains(
      _search.toLowerCase(),
    );
    return matchesFilter && matchesSearch;
  }).toList();

  Future<void> _pickDocx() async {
    if (!await _ensureLogin()) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.docx')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chỉ chấp nhận tệp Word có định dạng .docx.'),
        ),
      );
      return;
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showMessage(
        'Không đọc được nội dung file. Vui lòng chọn lại file DOCX.',
      );
      return;
    }
    setState(() {
      _selectedFileName = file.name;
      _isImporting = true;
    });
    try {
      final imported = await widget.api.importDocx(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _selectedFileName = null;
        _isImporting = false;
      });
      _showMessage('${imported['message'] ?? 'Đề thi đã được import và lưu.'}');
      await _loadDashboard();
    } on ExamApiException catch (error) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      _showMessage(error.message);
    }
  }

  Future<bool> _ensureLogin() async {
    if (widget.api.isAuthenticated) return true;
    return showApiLoginDialog(
      context,
      widget.api,
      title: 'Đăng nhập giảng viên',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _publish(ExamSummary exam) async {
    if (!await _ensureLogin()) return;
    try {
      await widget.api.publishExam(exam.id);
      await _loadDashboard();
      _showMessage('Đã xuất bản “${exam.title}”.');
    } on ExamApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _preview(ExamSummary exam) async {
    if (!await _ensureLogin()) return;
    try {
      final detail = await widget.api.getManageExamDetail(exam.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined, color: _violet),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Xem trước đề thi',
                              style: TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              detail.title,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _previewNotice(),
                      const SizedBox(height: 20),
                      for (final question in detail.questions)
                        _questionPreview(question),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } on ExamApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Widget _previewNotice() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F0FF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.visibility_outlined, color: _violet, size: 18),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Kiểm tra nội dung, thứ tự câu, đáp án và hình ảnh trước khi xuất bản. Đáp án đúng chỉ hiển thị trong chế độ rà soát.',
            style: TextStyle(color: _ink, fontSize: 12, height: 1.5),
          ),
        ),
      ],
    ),
  );

  Widget _questionPreview(ExamQuestion question) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE9ECF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Câu ${question.order}',
          style: const TextStyle(
            color: _violet,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        if (question.passage.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            question.passage,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.55),
          ),
        ],
        const SizedBox(height: 9),
        Text(
          question.prompt,
          style: const TextStyle(color: _ink, height: 1.55),
        ),
        const SizedBox(height: 12),
        for (final answer in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Icon(
                  answer.key == question.correctOptionKey
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: answer.key == question.correctOptionKey
                      ? const Color(0xFF2EA87A)
                      : const Color(0xFFB7BECC),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${answer.key}. ${answer.text}',
                    style: TextStyle(
                      color: answer.key == question.correctOptionKey
                          ? const Color(0xFF21845F)
                          : _muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final narrow = constraints.maxWidth < 600;
        return Scaffold(
          body: Row(
            children: [
              if (!compact) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _topBar(compact),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: narrow ? 18 : 36,
                          vertical: 28,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: _loadError != null
                                ? _loadErrorView()
                                : _isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(80),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : _selectedNavigation == 0
                                ? _dashboardContent(narrow)
                                : _secondaryContent(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: compact ? _mobileNavigation() : null,
        );
      },
    );
  }

  Widget _loadErrorView() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEAECF2)),
    ),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: _violet, size: 34),
        const SizedBox(height: 12),
        const Text(
          'Không tải được dữ liệu từ máy chủ',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _loadError?.message ?? 'Kiểm tra kết nối API rồi thử lại.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          children: [
            OutlinedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
            ),
            if (!widget.api.isAuthenticated)
              FilledButton.icon(
                onPressed: () async {
                  if (await _ensureLogin()) await _loadDashboard();
                },
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Đăng nhập'),
                style: _primaryButtonStyle(),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _sidebar() => Container(
    width: 248,
    color: const Color(0xFF18233B),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 27, 20, 38),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _violet,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'examly',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 0, 0, 12),
          child: Text(
            'KHÔNG GIAN LÀM VIỆC',
            style: TextStyle(
              color: Color(0xFF78849D),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        _navItem(0, Icons.grid_view_rounded, 'Tổng quan'),
        _navItem(1, Icons.library_books_outlined, 'Ngân hàng đề'),
        _navItem(2, Icons.bar_chart_rounded, 'Thống kê'),
        const Spacer(),
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF222F4A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE9D9C5),
                child: Text(
                  'ML',
                  style: TextStyle(
                    color: Color(0xFF6F4C35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Minh Lan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Giảng viên',
                      style: TextStyle(color: Color(0xFF9AA5BD), fontSize: 10),
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_horiz, color: Color(0xFF9AA5BD), size: 19),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _selectedNavigation == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFF2A3653) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _selectedNavigation = index),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? const Color(0xFFB9AEFF)
                      : const Color(0xFF9AA5BD),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFB7C0D1),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool compact) => Container(
    height: 76,
    padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 36),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEAECF2))),
    ),
    child: Row(
      children: [
        if (compact) ...[
          Container(
            width: 33,
            height: 33,
            decoration: BoxDecoration(
              color: _violet,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'examly',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ] else
          const Text(
            'Không gian giảng viên  /  Đề thi',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        const Spacer(),
        if (widget.api.isAuthenticated)
          IconButton(
            tooltip: 'Đăng xuất khỏi API',
            onPressed: () {
              widget.api.signOut();
              _loadDashboard();
            },
            icon: const Icon(Icons.logout_rounded, color: _muted),
          )
        else
          TextButton.icon(
            onPressed: () async {
              if (await _ensureLogin()) await _loadDashboard();
            },
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Đăng nhập'),
          ),
        IconButton(
          tooltip: 'Chuyển sang giao diện người học',
          onPressed: widget.onOpenStudent,
          icon: const Icon(Icons.school_outlined, color: _violet),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFE9D9C5),
            child: Text(
              'ML',
              style: TextStyle(
                color: Color(0xFF6F4C35),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'Minh Lan',
            style: TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, color: _muted, size: 18),
        ],
      ],
    ),
  );

  Widget _dashboardContent(bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chào buổi sáng, cô Lan 👋',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Quản lý đề thi và theo dõi kết quả học tập của lớp.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!narrow)
            FilledButton.icon(
              onPressed: _pickDocx,
              icon: const Icon(Icons.upload_file_rounded, size: 17),
              label: const Text('Import đề thi'),
              style: _primaryButtonStyle(),
            ),
        ],
      ),
      if (narrow) ...[
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _pickDocx,
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text('Import đề thi'),
            style: _primaryButtonStyle(),
          ),
        ),
      ],
      const SizedBox(height: 26),
      if (_selectedFileName != null) _selectedFileBanner(),
      _statCards(narrow),
      const SizedBox(height: 27),
      _uploadCard(narrow),
      const SizedBox(height: 30),
      _examList(),
      const SizedBox(height: 27),
      _analytics(narrow),
      const SizedBox(height: 20),
    ],
  );

  ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
    backgroundColor: _violet,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _statCards(bool narrow) {
    final stats = _statistics;
    final data = [
      (
        'Tổng số đề thi',
        '${stats?.totalExams ?? 0}',
        'Đề thi trong cơ sở dữ liệu',
        Icons.description_outlined,
        Color(0xFFF0EEFF),
        _violet,
      ),
      (
        'Lượt làm bài',
        '${stats?.totalAttempts ?? 0}',
        'Bài làm đã được nộp',
        Icons.people_alt_outlined,
        Color(0xFFE9F8F2),
        Color(0xFF31A879),
      ),
      (
        'Điểm trung bình',
        (stats?.averageScore ?? 0).toStringAsFixed(1),
        'Điểm trung bình theo dữ liệu bài làm',
        Icons.track_changes_outlined,
        Color(0xFFFFF4E8),
        Color(0xFFE89A38),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 25),
      child: narrow
          ? Column(
              children: [
                for (final item in data) ...[
                  _statCard(item),
                  const SizedBox(height: 12),
                ],
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < data.length; i++) ...[
                  Expanded(child: _statCard(data[i])),
                  if (i < data.length - 1) const SizedBox(width: 15),
                ],
              ],
            ),
    );
  }

  Widget _statCard((String, String, String, IconData, Color, Color) item) =>
      Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFEAECF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.$1,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: item.$5,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.$4, color: item.$6, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.$2,
              style: const TextStyle(
                color: _ink,
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(item.$3, style: TextStyle(color: item.$6, fontSize: 10)),
          ],
        ),
      );

  Widget _selectedFileBanner() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0EEFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE3DFFF)),
    ),
    child: Row(
      children: [
        if (_isImporting)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          const Icon(Icons.description_outlined, color: _violet, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            _isImporting
                ? 'Đang gửi $_selectedFileName để kiểm tra và lưu...'
                : 'Đã chọn $_selectedFileName',
            style: const TextStyle(color: _ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _uploadCard(bool narrow) => InkWell(
    onTap: _isImporting ? null : _pickDocx,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 26, vertical: 21),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F0FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3DFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.drive_folder_upload_outlined,
              color: _violet,
              size: 23,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tạo đề thi từ file Word',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Tải lên .docx để hệ thống kiểm tra cấu trúc trước khi lưu.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!narrow)
            OutlinedButton(
              onPressed: _isImporting ? null : _pickDocx,
              style: OutlinedButton.styleFrom(
                foregroundColor: _violet,
                side: const BorderSide(color: Color(0xFFD4CEFF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Chọn file .docx',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          if (narrow)
            const Icon(Icons.arrow_forward_ios, color: _violet, size: 15),
        ],
      ),
    ),
  );

  Widget _examList() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEAECF2)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 19, 21, 16),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đề thi của tôi',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Theo dõi và quản lý các đề thi của bạn',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 180,
                height: 38,
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'Tìm đề thi...',
                    hintStyle: const TextStyle(color: _muted, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, size: 17),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: const Color(0xFFF8F9FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFFE9ECF3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFFE9ECF3)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 0, 21, 12),
          child: Row(
            children: [
              for (final option in ['Tất cả', 'Đã xuất bản', 'Bản nháp'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _filterChip(option),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 680) {
              return Column(
                children: _visibleExams
                    .map((exam) => _examCompactTile(exam))
                    .toList(),
              );
            }
            return _examTable();
          },
        ),
      ],
    ),
  );

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () => setState(() => _filter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0EEFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _violet : _muted,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _examTable() => Column(
    children: [
      Container(
        color: const Color(0xFFFAFBFD),
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 11),
        child: const Row(
          children: [
            Expanded(flex: 4, child: _TableHeading('TÊN ĐỀ THI')),
            Expanded(flex: 2, child: _TableHeading('TRẠNG THÁI')),
            Expanded(flex: 2, child: _TableHeading('LƯỢT THI')),
            Expanded(flex: 2, child: _TableHeading('ĐIỂM TB')),
            Expanded(flex: 2, child: _TableHeading('CẬP NHẬT')),
            SizedBox(width: 88),
          ],
        ),
      ),
      for (final exam in _visibleExams) _examTableRow(exam),
      if (_visibleExams.isEmpty)
        const Padding(
          padding: EdgeInsets.all(25),
          child: Text(
            'Không tìm thấy đề thi phù hợp.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ),
    ],
  );

  Widget _examTableRow(ExamSummary exam) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFFF0F1F5))),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: InkWell(
            onTap: () => _preview(exam),
            child: Row(
              children: [
                Container(
                  width: 37,
                  height: 37,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F0FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: _violet,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${exam.totalQuestions} câu · ${exam.duration} phút',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _statusBadge(exam.isPublished),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            exam.attempts == 0 ? '—' : '${exam.attempts}',
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            exam.averageScore == 0 ? '—' : exam.averageScore.toStringAsFixed(1),
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            _formatDate(exam.createdAt),
            style: const TextStyle(color: _muted, fontSize: 9),
          ),
        ),
        SizedBox(
          width: 88,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconAction(
                Icons.visibility_outlined,
                'Xem trước',
                () => _preview(exam),
              ),
              if (!exam.isPublished)
                _iconAction(
                  Icons.rocket_launch_outlined,
                  'Xuất bản',
                  () => _publish(exam),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _examCompactTile(ExamSummary exam) => ListTile(
    onTap: () => _preview(exam),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F0FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.description_outlined, color: _violet, size: 18),
    ),
    title: Text(
      exam.title,
      style: const TextStyle(
        color: _ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          _statusBadge(exam.isPublished),
          const SizedBox(width: 8),
          Text(
            '${exam.attempts} lượt · ${exam.totalQuestions} câu',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    ),
    trailing: !exam.isPublished
        ? IconButton(
            tooltip: 'Xuất bản đề thi',
            onPressed: () => _publish(exam),
            icon: const Icon(
              Icons.rocket_launch_outlined,
              color: _violet,
              size: 19,
            ),
          )
        : const Icon(Icons.chevron_right, color: _muted),
  );

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _statusBadge(bool published) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: published ? const Color(0xFFE9F8F2) : const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: published
                  ? const Color(0xFF31A879)
                  : const Color(0xFFE89A38),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            published ? 'Đã xuất bản' : 'Bản nháp',
            style: TextStyle(
              color: published
                  ? const Color(0xFF21845F)
                  : const Color(0xFFB7791F),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: _muted, size: 17),
      );

  Widget _analytics(bool narrow) {
    final statistics = _statistics;
    final dailyAttempts = statistics?.attemptsLastSevenDays ?? const <int>[];
    final maxAttempts = dailyAttempts.isEmpty
        ? 1
        : dailyAttempts.reduce((left, right) => left > right ? left : right);
    final missedQuestions = statistics?.mostMissedQuestions ?? const [];
    final maxMisses = missedQuestions.isEmpty
        ? 1
        : missedQuestions
              .map(
                (question) =>
                    (question['incorrectCount'] as num?)?.toInt() ?? 0,
              )
              .reduce((left, right) => left > right ? left : right);
    final performance = Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lượt làm bài',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Thống kê trong 7 ngày gần nhất',
            style: TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 155,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: dailyAttempts.isEmpty
                                  ? 0
                                  : (dailyAttempts[i] / maxAttempts).clamp(
                                      0.04,
                                      1.0,
                                    ),
                              child: Container(
                                width: 17,
                                decoration: BoxDecoration(
                                  color: i == 6
                                      ? _violet
                                      : const Color(0xFFDCD7FF),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            Text(
                              dailyAttempts.isEmpty
                                  ? '0'
                                  : '${dailyAttempts[i]}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i],
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final missed = Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Câu hỏi cần lưu ý',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Top 10 câu hỏi sinh viên trả lời sai nhiều nhất',
            style: TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 17),
          if (missedQuestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Chưa có dữ liệu bài làm để thống kê câu sai.',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          for (final question in missedQuestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Q.${question['questionOrder']}',
                      style: const TextStyle(
                        color: Color(0xFFC45B5B),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question['examTitle']?.toString() ?? 'Đề thi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value:
                                ((question['incorrectCount'] as num?)
                                        ?.toInt() ??
                                    0) /
                                maxMisses,
                            minHeight: 4,
                            backgroundColor: const Color(0xFFF0F1F5),
                            color: const Color(0xFFE77878),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${question['incorrectCount'] ?? 0}',
                    style: const TextStyle(
                      color: Color(0xFFE77878),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 1),
          TextButton(
            onPressed: () => setState(() => _selectedNavigation = 2),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: _violet,
            ),
            child: const Text(
              'Xem phân tích chi tiết  →',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (narrow) {
      return Column(
        children: [performance, const SizedBox(height: 16), missed],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: performance),
        const SizedBox(width: 16),
        Expanded(flex: 4, child: missed),
      ],
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(color: const Color(0xFFEAECF2)),
  );

  Widget _mobileNavigation() => NavigationBar(
    selectedIndex: _selectedNavigation,
    onDestinationSelected: (index) =>
        setState(() => _selectedNavigation = index),
    height: 65,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.grid_view_rounded),
        label: 'Tổng quan',
      ),
      NavigationDestination(
        icon: Icon(Icons.library_books_outlined),
        label: 'Đề thi',
      ),
      NavigationDestination(
        icon: Icon(Icons.bar_chart_rounded),
        label: 'Thống kê',
      ),
    ],
  );

  Widget _secondaryContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _selectedNavigation == 1 ? 'Ngân hàng đề' : 'Thống kê',
        style: const TextStyle(
          color: _ink,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        _selectedNavigation == 1
            ? 'Quản lý, rà soát và xuất bản đề thi của bạn.'
            : 'Phân tích kết quả và những câu hỏi sinh viên thường làm sai.',
        style: const TextStyle(color: _muted, fontSize: 13),
      ),
      const SizedBox(height: 22),
      if (_selectedNavigation == 1) _examList() else _analytics(true),
    ],
  );
}

class _TableHeading extends StatelessWidget {
  const _TableHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _muted,
      fontSize: 8,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );
}
