/// App-wide string constants.
/// Malaysian context — MYR currency, local terminology.
class AppStrings {
  AppStrings._();

  // App
  static const String appTitle = 'Interior Design';
  static const String appSubtitle =
      'AI-powered home design recommendations';

  // Auth
  static const String login = 'Login';
  static const String signUp = 'Sign Up';
  static const String createAccount = 'Create Account';
  static const String forgotPassword = 'Forgot Password?';
  static const String dontHaveAccount = "Don't have an account?";
  static const String alreadyHaveAccount = 'Already have an account?';
  static const String emailLabel = 'Email';
  static const String passwordLabel = 'Password';
  static const String confirmPasswordLabel = 'Confirm Password';
  static const String fullNameLabel = 'Full Name';
  static const String phoneLabel = 'Phone (optional)';
  static const String resetPassword = 'Send Reset Link';
  static const String verifyEmailTitle = 'Verify Your Email';
  static const String verifyEmailBody =
      'We have sent a verification email to your address. '
      'Please check your inbox and follow the instructions.';
  static const String resendEmail = 'Resend Verification Email';
  static const String iveVerified = "I've Verified";

  // Errors
  static const String invalidEmail = 'Please enter a valid email address';
  static const String invalidPassword =
      'Password must be at least 8 characters with an uppercase letter and a number';
  static const String passwordsDontMatch = 'Passwords do not match';
  static const String requiredField = 'This field is required';
  static const String loginFailed = 'Login failed';
  static const String registrationFailed = 'Registration failed';
  static const String wrongPassword = 'Incorrect password';
  static const String userNotFound = 'No account found with this email';
  static const String tooManyRequests =
      'Too many attempts. Please try again later.';
  static const String emailNotVerified =
      'Please verify your email first. Check your inbox.';

  // Currency
  static const String currencyCode = 'MYR';
  static String formatMyr(int amount) => 'RM ${amount.toString()}';
}
