# Budget Calculation Module - State Diagrams

## 5.1 Budget Setup State Diagram

```mermaid
stateDiagram-v2
    [*] --> BudgetSetup
    BudgetSetup --> SettingBudgetLimit: Set Budget Limit
    SettingBudgetLimit --> CreatingBudgetPlan: Limit Set
    CreatingBudgetPlan --> SavingConfiguration: Plan Created
    SavingConfiguration --> BudgetSaved: Configuration Saved
    BudgetSaved --> BudgetConfigured: Budget Ready
    BudgetConfigured --> [*]: Budget Setup Complete
```

## 5.2 Cost Calculation State Diagram

```mermaid
stateDiagram-v2
    [*] --> AddingItems
    AddingItems --> CalculatingCosts: Add Items to Budget
    CalculatingCosts --> GettingPrices: Costs Calculation Started
    GettingPrices --> PricesRetrieved: Product Prices Retrieved
    PricesRetrieved --> CalculatingTotal: Prices Loaded
    CalculatingTotal --> UpdatingCalculations: Total Calculated
    UpdatingCalculations --> CalculationsSaved: Budget Updated
    CalculationsSaved --> BudgetUpdated: Calculations Saved
    BudgetUpdated --> [*]: Budget Status Displayed
```

## 5.3 Budget Tracking State Diagram

```mermaid
stateDiagram-v2
    [*] --> ViewingBudget
    ViewingBudget --> LoadingBudgetData: View Budget Status
    LoadingBudgetData --> BudgetDataLoaded: Budget Data Retrieved
    BudgetDataLoaded --> CalculatingRemaining: Data Loaded
    CalculatingRemaining --> RemainingCalculated: Remaining Amount Calculated
    RemainingCalculated --> BudgetStatusReady: Calculation Complete
    BudgetStatusReady --> [*]: Budget Tracking Displayed
```

## 5.4 Budget Alert State Diagram

```mermaid
stateDiagram-v2
    [*] --> BudgetMonitoring
    BudgetMonitoring --> CheckingBudget: Monitor Budget
    CheckingBudget --> BudgetExceeded: Budget Exceeded
    CheckingBudget --> BudgetWithinLimit: Budget Within Limit
    BudgetExceeded --> SendingAlert: Send Budget Alert
    BudgetWithinLimit --> UpdatingDisplay: Update Budget Display
    SendingAlert --> AlertShown: Alert Sent
    UpdatingDisplay --> StatusShown: Display Updated
    AlertShown --> [*]: Budget Warning Displayed
    StatusShown --> [*]: Budget Status Shown
```

## 5.5 Budget Adjustment State Diagram

```mermaid
stateDiagram-v2
    [*] --> AdjustingBudget
    AdjustingBudget --> RecalculatingCosts: Adjust Budget Items
    RecalculatingCosts --> UpdatingPlan: Costs Recalculated
    UpdatingPlan --> SavingAdjustments: Plan Updated
    SavingAdjustments --> AdjustmentsSaved: Adjustments Saved
    AdjustmentsSaved --> BudgetUpdated: Budget Updated
    BudgetUpdated --> [*]: Adjusted Budget Displayed
``` 