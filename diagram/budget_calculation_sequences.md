# Budget Calculation Module - Sequence Diagrams

## 5.1 Budget Setup Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager
    participant DB as Database

    Note over U,DB: Budget Setup Process
    U->>UI: Set budget limit
    UI->>BM: Create budget plan
    BM->>DB: Save budget configuration
    DB-->>BM: Budget saved
    BM-->>UI: Budget configured
    UI-->>U: Show budget setup
```

## 5.2 Cost Calculation Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager
    participant CM as Cost Calculator
    participant PRM as Product Manager
    participant DB as Database

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
```

## 5.3 Budget Tracking Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager
    participant CM as Cost Calculator
    participant DB as Database

    Note over U,DB: Budget Tracking Process
    U->>UI: View budget status
    UI->>BM: Get budget information
    BM->>DB: Retrieve budget data
    DB-->>BM: Budget information
    BM->>CM: Calculate remaining budget
    CM-->>BM: Remaining amount
    BM-->>UI: Budget status
    UI-->>U: Display budget tracking
```

## 5.4 Budget Alert Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager

    Note over U,BM: Budget Alert Process
    alt Budget exceeded
        BM->>UI: Send budget alert
        UI-->>U: Show budget warning
    else Budget within limit
        BM->>UI: Update budget display
        UI-->>U: Show budget status
    end
```

## 5.5 Budget Adjustment Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant BM as Budget Manager
    participant CM as Cost Calculator
    participant DB as Database

    Note over U,DB: Budget Adjustment Process
    U->>UI: Adjust budget items
    UI->>CM: Recalculate costs
    CM->>BM: Update budget plan
    BM->>DB: Save adjustments
    DB-->>BM: Adjustments saved
    BM-->>UI: Updated budget
    UI-->>U: Show adjusted budget
``` 