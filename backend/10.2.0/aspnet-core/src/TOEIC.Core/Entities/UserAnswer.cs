using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Abp.Domain.Entities;

[Table("UserAnswers")]
public class UserAnswer : Entity<Guid>
{
    [Required]
    public Guid UserExamResultId { get; set; }

    [Required]
    public Guid QuestionId { get; set; }

    [MaxLength(5)]
    public string SelectedOptionKey { get; set; } // Đáp án sinh viên chọn (A, B, C, D)

    public bool IsCorrect { get; set; } = false;
}