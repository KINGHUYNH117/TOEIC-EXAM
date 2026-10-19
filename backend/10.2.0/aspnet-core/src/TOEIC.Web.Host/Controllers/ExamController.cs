using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Abp.AspNetCore.Mvc.Controllers;
using Abp.Authorization;
using Abp.Domain.Repositories;
using Abp.Domain.Uow;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TOEIC.Exams;

namespace TOEIC.Controllers
{
    public class SubmitExamDto
    {
        public Guid ExamId { get; set; }
        public List<UserAnswerDto> Answers { get; set; } = new List<UserAnswerDto>();
    }

    public class UserAnswerDto
    {
        public Guid QuestionId { get; set; }
        public Guid SelectedAnswerId { get; set; }
    }

    [Route("api/[controller]/[action]")]
    public class ExamController : AbpController
    {
        private readonly IExamImportService _examImportService;
        private readonly IRepository<Exam, Guid> _examRepository;
        private readonly IRepository<Question, Guid> _questionRepository;
        private readonly IRepository<Answer, Guid> _answerRepository;
        private readonly IRepository<UserExamResult, Guid> _userExamResultRepository;
        private readonly IRepository<UserAnswer, Guid> _userAnswerRepository;

        public ExamController(
            IExamImportService examImportService,
            IRepository<Exam, Guid> examRepository,
            IRepository<Question, Guid> questionRepository,
            IRepository<Answer, Guid> answerRepository,
            IRepository<UserExamResult, Guid> userExamResultRepository,
            IRepository<UserAnswer, Guid> userAnswerRepository)
        {
            _examImportService = examImportService;
            _examRepository = examRepository;
            _questionRepository = questionRepository;
            _answerRepository = answerRepository;
            _userExamResultRepository = userExamResultRepository;
            _userAnswerRepository = userAnswerRepository;
        }

        [HttpPost]
        [AbpAuthorize]
        public async Task<IActionResult> ImportExam(IFormFile file)
        {
            var examId = await _examImportService.ImportExamFromDocxAsync(file);
            var exam = await _examRepository.GetAsync(examId);
            return Ok(new
            {
                success = true,
                message = "Đề thi hợp lệ và đã được lưu ở trạng thái bản nháp.",
                data = new
                {
                    id = exam.Id,
                    title = exam.Title,
                    duration = exam.Duration,
                    totalQuestions = exam.TotalQuestions,
                    isPublished = exam.IsPublished
                }
            });
        }

        [HttpGet]
        [AbpAllowAnonymous]
        public async Task<IActionResult> GetExams()
        {
            var exams = await _examRepository.GetAll()
                .Where(exam => exam.IsPublished)
                .OrderByDescending(exam => exam.CreationTime)
                .Select(exam => new
                {
                    id = exam.Id,
                    title = exam.Title,
                    duration = exam.Duration,
                    totalQuestions = exam.TotalQuestions,
                    isPublished = exam.IsPublished
                })
                .ToListAsync();

            return Ok(new { success = true, data = exams });
        }

        [HttpGet("{examId}")]
        [AbpAllowAnonymous]
        public async Task<IActionResult> GetExamDetail(Guid examId)
        {
            var exam = await _examRepository.GetAll()
                .Where(item => item.Id == examId && item.IsPublished)
                .Select(item => new
                {
                    id = item.Id,
                    title = item.Title,
                    duration = item.Duration,
                    questions = item.Questions
                        .OrderBy(question => question.QuestionOrder)
                        .Select(question => new
                        {
                            id = question.Id,
                            questionOrder = question.QuestionOrder,
                            partNumber = question.PartNumber,
                            passageContent = question.PassageContent,
                            content = question.QuestionText,
                            answers = question.Answers
                                .OrderBy(answer => answer.OptionKey)
                                .Select(answer => new
                                {
                                    id = answer.Id,
                                    optionText = answer.OptionText,
                                    optionKey = answer.OptionKey
                                })
                                .ToList()
                        })
                        .ToList()
                })
                .FirstOrDefaultAsync();

            if (exam == null)
            {
                return NotFound(new
                {
                    success = false,
                    message = "Không tìm thấy đề thi đã xuất bản."
                });
            }

            return Ok(new { success = true, data = exam });
        }

        [HttpGet]
        [AbpAuthorize]
        public async Task<IActionResult> GetManageExams()
        {
            var exams = await _examRepository.GetAll()
                .OrderByDescending(exam => exam.CreationTime)
                .Select(exam => new
                {
                    id = exam.Id,
                    title = exam.Title,
                    duration = exam.Duration,
                    totalQuestions = exam.TotalQuestions,
                    isPublished = exam.IsPublished,
                    createdAt = exam.CreationTime
                })
                .ToListAsync();

            var examIds = exams.Select(exam => exam.id).ToList();
            var results = await _userExamResultRepository.GetAll()
                .Where(result => examIds.Contains(result.ExamId) && result.SubmitTime != null)
                .GroupBy(result => result.ExamId)
                .Select(group => new
                {
                    examId = group.Key,
                    attempts = group.Count(),
                    averageScore = group.Average(result => result.Score ?? 0)
                })
                .ToListAsync();
            var resultLookup = results.ToDictionary(result => result.examId);

            var data = exams.Select(exam =>
            {
                resultLookup.TryGetValue(exam.id, out var result);
                return new
                {
                    exam.id,
                    exam.title,
                    exam.duration,
                    exam.totalQuestions,
                    exam.isPublished,
                    exam.createdAt,
                    attempts = result == null ? 0 : result.attempts,
                    averageScore = result == null ? 0 : result.averageScore
                };
            }).ToList();

            return Ok(new { success = true, data });
        }

        [HttpGet("{examId}")]
        [AbpAuthorize]
        public async Task<IActionResult> GetManageExamDetail(Guid examId)
        {
            var exam = await _examRepository.GetAll()
                .Where(item => item.Id == examId)
                .Select(item => new
                {
                    id = item.Id,
                    title = item.Title,
                    duration = item.Duration,
                    isPublished = item.IsPublished,
                    questions = item.Questions
                        .OrderBy(question => question.QuestionOrder)
                        .Select(question => new
                        {
                            id = question.Id,
                            questionOrder = question.QuestionOrder,
                            partNumber = question.PartNumber,
                            passageContent = question.PassageContent,
                            content = question.QuestionText,
                            explanation = question.Explanation,
                            answers = question.Answers
                                .OrderBy(answer => answer.OptionKey)
                                .Select(answer => new
                                {
                                    id = answer.Id,
                                    optionText = answer.OptionText,
                                    optionKey = answer.OptionKey,
                                    isCorrect = answer.IsCorrect
                                })
                                .ToList()
                        })
                        .ToList()
                })
                .FirstOrDefaultAsync();

            if (exam == null)
            {
                return NotFound(new { success = false, message = "Không tìm thấy đề thi." });
            }
            return Ok(new { success = true, data = exam });
        }

        [HttpPost("{examId}")]
        [AbpAuthorize]
        [UnitOfWork]
        public async Task<IActionResult> PublishExam(Guid examId)
        {
            var exam = await _examRepository.GetAsync(examId);
            var questions = await _questionRepository.GetAll()
                .Where(question => question.ExamId == examId)
                .ToListAsync();
            if (questions.Count == 0 || questions.Count != exam.TotalQuestions)
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Không thể xuất bản đề thi chưa có đủ câu hỏi hợp lệ."
                });
            }

            var questionIds = questions.Select(question => question.Id).ToList();
            var answerCounts = await _answerRepository.GetAll()
                .Where(answer => questionIds.Contains(answer.QuestionId))
                .GroupBy(answer => answer.QuestionId)
                .Select(group => new
                {
                    questionId = group.Key,
                    count = group.Count(),
                    correctCount = group.Count(answer => answer.IsCorrect)
                })
                .ToListAsync();
            if (answerCounts.Count != questions.Count ||
                answerCounts.Any(item => item.count != 4 || item.correctCount != 1))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Mỗi câu hỏi phải có đúng 4 lựa chọn và một đáp án đúng."
                });
            }

            exam.IsPublished = true;
            await _examRepository.UpdateAsync(exam);
            await CurrentUnitOfWork.SaveChangesAsync();
            return Ok(new
            {
                success = true,
                message = "Đề thi đã được xuất bản."
            });
        }

        [HttpGet]
        [AbpAuthorize]
        public async Task<IActionResult> GetStatistics()
        {
            var exams = await _examRepository.GetAll().ToListAsync();
            var examIds = exams.Select(exam => exam.Id).ToList();
            var results = await _userExamResultRepository.GetAll()
                .Where(result => examIds.Contains(result.ExamId) && result.SubmitTime != null)
                .Select(result => new
                {
                    result.ExamId,
                    result.SubmitTime,
                    result.Score
                })
                .ToListAsync();

            var today = DateTime.Today;
            var attemptsLastSevenDays = Enumerable.Range(0, 7)
                .Select(offset => results.Count(result =>
                    result.SubmitTime.HasValue &&
                    result.SubmitTime.Value.Date == today.AddDays(offset - 6)))
                .ToList();
            var averageScore = results.Count == 0
                ? 0
                : results.Average(result => result.Score ?? 0);

            var questionDetails = await _questionRepository.GetAll()
                .Where(question => examIds.Contains(question.ExamId))
                .Select(question => new
                {
                    question.Id,
                    question.ExamId,
                    question.QuestionOrder,
                    question.QuestionText
                })
                .ToListAsync();
            var incorrectCounts = await _userAnswerRepository.GetAll()
                .Where(answer => !answer.IsCorrect)
                .GroupBy(answer => answer.QuestionId)
                .Select(group => new
                {
                    questionId = group.Key,
                    count = group.Count()
                })
                .ToListAsync();
            var examTitles = exams.ToDictionary(exam => exam.Id, exam => exam.Title);
            var incorrectLookup = incorrectCounts.ToDictionary(item => item.questionId);
            var mostMissedQuestions = questionDetails
                .Select(question =>
                {
                    incorrectLookup.TryGetValue(question.Id, out var incorrect);
                    return new
                    {
                        questionId = question.Id,
                        examTitle = examTitles[question.ExamId],
                        questionOrder = question.QuestionOrder,
                        questionText = question.QuestionText,
                        incorrectCount = incorrect == null ? 0 : incorrect.count
                    };
                })
                .Where(question => question.incorrectCount > 0)
                .OrderByDescending(question => question.incorrectCount)
                .Take(10)
                .ToList();

            return Ok(new
            {
                success = true,
                data = new
                {
                    totalExams = exams.Count,
                    totalAttempts = results.Count,
                    averageScore,
                    attemptsLastSevenDays,
                    mostMissedQuestions
                }
            });
        }

        [HttpPost]
        [AbpAuthorize]
        [UnitOfWork]
        public async Task<IActionResult> SubmitExam([FromBody] SubmitExamDto input)
        {
            if (input == null || input.ExamId == Guid.Empty || input.Answers == null ||
                input.Answers.Any(answer =>
                    answer == null ||
                    answer.QuestionId == Guid.Empty ||
                    answer.SelectedAnswerId == Guid.Empty))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Dữ liệu nộp bài không hợp lệ."
                });
            }
            if (!AbpSession.UserId.HasValue)
            {
                return Unauthorized(new
                {
                    success = false,
                    message = "Bạn cần đăng nhập để nộp bài thi."
                });
            }
            if (input.Answers.Select(answer => answer.QuestionId).Distinct().Count() !=
                input.Answers.Count)
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Danh sách bài làm có câu hỏi bị lặp."
                });
            }

            var exam = await _examRepository.GetAll()
                .Where(item => item.Id == input.ExamId && item.IsPublished)
                .FirstOrDefaultAsync();
            if (exam == null)
            {
                return NotFound(new
                {
                    success = false,
                    message = "Không tìm thấy đề thi đã xuất bản."
                });
            }

            var examQuestions = await _questionRepository.GetAll()
                .Where(question => question.ExamId == exam.Id)
                .OrderBy(question => question.QuestionOrder)
                .ToListAsync();
            if (examQuestions.Count == 0)
            {
                return BadRequest(new { success = false, message = "Đề thi chưa có câu hỏi." });
            }

            var questionById = examQuestions.ToDictionary(question => question.Id);
            if (input.Answers.Any(answer => !questionById.ContainsKey(answer.QuestionId)))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Có câu hỏi không thuộc đề thi đã chọn."
                });
            }

            var selectedAnswerIds = input.Answers.Select(answer => answer.SelectedAnswerId).ToList();
            var selectedAnswers = await _answerRepository.GetAll()
                .Where(answer => selectedAnswerIds.Contains(answer.Id))
                .ToDictionaryAsync(answer => answer.Id);
            if (input.Answers.Any(answer =>
                    !selectedAnswers.TryGetValue(answer.SelectedAnswerId, out var selected) ||
                    selected.QuestionId != answer.QuestionId))
            {
                return BadRequest(new
                {
                    success = false,
                    message = "Có đáp án không thuộc câu hỏi tương ứng."
                });
            }

            var resultId = Guid.NewGuid();
            var correctCount = 0;
            var incorrectCount = 0;
            var userAnswers = new List<UserAnswer>();
            var selectedKeyByQuestion = new Dictionary<Guid, string>();
            foreach (var answer in input.Answers)
            {
                var selected = selectedAnswers[answer.SelectedAnswerId];
                if (selected.IsCorrect)
                {
                    correctCount++;
                }
                else
                {
                    incorrectCount++;
                }

                selectedKeyByQuestion[answer.QuestionId] = selected.OptionKey;
                userAnswers.Add(new UserAnswer
                {
                    Id = Guid.NewGuid(),
                    UserExamResultId = resultId,
                    QuestionId = answer.QuestionId,
                    SelectedOptionKey = selected.OptionKey,
                    IsCorrect = selected.IsCorrect
                });
            }

            var skippedCount = examQuestions.Count - input.Answers.Count;
            var score = (int)((double)correctCount / examQuestions.Count * 495);
            var result = new UserExamResult
            {
                Id = resultId,
                UserId = AbpSession.UserId.Value,
                ExamId = exam.Id,
                Score = score,
                TotalCorrect = correctCount,
                TotalIncorrect = incorrectCount,
                TotalSkipped = skippedCount,
                SubmitTime = DateTime.Now
            };
            await _userExamResultRepository.InsertAsync(result);
            foreach (var userAnswer in userAnswers)
            {
                await _userAnswerRepository.InsertAsync(userAnswer);
            }
            await CurrentUnitOfWork.SaveChangesAsync();

            var answerKeys = await _answerRepository.GetAll()
                .Where(answer => examQuestions.Select(question => question.Id)
                    .Contains(answer.QuestionId) && answer.IsCorrect)
                .Select(answer => new
                {
                    answer.QuestionId,
                    answer.OptionKey
                })
                .ToDictionaryAsync(answer => answer.QuestionId, answer => answer.OptionKey);
            var review = examQuestions.Select(question =>
            {
                selectedKeyByQuestion.TryGetValue(question.Id, out var selectedKey);
                var correctKey = answerKeys[question.Id];
                return new
                {
                    questionId = question.Id,
                    selectedOptionKey = selectedKey,
                    correctOptionKey = correctKey,
                    isCorrect = selectedKey != null && selectedKey == correctKey
                };
            }).ToList();

            return Ok(new
            {
                success = true,
                message = "Nộp bài và chấm điểm thành công.",
                data = new
                {
                    resultId,
                    score,
                    correctCount,
                    incorrectCount,
                    skippedCount,
                    totalQuestions = examQuestions.Count,
                    answers = review
                }
            });
        }
    }
}
