classDiagram
    %% User Management
    class User {
        +String id
        +String name
        +String email
        +String password
        +String phone
        +String address
        +String role
        +String profilePicture
        +DateTime createdAt
        +DateTime updatedAt
        +login()
        +logout()
        +changePassword()
        +updateProfile()
        +getRole()
        +getId()
        +getName()
        +getEmail()
        +getPhone()
        +getAddress()
        +setName(String name)
        +setEmail(String email)
        +setPhone(String phone)
        +setAddress(String address)
        +setProfilePicture(String picture)
    }
    
    %% Supplier Management
    class Supplier {
        +String id
        +String name
        +String email
        +String phone
        +String address
        +String businessLicense
        +String description
        +DateTime createdAt
        +DateTime updatedAt
        +registerSupplier()
        +updateSupplierInfo()
        +viewProducts()
        +manageOrders()
        +viewAnalytics()
        +getId()
        +getName()
        +getEmail()
        +getPhone()
        +getAddress()
        +setName(String name)
        +setEmail(String email)
        +setPhone(String phone)
        +setAddress(String address)
        +setBusinessLicense(String license)
        +setDescription(String description)
    }
    
    %% Product Management
    class Product {
        +String id
        +String name
        +String description
        +int price
        +int stock
        +String image
        +String category
        +String designStyle
        +String supplierId
        +DateTime createdAt
        +DateTime updatedAt
        +addProduct()
        +updateProduct()
        +deleteProduct()
        +updateStock()
        +getProductInfo()
        +getId()
        +getName()
        +getPrice()
        +getStock()
        +getCategory()
        +setName(String name)
        +setDescription(String description)
        +setPrice(int price)
        +setStock(int stock)
        +setImage(String image)
        +setCategory(String category)
        +setDesignStyle(String style)
    }
    
    %% Order Management
    class Order {
        +String id
        +String userId
        +String supplierId
        +double totalAmount
        +String status
        +String shippingAddress
        +DateTime orderDate
        +DateTime deliveryDate
        +DateTime createdAt
        +DateTime updatedAt
        +createOrder()
        +updateOrderStatus()
        +calculateTotalAmount()
        +cancelOrder()
        +assignToSupplier()
        +getId()
        +getUserId()
        +getSupplierId()
        +getTotalAmount()
        +getStatus()
        +setStatus(String status)
        +setTotalAmount(double amount)
        +setShippingAddress(String address)
        +setDeliveryDate(DateTime date)
    }
    
    class OrderItem {
        +String id
        +String orderId
        +String productId
        +int quantity
        +double unitPrice
        +double subtotal
        +addOrderItem()
        +updateQuantity()
        +calculateSubTotal()
        +removeOrderItem()
        +getOrderItemStatus()
        +getId()
        +getOrderId()
        +getProductId()
        +getQuantity()
        +getUnitPrice()
        +getSubtotal()
        +setQuantity(int quantity)
        +setUnitPrice(double price)
        +setSubtotal(double subtotal)
    }
    
    %% Design Management
    class SavedDesign {
        +String id
        +String userId
        +String name
        +String description
        +String image
        +String roomType
        +String designStyle
        +DateTime createdAt
        +DateTime updatedAt
        +createDesign()
        +updateDesign()
        +deleteDesign()
        +saveDesign()
        +loadDesign()
        +exportDesign()
        +getId()
        +getUserId()
        +getName()
        +getDescription()
        +getRoomType()
        +getDesignStyle()
        +setName(String name)
        +setDescription(String description)
        +setImage(String image)
        +setRoomType(String roomType)
        +setDesignStyle(String style)
    }
    
    class PlacedFurniture {
        +String id
        +String designId
        +String furnitureId
        +double xPosition
        +double yPosition
        +double rotation
        +double scale
        +placeFurniture()
        +moveFurniture()
        +rotateFurniture()
        +scaleFurniture()
        +removeFurniture()
        +getId()
        +getDesignId()
        +getFurnitureId()
        +getXPosition()
        +getYPosition()
        +getRotation()
        +getScale()
        +setXPosition(double x)
        +setYPosition(double y)
        +setRotation(double rotation)
        +setScale(double scale)
    }
    
    class FurnitureItem {
        +String id
        +String name
        +String category
        +String image
        +String description
        +double width
        +double height
        +DateTime createdAt
        +addFurnitureItem()
        +updateFurnitureItem()
        +deleteFurnitureItem()
        +getFurnitureInfo()
        +searchFurniture()
        +getId()
        +getName()
        +getCategory()
        +getImage()
        +getDescription()
        +getWidth()
        +getHeight()
        +setName(String name)
        +setCategory(String category)
        +setImage(String image)
        +setDescription(String description)
        +setWidth(double width)
        +setHeight(double height)
    }
    
    class WallArea {
        +String id
        +String designId
        +double xPosition
        +double yPosition
        +double width
        +double height
        +String color
        +String textureId
        +createWallArea()
        +updateWallArea()
        +deleteWallArea()
        +changeColor()
        +applyTexture()
        +resizeWallArea()
        +getId()
        +getDesignId()
        +getXPosition()
        +getYPosition()
        +getWidth()
        +getHeight()
        +getColor()
        +getTextureId()
        +setXPosition(double x)
        +setYPosition(double y)
        +setWidth(double width)
        +setHeight(double height)
        +setColor(String color)
        +setTextureId(String textureId)
    }
    
    class WallTexture {
        +String id
        +String name
        +String image
        +String category
        +String description
        +addTexture()
        +updateTexture()
        +deleteTexture()
        +getTextureInfo()
        +searchTextures()
        +getId()
        +getName()
        +getImage()
        +getCategory()
        +getDescription()
        +setName(String name)
        +setImage(String image)
        +setCategory(String category)
        +setDescription(String description)
    }
    
    %% Budget Management
    class Budget {
        +String id
        +String userId
        +double totalBudget
        +double spentAmount
        +String currency
        +DateTime startDate
        +DateTime endDate
        +DateTime createdAt
        +DateTime updatedAt
        +createBudget()
        +updateBudget()
        +deleteBudget()
        +calculateSpentAmount()
        +getRemainingBudget()
        +addBudgetItem()
        +getId()
        +getUserId()
        +getTotalBudget()
        +getSpentAmount()
        +getCurrency()
        +getStartDate()
        +getEndDate()
        +setTotalBudget(double budget)
        +setSpentAmount(double spent)
        +setCurrency(String currency)
        +setStartDate(DateTime start)
        +setEndDate(DateTime end)
    }
    
    class BudgetItem {
        +String id
        +String budgetId
        +String category
        +double allocatedAmount
        +double spentAmount
        +String description
        +addBudgetItem()
        +updateBudgetItem()
        +deleteBudgetItem()
        +updateSpentAmount()
        +getBudgetItemStatus()
        +getId()
        +getBudgetId()
        +getCategory()
        +getAllocatedAmount()
        +getSpentAmount()
        +getDescription()
        +setCategory(String category)
        +setAllocatedAmount(double amount)
        +setSpentAmount(double spent)
        +setDescription(String description)
    }
    
    %% Chat/AI Messages
    class ChatMessage {
        +String id
        +String userId
        +String sender
        +String message
        +String messageType
        +DateTime timestamp
        +sendMessage()
        +receiveMessage()
        +deleteMessage()
        +getChatHistory()
        +markAsRead()
        +getId()
        +getUserId()
        +getSender()
        +getMessage()
        +getMessageType()
        +getTimestamp()
        +setMessage(String message)
        +setMessageType(String type)
        +setTimestamp(DateTime timestamp)
    }
    
    %% Purchase History
    class PurchaseHistory {
        +String id
        +String userId
        +String productId
        +int quantity
        +double totalPrice
        +DateTime purchaseDate
        +String status
        +addPurchaseRecord()
        +updatePurchaseStatus()
        +getPurchaseHistory()
        +getPurchaseDetails()
        +deletePurchaseRecord()
        +getId()
        +getUserId()
        +getProductId()
        +getQuantity()
        +getTotalPrice()
        +getPurchaseDate()
        +getStatus()
        +setQuantity(int quantity)
        +setTotalPrice(double price)
        +setPurchaseDate(DateTime date)
        +setStatus(String status)
    }
    
    %% Analytics
    class SalesAnalytics {
        +String id
        +String supplierId
        +double totalSales
        +int totalOrders
        +double averageRating
        +String period
        +DateTime date
        +generateAnalytics()
        +updateAnalytics()
        +getSalesReport()
        +getOrderStatistics()
        +getRatingAnalytics()
        +exportAnalytics()
        +getId()
        +getSupplierId()
        +getTotalSales()
        +getTotalOrders()
        +getAverageRating()
        +getPeriod()
        +getDate()
        +setTotalSales(double sales)
        +setTotalOrders(int orders)
        +setAverageRating(double rating)
        +setPeriod(String period)
        +setDate(DateTime date)
    }
    
    %% Notification System
    class Notification {
        +String id
        +String userId
        +String title
        +String message
        +String type
        +String status
        +DateTime createdAt
        +sendNotification()
        +markAsRead()
        +deleteNotification()
        +getUnreadNotifications()
        +getNotificationHistory()
        +getId()
        +getUserId()
        +getTitle()
        +getMessage()
        +getType()
        +getStatus()
        +getCreatedAt()
        +setTitle(String title)
        +setMessage(String message)
        +setType(String type)
        +setStatus(String status)
    }
    
    %% Receipt Management
    class Receipt {
        +String id
        +String orderId
        +String issuedBy
        +DateTime issueDate
        +String paymentMethod
        +double totalAmount
        +generateReceipt()
        +viewReceipt()
        +downloadReceipt()
        +printReceipt()
        +getId()
        +getOrderId()
        +getIssuedBy()
        +getIssueDate()
        +getPaymentMethod()
        +getTotalAmount()
        +setIssuedBy(String issuedBy)
        +setIssueDate(DateTime date)
        +setPaymentMethod(String method)
        +setTotalAmount(double amount)
    }
    
    %% Relationships with Labels
    User --> Order : places
    User --> SavedDesign : creates
    User --> Budget : has
    User --> ChatMessage : sends
    User --> PurchaseHistory : makes
    User --> Notification : receives
    
    Supplier --> Product : supplies
    Supplier --> Order : receives
    Supplier --> SalesAnalytics : generates
    
    Product --> OrderItem : included_in
    Product --> PurchaseHistory : purchased_in
    
    Order --> OrderItem : has
    Order --> Receipt : has
    
    SavedDesign --> PlacedFurniture : has
    SavedDesign --> WallArea : has
    
    FurnitureItem --> PlacedFurniture : placed_as
    
    WallTexture --> WallArea : applied_to
    
    Budget --> BudgetItem : has

## 📋 **Implementation Notes for Draw.io**

### **🎯 Cardinality Information to Add:**

#### **1. ✅ One-to-Many Relationships (1 to *):**
- **User → Order**: 1 to many
- **User → SavedDesign**: 1 to many  
- **User → Budget**: 1 to many
- **User → ChatMessage**: 1 to many
- **User → PurchaseHistory**: 1 to many
- **User → Notification**: 1 to many
- **Supplier → Product**: 1 to many
- **Supplier → Order**: 1 to many
- **Supplier → SalesAnalytics**: 1 to many
- **Product → OrderItem**: 1 to many
- **Product → PurchaseHistory**: 1 to many
- **Order → OrderItem**: 1 to many
- **SavedDesign → PlacedFurniture**: 1 to many
- **SavedDesign → WallArea**: 1 to many
- **FurnitureItem → PlacedFurniture**: 1 to many
- **WallTexture → WallArea**: 1 to many
- **Budget → BudgetItem**: 1 to many

#### **2. ✅ One-to-One Relationships (1 to 1):**
- **Order → Receipt**: 1 to 1

#### **3. ✅ Reverse Relationships (Child to Parent):**
- **Order → User**: many to 1
- **SavedDesign → User**: many to 1
- **Budget → User**: many to 1
- **ChatMessage → User**: many to 1
- **PurchaseHistory → User**: many to 1
- **Notification → User**: many to 1
- **Product → Supplier**: many to 1
- **Order → Supplier**: many to 1
- **SalesAnalytics → Supplier**: many to 1
- **OrderItem → Product**: many to 1
- **PurchaseHistory → Product**: many to 1
- **OrderItem → Order**: many to 1
- **Receipt → Order**: 1 to 1
- **PlacedFurniture → SavedDesign**: many to 1
- **WallArea → SavedDesign**: many to 1
- **PlacedFurniture → FurnitureItem**: many to 1
- **WallArea → WallTexture**: many to 1
- **BudgetItem → Budget**: many to 1

### **🏗️ Composition vs Aggregation:**

#### **🔗 Composition (Strong Ownership - Diamond with filled arrow):**
- **SavedDesign → PlacedFurniture**: Composition (furniture is part of the design)
- **SavedDesign → WallArea**: Composition (wall areas are part of the design)
- **Order → OrderItem**: Composition (items are part of the order)
- **Budget → BudgetItem**: Composition (budget items are part of the budget)

#### **🔗 Aggregation (Weak Ownership - Diamond with empty arrow):**
- **User → Order**: Aggregation (user can exist without orders)
- **User → SavedDesign**: Aggregation (user can exist without designs)
- **User → Budget**: Aggregation (user can exist without budget)
- **Supplier → Product**: Aggregation (supplier can exist without products)
- **Product → OrderItem**: Aggregation (product can exist independently)
- **FurnitureItem → PlacedFurniture**: Aggregation (furniture item can exist independently)
- **WallTexture → WallArea**: Aggregation (texture can exist independently)

### **📊 How to Implement in Draw.io:**

#### **1. ✅ Cardinality Labels:**
- Add text labels: `1` and `*` on relationship lines
- Use `1..*` for "one or many"
- Use `0..1` for "zero or one"

#### **2. ✅ Composition (Filled Diamond):**
- Use filled diamond arrowhead
- Indicates "part-of" relationship
- Child cannot exist without parent

#### **3. ✅ Aggregation (Empty Diamond):**
- Use empty diamond arrowhead  
- Indicates "has-a" relationship
- Child can exist independently

#### **4. ✅ Association (Simple Arrow):**
- Use simple arrow for basic associations
- No ownership implied

### **🎨 Visual Guidelines:**
- **Composition**: Filled diamond + solid line
- **Aggregation**: Empty diamond + solid line
- **Association**: Simple arrow
- **Cardinality**: Text labels (1, *, 1..*, 0..1)