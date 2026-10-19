using Abp.Zero.EntityFrameworkCore;
using TOEIC.Authorization.Roles;
using TOEIC.Authorization.Users;
using TOEIC.MultiTenancy;
using Microsoft.EntityFrameworkCore;

namespace TOEIC.EntityFrameworkCore;

public class TOEICDbContext : AbpZeroDbContext<Tenant, Role, User, TOEICDbContext>
{
    /* Define a DbSet for each entity of the application */

    public virtual DbSet<Exam> Exams { get; set; }
    public virtual DbSet<Question> Questions { get; set; }
    public virtual DbSet<Answer> Answers { get; set; }
    public virtual DbSet<UserExamResult> UserExamResults { get; set; }
    public virtual DbSet<UserAnswer> UserAnswers { get; set; }

    public TOEICDbContext(DbContextOptions<TOEICDbContext> options)
        : base(options)
    {
    }
}
