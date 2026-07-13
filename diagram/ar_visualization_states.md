# AR Visualization Module - State Diagrams

## 2.1 AR Room Scanning State Diagram

```mermaid
stateDiagram-v2
    [*] --> ARSession
    ARSession --> InitializingAR: Start AR Scan
    InitializingAR --> ActivatingCamera: AR Initialized
    ActivatingCamera --> CameraReady: Camera Activated
    CameraReady --> StartingDetection: Camera Ready
    StartingDetection --> CapturingRoomData: Detection Started
    CapturingRoomData --> ProcessingDimensions: Room Data Captured
    ProcessingDimensions --> SavingRoomData: Dimensions Processed
    SavingRoomData --> RoomDetected: Data Saved
    RoomDetected --> [*]: Room Layout Displayed
```

## 2.2 Furniture Placement State Diagram

```mermaid
stateDiagram-v2
    [*] --> FurnitureSelection
    FurnitureSelection --> LoadingFurnitureData: Select Furniture
    LoadingFurnitureData --> FurnitureLoaded: Data Retrieved
    FurnitureLoaded --> DisplayingOptions: Furniture Details Loaded
    DisplayingOptions --> PlacingFurniture: User Places Item
    PlacingFurniture --> CheckingPlacement: Furniture Added to Scene
    CheckingPlacement --> ValidPlacement: Placement Valid
    CheckingPlacement --> InvalidPlacement: Placement Invalid
    ValidPlacement --> SavingPlacement: Placement Confirmed
    InvalidPlacement --> DisplayingOptions: Show Error
    SavingPlacement --> PlacementComplete: Placement Saved
    PlacementComplete --> [*]: Furniture Placed Successfully
```

## 2.3 AR Visualization State Diagram

```mermaid
stateDiagram-v2
    [*] --> ARVisualizationRequest
    ARVisualizationRequest --> LoadingDesign: Request Visualization
    LoadingDesign --> DesignLoaded: Design Retrieved
    DesignLoaded --> LoadingFurnitureModels: Design Data Loaded
    LoadingFurnitureModels --> ModelsLoaded: 3D Models Loaded
    ModelsLoaded --> CreatingOverlay: Models Ready
    CreatingOverlay --> AROverlayReady: Overlay Created
    AROverlayReady --> VisualizationActive: AR Active
    VisualizationActive --> [*]: AR View Displayed
```

## 2.4 Design Save State Diagram

```mermaid
stateDiagram-v2
    [*] --> SaveRequest
    SaveRequest --> CapturingState: User Saves Design
    CapturingState --> SavingDesign: Current State Captured
    SavingDesign --> DesignSaved: Design Data Saved
    DesignSaved --> SaveComplete: Save Successful
    SaveComplete --> [*]: Design Saved Successfully
``` 