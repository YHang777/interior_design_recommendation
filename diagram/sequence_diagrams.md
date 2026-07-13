# 📊 Process Design - Sequence Diagrams

## 4.5 Process Design - Sequence Diagram

### 4.5.1 Account & Profile Management Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AM as Account Manager
    participant DB as Database
    participant EM as Email Service

    Note over U,EM: User Registration Process
    U->>UI: Enter registration details
    UI->>AM: Validate registration data
    AM->>DB: Check if email exists
    DB-->>AM: Email status
    alt Email not exists
        AM->>DB: Create new user account
        DB-->>AM: Account created
        AM->>EM: Send verification email
        EM-->>U: Verification email sent
        U->>UI: Click verification link
        UI->>AM: Verify email token
        AM->>DB: Update account status
        DB-->>AM: Status updated
        AM-->>UI: Registration successful
        UI-->>U: Show success message
    else Email exists
        AM-->>UI: Email already registered
        UI-->>U: Show error message
    end

    Note over U,EM: Profile Management Process
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

    Note over U,EM: Password Change Process
    U->>UI: Request password change
    UI->>AM: Validate current password
    AM->>DB: Verify current password
    DB-->>AM: Password verification
    alt Password correct
        AM->>EM: Send password reset email
        EM-->>U: Reset email sent
        U->>UI: Enter new password
        UI->>AM: Validate new password
        AM->>DB: Update password
        DB-->>AM: Password updated
        AM-->>UI: Password changed
        UI-->>U: Show success message
    else Password incorrect
        AM-->>UI: Invalid password
        UI-->>U: Show error message
    end

    Note over U,EM: Account Deletion Process
    U->>UI: Request account deletion
    UI->>AM: Verify user identity
    AM->>EM: Send deletion confirmation
    EM-->>U: Confirmation email
    U->>UI: Confirm deletion
    UI->>AM: Process deletion request
    AM->>DB: Delete user account
    AM->>DB: Clean up related data
    DB-->>AM: Deletion completed
    AM-->>UI: Account deleted
    UI-->>U: Show deletion confirmation
```

### 4.5.2 Authentication Module

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

    Note over U,SM: Session Management
    U->>UI: Access protected resource
    UI->>SM: Validate session token
    SM->>DB: Check session validity
    DB-->>SM: Session status
    alt Session valid
        SM-->>UI: Session valid
        UI-->>U: Allow access
    else Session expired
        SM-->>UI: Session expired
        UI-->>U: Redirect to login
    end

    Note over U,SM: Logout Process
    U->>UI: Request logout
    UI->>SM: Invalidate session
    SM->>DB: Remove session data
    DB-->>SM: Session removed
    SM-->>UI: Logout successful
    UI-->>U: Redirect to login page

    Note over U,SM: Password Reset Process
    U->>UI: Request password reset
    UI->>AM: Validate email address
    AM->>DB: Check email exists
    DB-->>AM: Email status
    alt Email exists
        AM->>DB: Generate reset token
        DB-->>AM: Token generated
        AM->>UI: Send reset email
        UI-->>U: Reset email sent
    else Email not found
        AM-->>UI: Email not found
        UI-->>U: Show error message
    end
```

### 4.5.3 AR Visualize Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AR as AR Visualizer
    participant CM as Camera Manager
    participant RM as Room Detector
    participant FM as Furniture Manager
    participant DB as Database

    Note over U,DB: AR Room Scanning Process
    U->>UI: Start AR room scan
    UI->>AR: Initialize AR session
    AR->>CM: Activate camera
    CM-->>AR: Camera ready
    AR->>RM: Start room detection
    RM->>CM: Capture room data
    CM-->>RM: Room images
    RM->>AR: Process room dimensions
    AR-->>UI: Room detected
    UI-->>U: Show room layout

    Note over U,DB: Furniture Placement Process
    U->>UI: Select furniture item
    UI->>FM: Get furniture data
    FM->>DB: Retrieve furniture catalog
    DB-->>FM: Furniture information
    FM-->>UI: Furniture details
    UI-->>U: Display furniture options
    U->>UI: Place furniture in AR
    UI->>AR: Add furniture to scene
    AR->>RM: Check placement validity
    RM-->>AR: Placement status
    alt Valid placement
        AR->>DB: Save furniture placement
        DB-->>AR: Placement saved
        AR-->>UI: Furniture placed
        UI-->>U: Show placement confirmation
    else Invalid placement
        AR-->>UI: Invalid placement
        UI-->>U: Show error message
    end

    Note over U,DB: AR Visualization Process
    U->>UI: Request AR visualization
    UI->>AR: Load saved design
    AR->>DB: Retrieve design data
    DB-->>AR: Design information
    AR->>FM: Load furniture models
    FM-->>AR: 3D models loaded
    AR->>CM: Overlay design on camera
    CM-->>AR: AR overlay ready
    AR-->>UI: AR visualization active
    UI-->>U: Display AR view

    Note over U,DB: Design Save Process
    U->>UI: Save AR design
    UI->>AR: Capture current state
    AR->>DB: Save design data
    DB-->>AR: Design saved
    AR-->>UI: Save successful
    UI-->>U: Show save confirmation
```

### 4.5.4 AI Recommendation Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AI as AI Recommendation Engine
    participant PM as Preference Manager
    participant DM as Design Analyzer
    participant PRM as Product Matcher
    participant DB as Database

    Note over U,DB: Preference Collection Process
    U->>UI: Access AI recommendations
    UI->>PM: Get user preferences
    PM->>DB: Retrieve user data
    DB-->>PM: User preferences
    PM-->>UI: Preference data
    UI-->>U: Display preference form
    U->>UI: Update preferences
    UI->>PM: Save preference changes
    PM->>DB: Update user preferences
    DB-->>PM: Preferences updated
    PM-->>UI: Preferences saved
    UI-->>U: Show confirmation

    Note over U,DB: Design Analysis Process
    U->>UI: Submit room design
    UI->>DM: Analyze design requirements
    DM->>DB: Get design context
    DB-->>DM: Design information
    DM->>AI: Process design analysis
    AI->>DM: Design insights
    DM-->>UI: Analysis results
    UI-->>U: Display analysis

    Note over U,DB: Recommendation Generation Process
    U->>UI: Request recommendations
    UI->>AI: Generate recommendations
    AI->>PM: Get user preferences
    PM->>DB: Retrieve preference data
    DB-->>PM: User preferences
    PM-->>AI: Preference information
    AI->>DM: Analyze design context
    DM-->>AI: Design analysis
    AI->>PRM: Match products to preferences
    PRM->>DB: Get product catalog
    DB-->>PRM: Product data
    PRM-->>AI: Matched products
    AI-->>UI: Generated recommendations
    UI-->>U: Display recommendations

    Note over U,DB: Recommendation Feedback Process
    U->>UI: Provide feedback on recommendations
    UI->>AI: Process user feedback
    AI->>PM: Update preference model
    PM->>DB: Save feedback data
    DB-->>PM: Feedback saved
    PM-->>AI: Model updated
    AI-->>UI: Feedback processed
    UI-->>U: Show thank you message
```

### 4.5.5 Dashboard Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant DM as Dashboard Manager
    participant ANM as Analytics Manager
    participant PM as Project Manager
    participant BM as Budget Manager
    participant DB as Database

    Note over U,DB: Dashboard Initialization
    U->>UI: Access dashboard
    UI->>DM: Load dashboard data
    DM->>ANM: Get user analytics
    ANM->>DB: Retrieve user statistics
    DB-->>ANM: Analytics data
    ANM-->>DM: User analytics
    DM->>PM: Get project data
    PM->>DB: Retrieve user projects
    DB-->>PM: Project information
    PM-->>DM: Project data
    DM->>BM: Get budget information
    BM->>DB: Retrieve budget data
    DB-->>BM: Budget information
    BM-->>DM: Budget data
    DM-->>UI: Dashboard data ready
    UI-->>U: Display dashboard

    Note over U,DB: Quick Actions Process
    U->>UI: Select quick action
    UI->>DM: Process action request
    DM->>UI: Navigate to action
    UI-->>U: Open action screen

    Note over U,DB: Project Overview Process
    U->>UI: View project overview
    UI->>PM: Get project details
    PM->>DB: Retrieve project data
    DB-->>PM: Project information
    PM-->>UI: Project details
    UI-->>U: Display project overview

    Note over U,DB: Analytics Update Process
    U->>UI: Refresh analytics
    UI->>ANM: Update analytics data
    ANM->>DB: Get latest statistics
    DB-->>ANM: Updated analytics
    ANM-->>UI: New analytics data
    UI-->>U: Update dashboard display
```

### 4.5.6 Budget Calculation Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager
    participant CM as Cost Calculator
    participant PRM as Product Manager
    participant DB as Database

    Note over U,DB: Budget Setup Process
    U->>UI: Set budget limit
    UI->>BM: Create budget plan
    BM->>DB: Save budget configuration
    DB-->>BM: Budget saved
    BM-->>UI: Budget configured
    UI-->>U: Show budget setup

    Note over U,DB: Cost Calculation Process
    U->>UI: Add items to budget
    UI->>CM: Calculate item costs
    CM->>PRM: Get product prices
    PRM->>DB: Retrieve product data
    DB-->>PRM: Product information
    PRM-->>CM: Product prices
    CM->>BM: Calculate total cost
    BM->>DB: Update budget calculations
    DB-->>BM: Calculations saved
    BM-->>UI: Updated budget
    UI-->>U: Display budget status

    Note over U,DB: Budget Tracking Process
    U->>UI: View budget status
    UI->>BM: Get budget information
    BM->>DB: Retrieve budget data
    DB-->>BM: Budget information
    BM->>CM: Calculate remaining budget
    CM-->>BM: Remaining amount
    BM-->>UI: Budget status
    UI-->>U: Display budget tracking

    Note over U,DB: Budget Alert Process
    alt Budget exceeded
        BM->>UI: Send budget alert
        UI-->>U: Show budget warning
    else Budget within limit
        BM->>UI: Update budget display
        UI-->>U: Show budget status
    end

    Note over U,DB: Budget Adjustment Process
    U->>UI: Adjust budget items
    UI->>CM: Recalculate costs
    CM->>BM: Update budget plan
    BM->>DB: Save adjustments
    DB-->>BM: Adjustments saved
    BM-->>UI: Updated budget
    UI-->>U: Show adjusted budget
```

### 4.5.7 Market Module

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant MM as Market Manager
    participant PM as Product Manager
    participant SM as Supplier Manager
    participant OM as Order Manager
    participant DB as Database

    Note over U,DB: Product Browsing Process
    U->>UI: Browse marketplace
    UI->>MM: Load product catalog
    MM->>PM: Get product list
    PM->>DB: Retrieve products
    DB-->>PM: Product data
    PM-->>MM: Product information
    MM->>SM: Get supplier information
    SM->>DB: Retrieve supplier data
    DB-->>SM: Supplier information
    SM-->>MM: Supplier details
    MM-->>UI: Market data ready
    UI-->>U: Display marketplace

    Note over U,DB: Product Search Process
    U->>UI: Search for products
    UI->>PM: Process search query
    PM->>DB: Search products
    DB-->>PM: Search results
    PM-->>UI: Filtered products
    UI-->>U: Display search results

    Note over U,DB: Product Detail Process
    U->>UI: Select product
    UI->>PM: Get product details
    PM->>DB: Retrieve product information
    DB-->>PM: Product details
    PM->>SM: Get supplier details
    SM->>DB: Get supplier information
    DB-->>SM: Supplier data
    SM-->>PM: Supplier details
    PM-->>UI: Complete product information
    UI-->>U: Display product details

    Note over U,DB: Purchase Process
    U->>UI: Add to cart
    UI->>OM: Add item to cart
    OM->>DB: Update cart
    DB-->>OM: Cart updated
    OM-->>UI: Item added
    UI-->>U: Show cart update
    U->>UI: Proceed to checkout
    UI->>OM: Process order
    OM->>DB: Create order
    DB-->>OM: Order created
    OM->>SM: Notify supplier
    SM-->>OM: Supplier notified
    OM-->>UI: Order processed
    UI-->>U: Show order confirmation

    Note over U,DB: Order Tracking Process
    U->>UI: View order status
    UI->>OM: Get order information
    OM->>DB: Retrieve order data
    DB-->>OM: Order details
    OM-->>UI: Order status
    UI-->>U: Display order tracking
```

---

## 📋 Import Instructions for draw.io

1. **Copy the Mermaid code** from any section above
2. **Open draw.io** in your browser
3. **Create a new diagram** or open existing one
4. **Go to File > Import From > Text**
5. **Paste the Mermaid code** in the text area
6. **Click Import** to add the sequence diagram to your diagram

## 🔧 Customization Notes

- **Actors/Objects**: You can modify participant names to match your specific system components
- **Messages**: Update message descriptions to reflect your exact business processes
- **Flow**: Adjust the sequence flow based on your specific implementation requirements
- **Error Handling**: Add additional alt/else blocks for error scenarios as needed

## 📊 Diagram Features

Each sequence diagram includes:
- ✅ **Clear participant identification**
- ✅ **Logical process flow**
- ✅ **Database interactions**
- ✅ **Error handling scenarios**
- ✅ **User interface interactions**
- ✅ **Service layer communications** 