# AI Recommendation Module - Sequence Diagrams

## 3.1 Preference Collection Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant PM as Preference Manager
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
```

## 3.2 Design Analysis Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant DM as Design Analyzer
    participant AI as AI Recommendation Engine
    participant DB as Database

    Note over U,DB: Design Analysis Process
    U->>UI: Submit room design
    UI->>DM: Analyze design requirements
    DM->>DB: Get design context
    DB-->>DM: Design information
    DM->>AI: Process design analysis
    AI->>DM: Design insights
    DM-->>UI: Analysis results
    UI-->>U: Display analysis
```

## 3.3 Recommendation Generation Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AI as AI Recommendation Engine
    participant PM as Preference Manager
    participant DM as Design Analyzer
    participant PRM as Product Matcher
    participant DB as Database

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
```

## 3.4 Recommendation Feedback Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AI as AI Recommendation Engine
    participant PM as Preference Manager
    participant DB as Database

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