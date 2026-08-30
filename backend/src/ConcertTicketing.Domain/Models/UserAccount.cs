namespace ConcertTicketing.Domain.Models;

public class UserAccount
{
    public int UserID { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;   // DB: DisplayName (không phải FullName)
    public string AccountStatus { get; set; } = string.Empty; // Active / Locked / Disabled
    public DateTime CreatedTimestamp { get; set; }             // DB: CreatedTimestamp (không phải CreatedAt)
}

public class UserRoleAssignment
{
    public int UserID { get; set; }
    public int RoleID { get; set; }
    public string RoleName { get; set; } = string.Empty;
    public string AssignmentStatus { get; set; } = string.Empty; // Active / Revoked
}
