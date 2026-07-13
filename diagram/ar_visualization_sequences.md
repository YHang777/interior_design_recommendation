# AR Visualization Module - Sequence Diagrams

## 2.1 AR Room Scanning Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AR as AR Visualizer
    participant CM as Camera Manager
    participant RM as Room Detector
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
    AR->>DB: Save room layout data
    DB-->>AR: Room data saved
    AR-->>UI: Room detected
    UI-->>U: Show room layout
```

## 2.2 Furniture Placement Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AR as AR Visualizer
    participant RM as Room Detector
    participant FM as Furniture Manager
    participant DB as Database

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
```

## 2.3 AR Visualization Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AR as AR Visualizer
    participant CM as Camera Manager
    participant FM as Furniture Manager
    participant DB as Database

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
```

## 2.4 Design Save Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant AR as AR Visualizer
    participant DB as Database

    Note over U,DB: Design Save Process
    U->>UI: Save AR design
    UI->>AR: Capture current state
    AR->>DB: Save design data
    DB-->>AR: Design saved
    AR-->>UI: Save successful
    UI-->>U: Show save confirmation
``` 