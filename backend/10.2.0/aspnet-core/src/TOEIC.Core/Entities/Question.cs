using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Abp.Domain.Entities;

[Table("Questions")]
public class Question : Entity<Guid>
{
    [Required]
    public Guid ExamId { get; set; }

    [ForeignKey("ExamId")]
    public virtual Exam Exam { get; set; }

    public int PartNumber { get; set; } // Part 5, 6 hoặc 7

    [MaxLength(50)]
    public string GroupIdentifier { get; set; } // Mã nhóm (VD: '131-134')

    public string PassageContent { get; set; } // Nội dung đoạn văn / hình ảnh

    public int QuestionOrder { get; set; } // Số thứ tự câu hỏi (101, 131...)

    [Required]
    public string QuestionText { get; set; }

    public string Explanation { get; set; } // Gợi ý / Giải thích đáp án

    public bool ShuffleQuestion { get; set; } = true;
    public bool ShuffleAnswers { get; set; } = true;

    // Quan hệ 1 - nhiều với Answers
    public virtual ICollection<Answer> Answers { get; set; }
}