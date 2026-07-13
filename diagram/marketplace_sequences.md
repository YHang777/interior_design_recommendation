# Marketplace Module - Sequence Diagrams

## 6.1 Product Browsing Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant MM as Market Manager
    participant PM as Product Manager
    participant SM as Supplier Manager
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
```

## 6.2 Product Search Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant PM as Product Manager
    participant DB as Database

    Note over U,DB: Product Search Process
    U->>UI: Search for products
    UI->>PM: Process search query
    PM->>DB: Search products
    DB-->>PM: Search results
    PM-->>UI: Filtered products
    UI-->>U: Display search results
```

## 6.3 Product Detail Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant PM as Product Manager
    participant SM as Supplier Manager
    participant DB as Database

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
```

## 6.4 Purchase Process Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant OM as Order Manager
    participant SM as Supplier Manager
    participant DB as Database

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
```

## 6.5 Order Tracking Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant UI as User Interface
    participant OM as Order Manager
    participant DB as Database

    Note over U,DB: Order Tracking Process
    U->>UI: View order status
    UI->>OM: Get order information
    OM->>DB: Retrieve order data
    DB-->>OM: Order details
    OM-->>UI: Order status
    UI-->>U: Display order tracking
```

## 6.6 View Orders (Supplier) Sequence Diagram

```mermaid
sequenceDiagram
    participant S as Supplier
    participant UI as User Interface
    participant OM as Order Manager
    participant DB as Database

    Note over S,DB: View Orders Process
    S->>UI: Open order dashboard
    UI->>OM: Get supplier orders
    OM->>DB: Retrieve order data
    DB-->>OM: Order list
    OM-->>UI: Order information
    UI-->>S: Display order list
``` 