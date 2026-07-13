# Dashboard Module - Sequence Diagrams

## 4.1 Dashboard Initialization Sequence Diagram

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
```

## 4.2 Quick Actions Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant DM as Dashboard Manager

    Note over U,DM: Quick Actions Process
    U->>UI: Select quick action
    UI->>DM: Process action request
    DM->>UI: Navigate to action
    UI-->>U: Open action screen
```

## 4.3 Project Overview Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant PM as Project Manager
    participant DB as Database

    Note over U,DB: Project Overview Process
    U->>UI: View project overview
    UI->>PM: Get project details
    PM->>DB: Retrieve project data
    DB-->>PM: Project information
    PM-->>UI: Project details
    UI-->>U: Display project overview
```

## 4.4 Analytics Update Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant ANM as Analytics Manager
    participant DB as Database

    Note over U,DB: Analytics Update Process
    U->>UI: Refresh analytics
    UI->>ANM: Update analytics data
    ANM->>DB: Get latest statistics
    DB-->>ANM: Updated analytics
    ANM-->>UI: New analytics data
    UI-->>U: Update dashboard display
``` 