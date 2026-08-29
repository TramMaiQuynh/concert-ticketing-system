namespace ConcertTicketing.Domain.Models;

public class UserAccount
{
    public int UserID { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string AccountStatus { get; set; } = string.Empty; // Active/Suspended/Deactivated
    public DateTime CreatedAt { get; set; }
}

public class UserRoleAssignment
{
    public int UserID { get; set; }
    public int RoleID { get; set; }
    public string RoleName { get; set; } = string.Empty;
}
