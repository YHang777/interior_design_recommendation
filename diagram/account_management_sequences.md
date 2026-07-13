# Account Management Module - Sequence Diagrams

## 1.1 Create Account Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Account Manager
    participant DB as Database
    participant EM as Email Service

    Note over U,EM: Create Account Process
    U->>UI: Navigate to Create Account page
    UI-->>U: Display registration form
    U->>UI: Fill in user details
    UI->>AM: Validate input data
    AM->>DB: Check if email exists
    DB-->>AM: Email status
    alt Email not exists
        AM->>DB: Create account in inactive state
        DB-->>AM: Account created
        AM->>EM: Send verification email
        EM-->>U: Verification email sent
        U->>UI: Navigate to email
        U->>UI: Complete verification step
        UI->>AM: Verify email token
        AM->>DB: Update account status to active
        DB-->>AM: Status updated
        AM-->>UI: Account creation successful
        UI-->>U: Show success message
    else Email exists
        AM-->>UI: Email already exists
        UI-->>U: Show "Email existed" message
    end
```

## 1.2 Login Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Authentication Manager
    participant DB as Database
    participant SM as Session Manager

    Note over U,SM: Login Process
    U->>UI: Enter credentials
    UI->>AM: Validate input format
    AM->>DB: Check user credentials
    DB-->>AM: User authentication result
    alt Authentication successful
        AM->>SM: Create user session
        SM-->>AM: Session token
        AM->>DB: Log login attempt
        DB-->>AM: Log recorded
        AM-->>UI: Authentication successful
        UI-->>U: Redirect to dashboard
    else Authentication failed
        AM->>DB: Log failed attempt
        DB-->>AM: Log recorded
        AM-->>UI: Authentication failed
        UI-->>U: Show error message
    end
```

## 1.3 Manage Profile Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Account Manager
    participant DB as Database

    Note over U,DB: Profile Management Process
    U->>UI: Access profile settings
    UI->>AM: Get user profile data
    AM->>DB: Retrieve user information
    DB-->>AM: User data
    AM-->>UI: Profile data
    UI-->>U: Display profile form
    U->>UI: Update profile information
    UI->>AM: Validate updated data
    AM->>DB: Update user profile
    DB-->>AM: Update confirmed
    AM-->>UI: Profile updated
    UI-->>U: Show success message
```

## 1.4 Password Reset Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Authentication Manager
    participant DB as Database
    participant EM as Email Service

    Note over U,EM: Password Reset Process
    U->>UI: Request password reset
    UI->>AM: Validate email address
    AM->>DB: Check email exists
    DB-->>AM: Email status
    alt Email exists
        AM->>DB: Generate reset token
        DB-->>AM: Token generated
        AM->>EM: Send reset email
        EM-->>U: Reset email sent
        U->>UI: Enter new password
        UI->>AM: Validate new password
        AM->>DB: Update password
        DB-->>AM: Password updated
        AM-->>UI: Password reset successful
        UI-->>U: Show success message
    else Email not found
        AM-->>UI: Email not found
        UI-->>U: Show error message
    end
```

## 1.5 Account Deletion Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Account Manager
    participant DB as Database
    participant EM as Email Service

    Note over U,EM: Account Deletion Process
    U->>UI: Request account deletion
    UI->>AM: Verify user identity
    AM->>EM: Send deletion confirmation
    EM-->>U: Confirmation email
    U->>UI: Confirm deletion
    UI->>AM: Process deletion request
    AM->>DB: Delete user account
    AM-->>DB: Clean up related data
    DB-->>AM: Deletion completed
    AM-->>UI: Account deleted
    UI-->>U: Show deletion confirmation
``` 