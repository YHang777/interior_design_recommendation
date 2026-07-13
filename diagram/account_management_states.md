# Account Management Module - State Diagrams

## 1.1 Create Account State Diagram

```mermaid
stateDiagram-v2
    [*] --> RegistrationForm
    RegistrationForm --> ValidatingInput: Fill Form
    ValidatingInput --> EmailExists: Email Already Exists
    ValidatingInput --> CreatingAccount: Email Valid
    EmailExists --> RegistrationForm: Show Error
    CreatingAccount --> SendingVerification: Account Created
    SendingVerification --> WaitingForVerification: Email Sent
    WaitingForVerification --> VerifyingEmail: User Clicks Link
    VerifyingEmail --> AccountActive: Verification Successful
    VerifyingEmail --> RegistrationForm: Verification Failed
    AccountActive --> [*]: Registration Complete
```

## 1.2 Login State Diagram

```mermaid
stateDiagram-v2
    [*] --> LoginForm
    LoginForm --> ValidatingCredentials: Enter Credentials
    ValidatingCredentials --> AuthenticationFailed: Invalid Credentials
    ValidatingCredentials --> CreatingSession: Valid Credentials
    AuthenticationFailed --> LoginForm: Show Error
    CreatingSession --> LoggingAttempt: Session Created
    LoggingAttempt --> Dashboard: Login Successful
    Dashboard --> [*]: User Logged In
```

## 1.3 Manage Profile State Diagram

```mermaid
stateDiagram-v2
    [*] --> ProfileView
    ProfileView --> LoadingProfile: Access Profile
    LoadingProfile --> ProfileForm: Data Loaded
    ProfileForm --> UpdatingProfile: Submit Changes
    UpdatingProfile --> ValidatingChanges: Changes Submitted
    ValidatingChanges --> ProfileUpdated: Validation Passed
    ValidatingChanges --> ProfileForm: Validation Failed
    ProfileUpdated --> ProfileView: Show Success
    ProfileView --> [*]: Profile Management Complete
```

## 1.4 Password Reset State Diagram

```mermaid
stateDiagram-v2
    [*] --> PasswordResetForm
    PasswordResetForm --> ValidatingEmail: Submit Email
    ValidatingEmail --> EmailNotFound: Email Not Found
    ValidatingEmail --> GeneratingToken: Email Valid
    EmailNotFound --> PasswordResetForm: Show Error
    GeneratingToken --> SendingResetEmail: Token Generated
    SendingResetEmail --> WaitingForReset: Email Sent
    WaitingForReset --> EnteringNewPassword: User Clicks Link
    EnteringNewPassword --> ValidatingNewPassword: Submit New Password
    ValidatingNewPassword --> PasswordUpdated: Password Valid
    ValidatingNewPassword --> EnteringNewPassword: Password Invalid
    PasswordUpdated --> [*]: Reset Complete
```

## 1.5 Account Deletion State Diagram

```mermaid
stateDiagram-v2
    [*] --> DeletionRequest
    DeletionRequest --> VerifyingIdentity: Request Deletion
    VerifyingIdentity --> SendingConfirmation: Identity Verified
    SendingConfirmation --> WaitingForConfirmation: Email Sent
    WaitingForConfirmation --> ConfirmingDeletion: User Confirms
    ConfirmingDeletion --> ProcessingDeletion: Confirmation Received
    ProcessingDeletion --> CleaningUpData: Account Deleted
    CleaningUpData --> DeletionComplete: Cleanup Done
    DeletionComplete --> [*]: Account Deleted
``` 