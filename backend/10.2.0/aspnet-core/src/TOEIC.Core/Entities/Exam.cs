using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Abp.Domain.Entities;

[Table("Exams")]
public class Exam : Entity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Title { get; set; }

    public int Duration { get; set; } = 75; // Thời gian làm bài (phút)

    public int TotalQuestions { get; set; } = 100;

    public bool IsPublished { get; set; } = false; // 0: Bản nháp, 1: Đã xuất bản

    public DateTime CreationTime { get; set; } = DateTime.Now;

    public long? CreatorUserId { get; set; }

    // Quan hệ 1 - nhiều với Questions
    public virtual ICollection<Question> Questions { get; set; }
}   