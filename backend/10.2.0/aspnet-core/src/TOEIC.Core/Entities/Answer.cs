using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Abp.Domain.Entities;

[Table("Answers")]
public class Answer : Entity<Guid>
{
    [Required]
    public Guid QuestionId { get; set; }

    [ForeignKey("QuestionId")]
    public virtual Question Question { get; set; }

    [Required]
    [MaxLength(5)]
    public string OptionKey { get; set; } // 'A', 'B', 'C', 'D'

    [Required]
    public string OptionText { get; set; }

    public bool IsCorrect { get; set; } = false; // 1: Đúng, 0: Sai
}