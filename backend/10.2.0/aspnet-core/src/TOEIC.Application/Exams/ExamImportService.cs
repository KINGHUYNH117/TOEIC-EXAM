using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Abp.Application.Services;
using Abp.Domain.Repositories;
using Abp.Domain.Uow;
using Abp.UI;
using DocumentFormat.OpenXml.Packaging;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace TOEIC.Exams
{
    public interface IExamImportService : IApplicationService
    {
        [HttpPost]
        Task<Guid> ImportExamFromDocxAsync(IFormFile file);
    }

    public class ExamImportService : TOEICAppServiceBase, IExamImportService
    {
        private readonly IRepository<Exam, Guid> _examRepository;
        private readonly IRepository<Question, Guid> _questionRepository;
        private readonly IRepository<Answer, Guid> _answerRepository;

        public ExamImportService(
            IRepository<Exam, Guid> examRepository,
            IRepository<Question, Guid> questionRepository,
            IRepository<Answer, Guid> answerRepository)
        {
            _examRepository = examRepository;
            _questionRepository = questionRepository;
            _answerRepository = answerRepository;
        }

        [UnitOfWork]
        public async Task<Guid> ImportExamFromDocxAsync(IFormFile file)
        {
            if (file == null || file.Length == 0)
            {
                throw new UserFriendlyException("Vui lòng chọn một file Word (.docx) hợp lệ.");
            }

            if (!string.Equals(
                System.IO.Path.GetExtension(file.FileName),
                ".docx",
                StringComparison.OrdinalIgnoreCase))
            {
                throw new UserFriendlyException("Chỉ chấp nhận file Word có định dạng .docx.");
            }

            try
            {
                List<string> paragraphs;
                using (var stream = file.OpenReadStream())
                using (var document = WordprocessingDocument.Open(stream, false))
                {
                    if (document.MainDocumentPart == null ||
                        document.MainDocumentPart.Document == null ||
                        document.MainDocumentPart.Document.Body == null)
                    {
                        throw new UserFriendlyException("File Word không có nội dung tài liệu hợp lệ.");
                    }

                    paragraphs = document.MainDocumentPart.Document.Body
                        .Descendants<DocumentFormat.OpenXml.Wordprocessing.Paragraph>()
                        .Select(paragraph => paragraph.InnerText.Trim())
                        .Where(text => !string.IsNullOrWhiteSpace(text))
                        .ToList();
                }

                var exam = ParseAndValidate(paragraphs);

                await _examRepository.InsertAsync(exam);
                foreach (var question in exam.Questions)
                {
                    await _questionRepository.InsertAsync(question);
                    foreach (var answer in question.Answers)
                    {
                        await _answerRepository.InsertAsync(answer);
                    }
                }

                await CurrentUnitOfWork.SaveChangesAsync();
                return exam.Id;
            }
            catch (UserFriendlyException)
            {
                throw;
            }
            catch (Exception exception)
            {
                Logger.Error("Failed to import exam from DOCX.", exception);
                throw new UserFriendlyException(
                    "Không thể đọc file Word. Hãy kiểm tra file .docx và sửa các lỗi định dạng trước khi import.");
            }
        }

        private static Exam ParseAndValidate(IReadOnlyList<string> paragraphs)
        {
            if (!paragraphs.Any(text =>
                    text.Equals("[EXAM_CONFIG]", StringComparison.OrdinalIgnoreCase)))
            {
                throw new UserFriendlyException("Không tìm thấy thẻ [EXAM_CONFIG].");
            }

            var title = FindTagValue(paragraphs, "TITLE");
            var durationText = FindTagValue(paragraphs, "DURATION");
            var countText = FindTagValue(paragraphs, "TOTAL_QUESTIONS");

            if (string.IsNullOrWhiteSpace(title))
            {
                throw new UserFriendlyException("Thiếu hoặc sai thẻ [TITLE]...[/TITLE].");
            }

            if (title.Length > 200)
            {
                throw new UserFriendlyException("Tên đề thi không được vượt quá 200 ký tự.");
            }

            if (!int.TryParse(durationText, out var duration) || duration <= 0)
            {
                throw new UserFriendlyException(
                    "Thẻ [DURATION] phải chứa số phút lớn hơn 0.");
            }

            if (!int.TryParse(countText, out var expectedQuestionCount) ||
                expectedQuestionCount <= 0)
            {
                throw new UserFriendlyException(
                    "Thẻ [TOTAL_QUESTIONS] phải chứa số câu hỏi lớn hơn 0.");
            }

            var exam = new Exam
            {
                Id = Guid.NewGuid(),
                Title = title.Trim(),
                Duration = duration,
                TotalQuestions = expectedQuestionCount,
                IsPublished = false,
                Questions = new List<Question>()
            };

            Question currentQuestion = null;
            var currentAnswers = new List<Answer>();
            var currentPassage = new StringBuilder();
            var explanation = new StringBuilder();
            var groupIdentifier = (string)null;
            var groupPartNumber = 0;
            var isReadingPassage = false;
            var isReadingExplanation = false;
            var isReadingAnswer = false;
            var correctOptionKey = (string)null;
            var lastQuestionOrder = (int?)null;

            foreach (var text in paragraphs)
            {
                if (text.Equals("[EXAM_CONFIG]", StringComparison.OrdinalIgnoreCase) ||
                    text.Equals("[/EXAM_CONFIG]", StringComparison.OrdinalIgnoreCase) ||
                    IsConfigTag(text))
                {
                    continue;
                }

                if (TryReadOpeningTag(text, "QUESTION_GROUP", out var groupAttributes))
                {
                    if (currentQuestion != null)
                    {
                        throw new UserFriendlyException(
                            "Thẻ [QUESTION_GROUP] xuất hiện trước khi câu hỏi hiện tại kết thúc.");
                    }

                    groupIdentifier = ReadAttribute(groupAttributes, "id");
                    int.TryParse(ReadAttribute(groupAttributes, "part"), out groupPartNumber);
                    continue;
                }

                if (text.Equals("[/QUESTION_GROUP]", StringComparison.OrdinalIgnoreCase))
                {
                    if (currentQuestion != null)
                    {
                        throw new UserFriendlyException(
                            "Thẻ [/QUESTION_GROUP] xuất hiện khi câu hỏi chưa kết thúc.");
                    }
                    groupIdentifier = null;
                    groupPartNumber = 0;
                    currentPassage.Clear();
                    continue;
                }

                if (isReadingPassage)
                {
                    if (TryReadClosingTag(text, "PASSAGE"))
                    {
                        isReadingPassage = false;
                    }
                    else if (text.StartsWith("[", StringComparison.Ordinal))
                    {
                        throw new UserFriendlyException(
                            "Thiếu thẻ [/PASSAGE] hoặc thẻ trong nội dung đoạn văn không hợp lệ.");
                    }
                    else
                    {
                        currentPassage.AppendLine(text);
                    }
                    continue;
                }

                if (TryReadTagContent(text, "PASSAGE", out var passageText, out var passageComplete))
                {
                    if (currentQuestion != null)
                    {
                        throw new UserFriendlyException(
                            "Thẻ [PASSAGE] phải nằm trước câu hỏi trong nhóm câu hỏi.");
                    }
                    currentPassage.Clear();
                    if (!string.IsNullOrWhiteSpace(passageText))
                    {
                        currentPassage.AppendLine(passageText);
                    }
                    isReadingPassage = !passageComplete;
                    continue;
                }

                if (TryReadQuestionHeader(text, out var questionAttributes))
                {
                    if (currentQuestion != null)
                    {
                        throw new UserFriendlyException(
                            "Thiếu thẻ [/QUESTION] trước câu hỏi tiếp theo.");
                    }

                    if (!int.TryParse(ReadAttribute(questionAttributes, "id"), out var questionOrder))
                    {
                        throw new UserFriendlyException(
                            "Mỗi thẻ [QUESTION] phải có id là số thứ tự câu hỏi.");
                    }

                    if (lastQuestionOrder.HasValue &&
                        questionOrder != lastQuestionOrder.Value + 1)
                    {
                        throw new UserFriendlyException(
                            "Số thứ tự câu hỏi không liên tục. Câu tiếp theo phải là " +
                            (lastQuestionOrder.Value + 1) + ".");
                    }

                    lastQuestionOrder = questionOrder;
                    int.TryParse(ReadAttribute(questionAttributes, "part"), out var questionPart);
                    if (questionPart == 0)
                    {
                        questionPart = groupPartNumber == 0 ? 5 : groupPartNumber;
                    }

                    currentQuestion = new Question
                    {
                        Id = Guid.NewGuid(),
                        ExamId = exam.Id,
                        QuestionOrder = questionOrder,
                        PartNumber = questionPart,
                        GroupIdentifier = groupIdentifier,
                        PassageContent = currentPassage.ToString().Trim(),
                        QuestionText = string.Empty,
                        Answers = new List<Answer>()
                    };
                    currentAnswers = new List<Answer>();
                    correctOptionKey = null;
                    explanation.Clear();
                    isReadingExplanation = false;
                    isReadingAnswer = false;
                    continue;
                }

                if (currentQuestion == null)
                {
                    if (text.StartsWith("[QUESTION", StringComparison.OrdinalIgnoreCase))
                    {
                        throw new UserFriendlyException(
                            "Thẻ câu hỏi không đúng định dạng. Dùng [QUESTION id=\"1\" part=\"5\"].");
                    }
                    continue;
                }

                if (isReadingExplanation)
                {
                    if (TryReadClosingTag(text, "EXPLANATION"))
                    {
                        currentQuestion.Explanation = explanation.ToString().Trim();
                        isReadingExplanation = false;
                    }
                    else if (text.StartsWith("[", StringComparison.Ordinal))
                    {
                        throw new UserFriendlyException(
                            "Thiếu thẻ [/EXPLANATION] hoặc thẻ giải thích không hợp lệ.");
                    }
                    else
                    {
                        explanation.AppendLine(text);
                    }
                    continue;
                }

                if (TryReadTagContent(
                    text,
                    "EXPLANATION",
                    out var explanationText,
                    out var explanationComplete))
                {
                    explanation.Clear();
                    if (!string.IsNullOrWhiteSpace(explanationText))
                    {
                        explanation.AppendLine(explanationText);
                    }
                    isReadingExplanation = !explanationComplete;
                    if (explanationComplete)
                    {
                        currentQuestion.Explanation = explanation.ToString().Trim();
                    }
                    continue;
                }

                if (isReadingAnswer)
                {
                    if (TryReadClosingTag(text, "ANSWER"))
                    {
                        isReadingAnswer = false;
                    }
                    else if (text.StartsWith("[", StringComparison.Ordinal))
                    {
                        throw new UserFriendlyException(
                            "Thiếu thẻ [/ANSWER] hoặc thẻ đáp án không hợp lệ.");
                    }
                    else if (correctOptionKey == null)
                    {
                        correctOptionKey = text.Trim();
                    }
                    else
                    {
                        throw new UserFriendlyException(
                            "Thẻ [ANSWER] chỉ được chứa một đáp án đúng.");
                    }
                    continue;
                }

                if (TryReadTagContent(text, "ANSWER", out var answerText, out var answerComplete))
                {
                    if (correctOptionKey != null)
                    {
                        throw new UserFriendlyException("Mỗi câu hỏi chỉ được có một thẻ [ANSWER].");
                    }
                    correctOptionKey = answerText.Trim();
                    isReadingAnswer = !answerComplete;
                    continue;
                }

                if (TryReadTagContent(text, "OPTION", out var optionText, out var optionComplete))
                {
                    var optionMatch = Regex.Match(
                        optionText.Trim(),
                        @"^\(?([A-D])\)?[.)]?\s*(.+)$",
                        RegexOptions.IgnoreCase);
                    if (!optionComplete || !optionMatch.Success)
                    {
                        throw new UserFriendlyException(
                            "Mỗi đáp án phải theo định dạng [OPTION]A. Nội dung[/OPTION].");
                    }

                    var optionKey = optionMatch.Groups[1].Value.ToUpperInvariant();
                    if (currentAnswers.Any(answer => answer.OptionKey == optionKey))
                    {
                        throw new UserFriendlyException(
                            "Câu " + currentQuestion.QuestionOrder +
                            " có đáp án trùng lựa chọn " + optionKey + ".");
                    }

                    currentAnswers.Add(new Answer
                    {
                        Id = Guid.NewGuid(),
                        QuestionId = currentQuestion.Id,
                        OptionKey = optionKey,
                        OptionText = optionMatch.Groups[2].Value.Trim()
                    });
                    continue;
                }

                if (text.Equals("[/QUESTION]", StringComparison.OrdinalIgnoreCase))
                {
                    ValidateQuestion(currentQuestion, currentAnswers, correctOptionKey);
                    var correctAnswer = currentAnswers.Single(
                        answer => answer.OptionKey == NormalizeAnswerKey(correctOptionKey));
                    correctAnswer.IsCorrect = true;
                    currentQuestion.Answers = currentAnswers;
                    exam.Questions.Add(currentQuestion);
                    currentQuestion = null;
                    currentAnswers = new List<Answer>();
                    currentPassage.Clear();
                    isReadingAnswer = false;
                    isReadingExplanation = false;
                    continue;
                }

                if (text.StartsWith("[", StringComparison.Ordinal))
                {
                    throw new UserFriendlyException(
                        "Thẻ không được hỗ trợ trong câu hỏi " +
                        currentQuestion.QuestionOrder + ": " + text);
                }

                currentQuestion.QuestionText =
                    string.IsNullOrWhiteSpace(currentQuestion.QuestionText)
                        ? text
                        : currentQuestion.QuestionText + Environment.NewLine + text;
            }

            if (isReadingPassage)
            {
                throw new UserFriendlyException("Thiếu thẻ đóng [/PASSAGE].");
            }
            if (isReadingAnswer)
            {
                throw new UserFriendlyException("Thiếu thẻ đóng [/ANSWER].");
            }
            if (isReadingExplanation)
            {
                throw new UserFriendlyException("Thiếu thẻ đóng [/EXPLANATION].");
            }
            if (currentQuestion != null)
            {
                throw new UserFriendlyException(
                    "Thiếu thẻ [/QUESTION] cho câu " + currentQuestion.QuestionOrder + ".");
            }
            if (exam.Questions.Count != expectedQuestionCount)
            {
                throw new UserFriendlyException(
                    "Số câu khai báo là " + expectedQuestionCount +
                    " nhưng tìm thấy " + exam.Questions.Count + " câu hoàn chỉnh.");
            }

            return exam;
        }

        private static void ValidateQuestion(
            Question question,
            IList<Answer> answers,
            string correctOptionKey)
        {
            if (string.IsNullOrWhiteSpace(question.QuestionText))
            {
                throw new UserFriendlyException(
                    "Câu " + question.QuestionOrder + " chưa có nội dung câu hỏi.");
            }
            if (answers.Count != 4)
            {
                throw new UserFriendlyException(
                    "Câu " + question.QuestionOrder +
                    " phải có đúng 4 đáp án A, B, C, D.");
            }
            if (!answers.Select(answer => answer.OptionKey)
                    .OrderBy(key => key)
                    .SequenceEqual(new[] { "A", "B", "C", "D" }))
            {
                throw new UserFriendlyException(
                    "Câu " + question.QuestionOrder +
                    " phải có đủ đáp án A, B, C, D.");
            }
            if (string.IsNullOrWhiteSpace(correctOptionKey))
            {
                throw new UserFriendlyException(
                    "Câu " + question.QuestionOrder + " chưa có đáp án đúng.");
            }

            var normalizedKey = NormalizeAnswerKey(correctOptionKey);
            if (!answers.Any(answer => answer.OptionKey == normalizedKey))
            {
                throw new UserFriendlyException(
                    "Đáp án đúng của câu " + question.QuestionOrder +
                    " phải là A, B, C hoặc D.");
            }
        }

        private static string NormalizeAnswerKey(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return string.Empty;
            }

            return value.Trim().Trim('(', ')', '.', ':').ToUpperInvariant();
        }

        private static bool IsConfigTag(string text)
        {
            return Regex.IsMatch(
                text,
                @"^\[/?(TITLE|DURATION|TOTAL_QUESTIONS)(\s|\])",
                RegexOptions.IgnoreCase);
        }

        private static string FindTagValue(IEnumerable<string> paragraphs, string tagName)
        {
            foreach (var paragraph in paragraphs)
            {
                if (TryReadTagContent(paragraph, tagName, out var value, out var complete) &&
                    complete)
                {
                    return value.Trim();
                }
            }
            return null;
        }

        private static bool TryReadQuestionHeader(string text, out string attributes)
        {
            var match = Regex.Match(
                text,
                @"^\[QUESTION(?=\s|\])(?<attributes>[^\]]*)\]$",
                RegexOptions.IgnoreCase);
            attributes = match.Success ? match.Groups["attributes"].Value : null;
            return match.Success;
        }

        private static bool TryReadOpeningTag(string text, string tagName, out string attributes)
        {
            var match = Regex.Match(
                text,
                @"^\[" + Regex.Escape(tagName) + @"(?=\s|\])(?<attributes>[^\]]*)\]$",
                RegexOptions.IgnoreCase);
            attributes = match.Success ? match.Groups["attributes"].Value : null;
            return match.Success;
        }

        private static string ReadAttribute(string attributes, string attributeName)
        {
            if (string.IsNullOrEmpty(attributes))
            {
                return null;
            }

            var match = Regex.Match(
                attributes,
                @"\b" + Regex.Escape(attributeName) +
                @"\s*=\s*[""'](?<value>[^""']+)[""']",
                RegexOptions.IgnoreCase);
            return match.Success ? match.Groups["value"].Value : null;
        }

        private static bool TryReadTagContent(
            string text,
            string tagName,
            out string content,
            out bool complete)
        {
            var openingTag = "[" + tagName + "]";
            if (!text.StartsWith(openingTag, StringComparison.OrdinalIgnoreCase))
            {
                content = null;
                complete = false;
                return false;
            }

            var remainingText = text.Substring(openingTag.Length);
            var closingTag = "[/" + tagName + "]";
            var closingIndex = remainingText.IndexOf(
                closingTag,
                StringComparison.OrdinalIgnoreCase);
            if (closingIndex >= 0)
            {
                content = remainingText.Substring(0, closingIndex).Trim();
                complete = true;
                return true;
            }

            content = remainingText.Trim();
            complete = false;
            return true;
        }

        private static bool TryReadClosingTag(string text, string tagName)
        {
            return text.Equals(
                "[/" + tagName + "]",
                StringComparison.OrdinalIgnoreCase);
        }
    }
}
