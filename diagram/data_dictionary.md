# 📚 Data Dictionary - Interior Design Recommendation System

## 📊 Overview
This data dictionary provides detailed documentation for all entities, attributes, data types, and descriptions used in the Interior Design Recommendation System database.

---

## 🗂️ Table 1: User Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `userId` | `String (PK)` | Unique identifier for the user |
| `name` | `String` | Full name of the user |
| `email` | `String` | Email address of the user |
| `password` | `String` | Encrypted password of the user |
| `phone` | `String` | Contact phone number of the user |
| `address` | `String` | Physical address of the user |
| `role` | `String` | Role of the user (e.g., "Homeowner", "Supplier") |
| `profilePicture` | `String` | Path to the user's profile picture |
| `createdAt` | `DateTime` | Date and time the account was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 2: Supplier Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `supplierId` | `String (PK)` | Unique identifier for the supplier |
| `name` | `String` | Business name of the supplier |
| `email` | `String` | Email address of the supplier |
| `phone` | `String` | Contact phone number of the supplier |
| `address` | `String` | Business address of the supplier |
| `businessLicense` | `String` | Business license number |
| `description` | `String` | Description of the supplier's business |
| `createdAt` | `DateTime` | Date and time the supplier account was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 3: Product Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `productId` | `String (PK)` | Unique identifier for the product |
| `name` | `String` | Name of the product |
| `description` | `String` | Detailed description of the product |
| `price` | `int` | Price of the product in RM |
| `stock` | `int` | Available quantity in stock |
| `image` | `String` | Path to the product image |
| `category` | `String` | Product category (e.g., "Furniture", "Lighting") |
| `designStyle` | `String` | Design style (e.g., "Modern", "Industrial") |
| `supplierId` | `String (FK)` | Foreign key referencing Supplier.supplierId |
| `createdAt` | `DateTime` | Date and time the product was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 4: Order Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `orderId` | `String (PK)` | Unique identifier for the order |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `supplierId` | `String (FK)` | Foreign key referencing Supplier.supplierId |
| `totalAmount` | `double` | Total amount of the order |
| `status` | `String` | Order status (e.g., "Pending", "Shipped", "Delivered") |
| `shippingAddress` | `String` | Delivery address for the order |
| `orderDate` | `DateTime` | Date and time the order was placed |
| `deliveryDate` | `DateTime` | Expected or actual delivery date |
| `createdAt` | `DateTime` | Date and time the order was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 5: OrderItem Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `orderItemId` | `String (PK)` | Unique identifier for the order item |
| `orderId` | `String (FK)` | Foreign key referencing Order.orderId |
| `productId` | `String (FK)` | Foreign key referencing Product.productId |
| `quantity` | `int` | Quantity of the product ordered |
| `unitPrice` | `double` | Price per unit at the time of order |
| `subtotal` | `double` | Total price for this item (quantity × unitPrice) |

---

## 🗂️ Table 6: SavedDesign Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `designId` | `String (PK)` | Unique identifier for the saved design |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `name` | `String` | Name of the saved design |
| `description` | `String` | Description of the design |
| `image` | `String` | Path to the design preview image |
| `roomType` | `String` | Type of room (e.g., "Living Room", "Bedroom") |
| `designStyle` | `String` | Design style of the room |
| `createdAt` | `DateTime` | Date and time the design was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 7: PlacedFurniture Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `placedFurnitureId` | `String (PK)` | Unique identifier for the placed furniture |
| `designId` | `String (FK)` | Foreign key referencing SavedDesign.designId |
| `furnitureId` | `String (FK)` | Foreign key referencing FurnitureItem.furnitureId |
| `xPosition` | `double` | X-coordinate position on the canvas |
| `yPosition` | `double` | Y-coordinate position on the canvas |
| `rotation` | `double` | Rotation angle of the furniture |
| `scale` | `double` | Scale/size of the furniture |

---

## 🗂️ Table 8: FurnitureItem Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `furnitureId` | `String (PK)` | Unique identifier for the furniture item |
| `name` | `String` | Name of the furniture item |
| `category` | `String` | Category of furniture (e.g., "Chair", "Table") |
| `image` | `String` | Path to the furniture image |
| `description` | `String` | Description of the furniture item |
| `width` | `double` | Width of the furniture item |
| `height` | `double` | Height of the furniture item |
| `createdAt` | `DateTime` | Date and time the furniture item was created |

---

## 🗂️ Table 9: WallArea Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `wallAreaId` | `String (PK)` | Unique identifier for the wall area |
| `designId` | `String (FK)` | Foreign key referencing SavedDesign.designId |
| `xPosition` | `double` | X-coordinate position on the canvas |
| `yPosition` | `double` | Y-coordinate position on the canvas |
| `width` | `double` | Width of the wall area |
| `height` | `double` | Height of the wall area |
| `color` | `String` | Color applied to the wall area |
| `textureId` | `String (FK)` | Foreign key referencing WallTexture.textureId |

---

## 🗂️ Table 10: WallTexture Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `textureId` | `String (PK)` | Unique identifier for the wall texture |
| `name` | `String` | Name of the texture |
| `image` | `String` | Path to the texture image |
| `category` | `String` | Category of texture (e.g., "Wood", "Stone") |
| `description` | `String` | Description of the texture |

---

## 🗂️ Table 11: Budget Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `budgetId` | `String (PK)` | Unique identifier for the budget |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `totalBudget` | `double` | Total allocated budget amount |
| `spentAmount` | `double` | Amount already spent |
| `currency` | `String` | Currency type (e.g., "RM") |
| `startDate` | `DateTime` | Start date of the budget period |
| `endDate` | `DateTime` | End date of the budget period |
| `createdAt` | `DateTime` | Date and time the budget was created |
| `updatedAt` | `DateTime` | Last update timestamp |

---

## 🗂️ Table 12: BudgetItem Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `budgetItemId` | `String (PK)` | Unique identifier for the budget item |
| `budgetId` | `String (FK)` | Foreign key referencing Budget.budgetId |
| `category` | `String` | Budget category (e.g., "Furniture", "Lighting") |
| `allocatedAmount` | `double` | Amount allocated for this category |
| `spentAmount` | `double` | Amount spent in this category |
| `description` | `String` | Description of the budget item |

---

## 🗂️ Table 13: ChatMessage Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `messageId` | `String (PK)` | Unique identifier for the chat message |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `sender` | `String` | Sender of the message (e.g., "User", "AI") |
| `message` | `String` | Content of the message |
| `messageType` | `String` | Type of message (e.g., "Text", "Recommendation") |
| `timestamp` | `DateTime` | Date and time the message was sent |

---

## 🗂️ Table 14: PurchaseHistory Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `purchaseId` | `String (PK)` | Unique identifier for the purchase record |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `productId` | `String (FK)` | Foreign key referencing Product.productId |
| `quantity` | `int` | Quantity purchased |
| `totalPrice` | `double` | Total price of the purchase |
| `purchaseDate` | `DateTime` | Date and time of the purchase |
| `status` | `String` | Status of the purchase (e.g., "Completed", "Cancelled") |

---

## 🗂️ Table 15: SalesAnalytics Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `analyticsId` | `String (PK)` | Unique identifier for the sales analytics |
| `supplierId` | `String (FK)` | Foreign key referencing Supplier.supplierId |
| `totalSales` | `double` | Total sales amount |
| `totalOrders` | `int` | Total number of orders |
| `averageRating` | `double` | Average customer rating |
| `period` | `String` | Time period (e.g., "Daily", "Monthly", "Yearly") |
| `date` | `DateTime` | Date of the analytics record |

---

## 🗂️ Table 16: Notification Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `notificationId` | `String (PK)` | Unique identifier for the notification |
| `userId` | `String (FK)` | Foreign key referencing User.userId |
| `title` | `String` | Title of the notification |
| `message` | `String` | Content of the notification |
| `type` | `String` | Type of notification (e.g., "Order", "System") |
| `status` | `String` | Status of the notification (e.g., "Read", "Unread") |
| `createdAt` | `DateTime` | Date and time the notification was created |

---

## 🗂️ Table 17: Receipt Collection

| **Attributes** | **Data Type** | **Description** |
|----------------|---------------|-----------------|
| `receiptId` | `String (PK)` | Unique identifier for the receipt |
| `orderId` | `String (FK)` | Foreign key referencing Order.orderId |
| `issuedBy` | `String` | Name of the person who issued the receipt |
| `issueDate` | `DateTime` | Date and time the receipt was issued |
| `paymentMethod` | `String` | Method of payment used |
| `totalAmount` | `double` | Total amount on the receipt |

---

## 🔗 **Relationship Summary**

### **One-to-Many Relationships:**
- **User** → **Order** (1 user can place many orders)
- **User** → **SavedDesign** (1 user can create many designs)
- **User** → **Budget** (1 user can have many budgets)
- **User** → **ChatMessage** (1 user can send many messages)
- **User** → **PurchaseHistory** (1 user can make many purchases)
- **User** → **Notification** (1 user can receive many notifications)
- **Supplier** → **Product** (1 supplier can supply many products)
- **Supplier** → **Order** (1 supplier can receive many orders)
- **Supplier** → **SalesAnalytics** (1 supplier can have many analytics records)
- **Product** → **OrderItem** (1 product can be in many order items)
- **Product** → **PurchaseHistory** (1 product can have many purchase records)
- **Order** → **OrderItem** (1 order can have many items)
- **SavedDesign** → **PlacedFurniture** (1 design can have many furniture pieces)
- **SavedDesign** → **WallArea** (1 design can have many wall areas)
- **FurnitureItem** → **PlacedFurniture** (1 furniture item can be placed many times)
- **WallTexture** → **WallArea** (1 texture can be applied to many wall areas)
- **Budget** → **BudgetItem** (1 budget can have many budget items)

### **One-to-One Relationships:**
- **Order** → **Receipt** (1 order has exactly 1 receipt)

---

## 📋 **Data Type Guidelines**

### **Primary Keys (PK):**
- All entities use `String` type for primary keys
- Recommended: UUID format for uniqueness

### **Foreign Keys (FK):**
- All foreign keys use `String` type
- References the primary key of the related entity

### **Numeric Types:**
- `int`: Used for quantities, stock, ratings
- `double`: Used for prices, amounts, positions, dimensions

### **Date/Time Types:**
- `DateTime`: Used for timestamps, dates, creation/update times

### **String Types:**
- Used for names, descriptions, paths, status values
- No specific length constraints defined (should be set based on requirements)

---

This data dictionary provides complete documentation for all entities in the Interior Design Recommendation System database! 🎉 