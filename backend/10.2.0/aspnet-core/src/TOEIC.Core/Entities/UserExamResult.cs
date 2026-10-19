using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Abp.Domain.Entities;

[Table("UserExamResults")]
public class UserExamResult : Entity<Guid>
{
    [Required]
    public long UserId { get; set; }

    [Required]
    public Guid ExamId { get; set; }

    [ForeignKey("ExamId")]
    public virtual Exam Exam { get; set; }

    public DateTime StartTime { get; set; } = DateTime.Now;
    public DateTime? SubmitTime { get; set; }
    public int? TotalCorrect { get; set; }
    public int? TotalIncorrect { get; set; }
    public int? TotalSkipped { get; set; }
    public double? Score { get; set; }
}   