import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
class ExamSummary {
  const ExamSummary({
    required this.id,
    required this.title,
    required this.duration,
    required this.totalQuestions,
    required this.isPublished,
    required this.attempts,
    required this.averageScore,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int duration;
  final int totalQuestions;
  final bool isPublished;
  final int attempts;
  final double averageScore;
  final DateTime? createdAt;

  factory ExamSummary.fromJson(Map<String, dynamic> json) => ExamSummary(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Đề thi không tên',
    duration: _toInt(json['duration']),
    totalQuestions: _toInt(json['totalQuestions']),
    isPublished: json['isPublished'] == true,
    attempts: _toInt(json['attempts']),
    averageScore: _toDouble(json['averageScore']),
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );
}

@immutable
class ExamOption {
  const ExamOption({required this.id, required this.key, required this.text});

  final String id;
  final String key;
  final String text;

  factory ExamOption.fromJson(Map<String, dynamic> json) => ExamOption(
    id: json['id']?.toString() ?? '',
    key: json['optionKey']?.toString() ?? '',
    text: json['optionText']?.toString() ?? '',
  );
}

@immutable
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.order,
    required this.partNumber,
    required this.passage,
    required this.prompt,
    required this.options,
    this.correctOptionKey,
  });

  final String id;
  final int order;
  final int partNumber;
  final String passage;
  final String prompt;
  final List<ExamOption> options;
  final String? correctOptionKey;

  factory ExamQuestion.fromJson(Map<String, dynamic> json) => ExamQuestion(
    id: json['id']?.toString() ?? '',
    order: _toInt(json['questionOrder']),
    partNumber: _toInt(json['partNumber']),
    passage: json['passageContent']?.toString() ?? '',
    prompt: json['content']?.toString() ?? '',
    options: (json['answers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExamOption.fromJson)
        .toList(),
    correctOptionKey:
        json['correctOptionKey']?.toString() ??
        (json['answers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where((answer) => answer['isCorrect'] == true)
            .map((answer) => answer['optionKey']?.toString() ?? '')
            .firstOrNull,
  );
}

@immutable
class ExamDetail {
  const ExamDetail({
    required this.id,
    required this.title,
    required this.duration,
    required this.questions,
  });

  final String id;
  final String title;
  final int duration;
  final List<ExamQuestion> questions;

  factory ExamDetail.fromJson(Map<String, dynamic> json) => ExamDetail(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Đề thi',
    duration: _toInt(json['duration']),
    questions: (json['questions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExamQuestion.fromJson)
        .toList(),
  );
}

@immutable
class ExamAnswerResult {
  const ExamAnswerResult({
    required this.questionId,
    required this.selectedOptionKey,
    required this.correctOptionKey,
    required this.isCorrect,
  });

  final String questionId;
  final String? selectedOptionKey;
  final String correctOptionKey;
  final bool isCorrect;

  factory ExamAnswerResult.fromJson(Map<String, dynamic> json) =>
      ExamAnswerResult(
        questionId: json['questionId']?.toString() ?? '',
        selectedOptionKey: json['selectedOptionKey']?.toString(),
        correctOptionKey: json['correctOptionKey']?.toString() ?? '',
        isCorrect: json['isCorrect'] == true,
      );
}

@immutable
class ExamSubmissionResult {
  const ExamSubmissionResult({
    required this.score,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.totalQuestions,
    required this.answers,
  });

  final double score;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final int totalQuestions;
  final List<ExamAnswerResult> answers;

  factory ExamSubmissionResult.fromJson(Map<String, dynamic> json) =>
      ExamSubmissionResult(
        score: _toDouble(json['score']),
        correctCount: _toInt(json['correctCount']),
        incorrectCount: _toInt(json['incorrectCount']),
        skippedCount: _toInt(json['skippedCount']),
        totalQuestions: _toInt(json['totalQuestions']),
        answers: (json['answers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ExamAnswerResult.fromJson)
            .toList(),
      );
}

@immutable
class ExamStatistics {
  const ExamStatistics({
    required this.totalExams,
    required this.totalAttempts,
    required this.averageScore,
    required this.attemptsLastSevenDays,
    required this.mostMissedQuestions,
  });

  final int totalExams;
  final int totalAttempts;
  final double averageScore;
  final List<int> attemptsLastSevenDays;
  final List<Map<String, dynamic>> mostMissedQuestions;

  factory ExamStatistics.fromJson(Map<String, dynamic> json) => ExamStatistics(
    totalExams: _toInt(json['totalExams']),
    totalAttempts: _toInt(json['totalAttempts']),
    averageScore: _toDouble(json['averageScore']),
    attemptsLastSevenDays:
        (json['attemptsLastSevenDays'] as List<dynamic>? ?? const [])
            .map(_toInt)
            .toList(),
    mostMissedQuestions:
        (json['mostMissedQuestions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
  );
}

class ExamApiException implements Exception {
  const ExamApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ExamApiClient {
  ExamApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          (baseUrl ??
                  const String.fromEnvironment(
                    'EXAM_API_BASE_URL',
                    defaultValue: 'https://localhost:44311',
                  ))
              .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;
  String? _accessToken;

  bool get isAuthenticated => _accessToken != null;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Future<Map<String, dynamic>> authenticate(
    String username,
    String password,
  ) async {
    final response = await _send(
      _uri('/api/TokenAuth/Authenticate'),
      () => _client.post(
        _uri('/api/TokenAuth/Authenticate'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userNameOrEmailAddress': username,
          'password': password,
          'rememberClient': false,
        }),
      ),
    );
    final data = _unwrap(_decode(response));
    final token = data['accessToken']?.toString();
    if (token == null || token.isEmpty) {
      throw const ExamApiException('API đăng nhập không trả về access token.');
    }
    _accessToken = token;
    return data;
  }

  void signOut() => _accessToken = null;

  Future<List<ExamSummary>> getTeacherExams() async {
    final response = await _send(
      _uri('/api/Exam/GetManageExams'),
      () => _client.get(_uri('/api/Exam/GetManageExams'), headers: _headers),
    );
    final data = _unwrap(_decode(response));
    return (data['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExamSummary.fromJson)
        .toList();
  }

  Future<ExamStatistics> getStatistics() async {
    final response = await _send(
      _uri('/api/Exam/GetStatistics'),
      () => _client.get(_uri('/api/Exam/GetStatistics'), headers: _headers),
    );
    return ExamStatistics.fromJson(
      _unwrap(_decode(response))['data'] as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> importDocx(String name, List<int> bytes) async {
    final request = http.MultipartRequest('POST', _uri('/api/Exam/ImportExam'))
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final response = await _send(_uri('/api/Exam/ImportExam'), () async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
    return _unwrap(_decode(response));
  }

  Future<void> publishExam(String examId) async {
    await _send(
      _uri('/api/Exam/PublishExam/$examId'),
      () => _client.post(
        _uri('/api/Exam/PublishExam/$examId'),
        headers: _headers,
      ),
    );
  }

  Future<List<ExamSummary>> getPublishedExams() async {
    final response = await _send(
      _uri('/api/Exam/GetExams'),
      () => _client.get(_uri('/api/Exam/GetExams'), headers: _headers),
    );
    final data = _unwrap(_decode(response));
    return (data['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExamSummary.fromJson)
        .toList();
  }

  Future<ExamDetail> getExamDetail(String examId) async {
    final response = await _send(
      _uri('/api/Exam/GetExamDetail/$examId'),
      () => _client.get(
        _uri('/api/Exam/GetExamDetail/$examId'),
        headers: _headers,
      ),
    );
    return ExamDetail.fromJson(
      _unwrap(_decode(response))['data'] as Map<String, dynamic>,
    );
  }

  Future<ExamDetail> getManageExamDetail(String examId) async {
    final response = await _send(
      _uri('/api/Exam/GetManageExamDetail/$examId'),
      () => _client.get(
        _uri('/api/Exam/GetManageExamDetail/$examId'),
        headers: _headers,
      ),
    );
    return ExamDetail.fromJson(
      _unwrap(_decode(response))['data'] as Map<String, dynamic>,
    );
  }

  Future<ExamSubmissionResult> submitExam(
    String examId,
    Map<String, String?> selectedAnswers,
  ) async {
    final payload = {
      'examId': examId,
      'answers': selectedAnswers.entries
          .where((answer) => answer.value != null)
          .map(
            (answer) => {
              'questionId': answer.key,
              'selectedAnswerId': answer.value,
            },
          )
          .toList(),
    };
    final response = await _send(
      _uri('/api/Exam/SubmitExam'),
      () => _client.post(
        _uri('/api/Exam/SubmitExam'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
    return ExamSubmissionResult.fromJson(
      _unwrap(_decode(response))['data'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const ExamApiException('API trả về dữ liệu không hợp lệ.');
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      throw const ExamApiException('API trả về dữ liệu không hợp lệ.');
    }
    throw ExamApiException(
      'Yêu cầu API thất bại (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> response) {
    final root = response['result'];
    final data = root is Map<String, dynamic> ? root : response;
    if (data['success'] == false) {
      throw ExamApiException(
        data['message']?.toString() ?? 'API từ chối yêu cầu.',
      );
    }
    if (response['success'] == false) {
      throw ExamApiException(
        response['message']?.toString() ?? 'API từ chối yêu cầu.',
      );
    }
    return data;
  }

  Future<http.Response> _send(
    Uri uri,
    Future<http.Response> Function() action,
  ) async {
    try {
      final response = await action();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _extractError(response.body);
        throw ExamApiException(message, statusCode: response.statusCode);
      }
      return response;
    } on ExamApiException {
      rethrow;
    } on http.ClientException catch (error) {
      throw ExamApiException(
        'Không thể kết nối đến API ${uri.origin}. '
        'Hãy khởi động backend và kiểm tra cấu hình HTTPS/CORS. ($error)',
      );
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final root = decoded['result'];
        if (root is Map<String, dynamic>) {
          return root['message']?.toString() ??
              decoded['message']?.toString() ??
              'Yêu cầu API thất bại.';
        }
        return decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            'Yêu cầu API thất bại.';
      }
    } on FormatException {
      return 'Yêu cầu API thất bại. HTTP response không hợp lệ.';
    }
    return 'Yêu cầu API thất bại.';
  }

  void close() => _client.close();
}

int _toInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

double _toDouble(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
