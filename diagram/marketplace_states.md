# Marketplace Module - State Diagrams

## 6.1 Product Browsing State Diagram

```mermaid
stateDiagram-v2
    [*] --> MarketplaceAccess
    MarketplaceAccess --> LoadingCatalog: Browse Marketplace
    LoadingCatalog --> LoadingProducts: Catalog Loaded
    LoadingProducts --> ProductsLoaded: Products Retrieved
    ProductsLoaded --> LoadingSuppliers: Product Data Loaded
    LoadingSuppliers --> SuppliersLoaded: Supplier Information Retrieved
    SuppliersLoaded --> MarketDataReady: Supplier Data Loaded
    MarketDataReady --> MarketplaceDisplayed: All Data Ready
    MarketplaceDisplayed --> [*]: Marketplace Displayed
```

## 6.2 Product Search State Diagram

```mermaid
stateDiagram-v2
    [*] --> SearchRequest
    SearchRequest --> ProcessingQuery: Search for Products
    ProcessingQuery --> SearchingProducts: Query Processed
    SearchingProducts --> SearchResultsReady: Products Searched
    SearchResultsReady --> FilteredProductsDisplayed: Results Retrieved
    FilteredProductsDisplayed --> [*]: Search Results Displayed
```

## 6.3 Product Detail State Diagram

```mermaid
stateDiagram-v2
    [*] --> ProductSelection
    ProductSelection --> LoadingProductDetails: Select Product
    LoadingProductDetails --> ProductDetailsLoaded: Product Information Retrieved
    ProductDetailsLoaded --> LoadingSupplierDetails: Product Details Loaded
    LoadingSupplierDetails --> SupplierDetailsLoaded: Supplier Information Retrieved
    SupplierDetailsLoaded --> CompleteProductInfo: Supplier Details Loaded
    CompleteProductInfo --> ProductDetailsDisplayed: Complete Information Ready
    ProductDetailsDisplayed --> [*]: Product Details Displayed
```

## 6.4 Purchase Process State Diagram

```mermaid
stateDiagram-v2
    [*] --> AddingToCart
    AddingToCart --> UpdatingCart: Add to Cart
    UpdatingCart --> CartUpdated: Cart Updated
    CartUpdated --> ItemAdded: Item Added
    ItemAdded --> ProceedingToCheckout: Cart Update Shown
    ProceedingToCheckout --> ProcessingOrder: Proceed to Checkout
    ProcessingOrder --> OrderCreated: Order Processed
    OrderCreated --> NotifyingSupplier: Order Created
    NotifyingSupplier --> SupplierNotified: Supplier Notified
    SupplierNotified --> OrderProcessed: Notification Complete
    OrderProcessed --> [*]: Order Confirmation Shown
```

## 6.5 Order Tracking State Diagram

```mermaid
stateDiagram-v2
    [*] --> OrderStatusRequest
    OrderStatusRequest --> LoadingOrderData: View Order Status
    LoadingOrderData --> OrderDataLoaded: Order Data Retrieved
    OrderDataLoaded --> OrderStatusReady: Order Details Loaded
    OrderStatusReady --> [*]: Order Tracking Displayed
```

## 6.6 View Orders (Supplier) State Diagram

```mermaid
stateDiagram-v2
    [*] --> OrderDashboardAccess
    OrderDashboardAccess --> LoadingSupplierOrders: Open Order Dashboard
    LoadingSupplierOrders --> OrderDataRetrieved: Supplier Orders Retrieved
    OrderDataRetrieved --> OrderInformationReady: Order Data Loaded
    OrderInformationReady --> [*]: Order List Displayed
``` 