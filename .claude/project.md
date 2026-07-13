# Interior Design Recommendation System — Project Reference

## Overview

A **Flutter-based Android mobile application** that provides AI-powered interior design recommendations. The app serves two user roles:

| Role | Purpose |
|------|---------|
| **Homeowner / End User** | Get AI design suggestions, preview changes via AR, browse & buy materials from marketplace, track budgets |
| **Supplier** | List and manage products, handle orders, view sales analytics |

The project is a **Final Year Project (FYP)** by Lim Yee Hang (24PMR10425), Bachelor of Software Engineering (Honours), TAR UMT Penang, supervised by Ms Tan Kee Oon. Academic Year 2025/26.

---

## Current Codebase State — CRITICAL

The existing codebase is **not reusable** and needs a **full redesign and restructure**:

1. **Monolithic dump**: `lib/main.dart` is ~9,437 lines (327 KB) containing **all** app code — auth, theming, every screen, every widget, providers, and business logic — all inline in one file.
2. **Empty placeholder files**: The feature screen files under `lib/screens/homeowner/` and `lib/screens/supplier/` are all empty (0 lines). Only the report screens (`report_screens.dart` at 1,299 lines, `budget_report_screen.dart` at 434 lines, etc.) have actual code extracted from `main.dart`. The actual feature implementations are all still in `main.dart`.
3. **No separation of concerns**: Models, services, providers, and UI are mixed together. `AuthProvider` is defined inline in `main.dart` instead of in a separate file.
4. **Hardcoded data**: Designs, products, and recommendations are hardcoded — no real backend integration. Firebase is listed as the database but not actually integrated.
5. **Plain/basic UI**: The current design is described as "too plain" — it uses a soft brown/teal color scheme with Material 3 and Google Fonts (Poppins), but the overall UX is basic.
6. **Messy directory structure**: No clear separation between features, no reusable widget library, no routing system.

### Current Directory Structure (messy)

```
interior_design_recommendation/
├── lib/
│   ├── main.dart              ← 9,437 lines, ALL code dumped here
│   ├── config/
│   │   ├── app_config.dart
│   │   └── local_config.dart
│   ├── models/
│   │   └── product.dart
│   ├── providers/
│   │   ├── analytics_provider.dart
│   │   └── marketplace_provider.dart
│   ├── screens/
│   │   ├── auth_screen.dart                  ← empty (0 lines)
│   │   ├── budget_report_screen.dart          ← 434 lines
│   │   ├── report_screens.dart                ← 1,299 lines
│   │   ├── sales_analytics_report_screen.dart ← 549 lines
│   │   ├── supplier_widgets.dart              ← empty (0 lines)
│   │   ├── user_design_report_screen.dart     ← 527 lines
│   │   ├── homeowner/
│   │   │   ├── ai_recommendation_screen.dart    ← empty
│   │   │   ├── budget_planner_screen.dart       ← empty
│   │   │   ├── dashboard_screen.dart            ← empty
│   │   │   ├── homeowner_main_screen.dart       ← empty
│   │   │   ├── marketplace_screen.dart          ← empty
│   │   │   ├── profile_screen.dart              ← empty
│   │   │   └── saved_designs_screen.dart        ← empty
│   │   └── supplier/
│   │       ├── dashboard_screen.dart            ← empty
│   │       ├── order_management_screen.dart     ← empty
│   │       ├── product_management_screen.dart   ← empty
│   │       ├── profile_screen.dart              ← empty
│   │       └── sales_analytics_screen.dart      ← empty
│   └── services/
│       ├── gemini_service.dart
│       └── marketplace_service.dart
├── assets/
│   ├── data/products.json
│   └── images/                  ← ~60 stock images for furniture/textures/rooms
├── server/
│   ├── bin/server.dart
│   └── data/products.json
├── diagram/                     ← System design diagrams (Mermaid format)
├── test/
├── android/
├── build/
└── pubspec.yaml
```

---

## Target Architecture (To Be Built)

### Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter (Dart), cross-platform for Android + iOS |
| **Backend** | Node.js (existing `server/` placeholder) |
| **Database** | Firebase (Firestore for real-time data; Auth for user management) |
| **AI** | Google Gemini API (currently `gemini-2.0-flash`); ML Kit for image labeling |
| **AR** | Camera plugin + ARCore/ARKit (via Flutter plugin, TBD) |
| **State Management** | Provider (current), consider Riverpod or Bloc for redesign |

### Dependencies (from pubspec.yaml)

- `provider: ^6.1.5` — state management
- `google_fonts: ^6.1.0` — typography
- `google_generative_ai: ^0.4.7` — Gemini AI integration
- `http: ^1.2.0` — HTTP client
- `camera: ^0.10.5+5` — camera for AR
- `google_mlkit_image_labeling: ^0.11.0` — on-device image recognition

### Proposed New Directory Structure

```
lib/
├── main.dart                          ← thin, app entry + DI setup only
├── app.dart                           ← MaterialApp, theme, router config
├── core/
│   ├── theme/
│   │   ├── app_theme.dart             ← light/dark themes
│   │   ├── app_colors.dart
│   │   └── app_typography.dart
│   ├── routing/
│   │   └── app_router.dart            ← GoRouter or Navigator 2.0 routes
│   ├── constants/
│   │   └── app_constants.dart
│   └── utils/
│       ├── validators.dart
│       └── extensions.dart
├── features/
│   ├── auth/
│   │   ├── data/                      ← repositories, data sources
│   │   ├── domain/                    ← models, use cases
│   │   └── presentation/             ← screens, widgets, providers
│   ├── dashboard/
│   │   └── ...
│   ├── ar_visualization/
│   │   └── ...
│   ├── ai_recommendation/
│   │   └── ...
│   ├── marketplace/
│   │   └── ...
│   ├── budget_planner/
│   │   └── ...
│   ├── supplier/
│   │   ├── inventory/
│   │   ├── orders/
│   │   ├── analytics/
│   │   └── ...
│   └── settings/
│       └── ...
├── shared/
│   ├── widgets/                       ← reusable UI components
│   │   ├── buttons/
│   │   ├── cards/
│   │   ├── inputs/
│   │   └── layout/
│   └── services/                      ← shared backend services
│       ├── api_client.dart
│       ├── firebase_service.dart
│       ├── gemini_service.dart        ← move from current location
│       └── storage_service.dart
└── l10n/                              ← localization (future)
```

---

## System Modules & Features

### 1. Account & Profile Management
- Email/password login with optional **2FA (face recognition)**
- Role-based access: `homeowner` vs `supplier`
- Profile editing, password change, notification preferences
- Firebase Authentication target

### 2. AR Visualization Module
- Real-time AR preview of design changes (wall colors, flooring, furniture)
- Room scanning via camera
- Furniture placement with position/rotation/scale
- Lighting adaptation
- Save/load designs
- **Technology**: Camera plugin + AR framework (ARKit/ARCore)

### 3. AI Recommendation Engine
- **Room analysis**: Scan room → identify existing materials, colors, style
- **Style matching**: Recommends compatible designs (Modern, Scandinavian, Industrial, Bohemian, Classic, Minimalist)
- **Budget-aware suggestions**: Suggests cheaper alternatives if selections exceed budget
- **Material recommendation**: Considers room conditions (e.g., water-resistant for humid areas)
- **Powered by**: Google Gemini API + ML Kit image labeling
- **Learning**: Refines recommendations from user feedback

### 4. Marketplace Module
- Browse, filter, search products (furniture, materials, decor)
- Categories: Furniture, Lighting, Flooring, Wall, Decor, Textiles
- **Eco-friendly filter**: Recycled materials, sustainable certifications, low-VOC
- **Live stock**: Real-time inventory from supplier
- Shopping cart, order placement, payment integration
- **Delivery tracking** for buyers

### 5. Budget Planner
- Set total renovation budget
- Track spent amount across selected items
- **Alert** when approaching/exceeding budget
- Auto-suggest cheaper alternatives
- Compare prices across suppliers
- Generate cost estimates

### 6. Dashboard (per role)

**Homeowner Dashboard**: Saved designs, purchase history, budget status, AI recommendations, promotions

**Supplier Dashboard**: Product views, sales volume, order management, analytics, low-stock alerts

### 7. Virtual Staging (Real Estate)
- Upload empty room photos
- Digitally furnish with popular styles
- Shareable link for potential buyers
- Multiple style options (Modern, Rustic, Minimal)

---

## Data Model (from ERD)

Key entities:

| Entity | Key Fields |
|--------|-----------|
| **User** | id, name, email, password, phone, address, role (homeowner/supplier), profilePicture |
| **Supplier** | id, name, email, phone, address, businessLicense, description |
| **Product** | id, name, description, price, stock, image, category, designStyle, supplierId (FK) |
| **Order** | id, userId (FK), supplierId (FK), totalAmount, status, shippingAddress |
| **OrderItem** | id, orderId (FK), productId (FK), quantity, unitPrice, subtotal |
| **SavedDesign** | id, userId (FK), name, description, image, roomType, designStyle |
| **PlacedFurniture** | id, designId (FK), furnitureId (FK), xPosition, yPosition, rotation, scale |
| **FurnitureItem** | id, name, category, image, description, width, height |
| **WallArea** | id, designId (FK), xPosition, yPosition, width, height, color, textureId (FK) |
| **WallTexture** | id, name, image, category, description |
| **Budget** | id, userId (FK), totalBudget, spentAmount, currency |
| **BudgetItem** | id, budgetId (FK), category, allocatedAmount, spentAmount |
| **ChatMessage** | id, userId (FK), sender, message, messageType |
| **Notification** | id, userId (FK), title, message, type, status |
| **Receipt** | id, orderId (FK), issuedBy, paymentMethod, totalAmount |
| **SalesAnalytics** | id, supplierId (FK), totalSales, totalOrders, averageRating |
| **PurchaseHistory** | id, userId (FK), productId (FK), quantity, totalPrice, status |

### Key Relationships
- User 1→* Order, SavedDesign, Budget, ChatMessage, Notification
- Supplier 1→* Product, Order, SalesAnalytics
- Order 1→* OrderItem; Order 1→1 Receipt
- SavedDesign 1→* PlacedFurniture, WallArea
- Budget 1→* BudgetItem

---

## Design Diagrams (in `diagram/` folder)

All diagrams are in Mermaid format and can be imported to draw.io:

| File | Content |
|------|---------|
| `software_architecture_diagrams.md` | Package diagram, deployment diagram, component diagram — full 3-layer architecture (SystemUI → SystemCtrl → Database) |
| `erd_diagram.md` | Entity-relationship diagram with 17 entities, cardinalities, and foreign keys |
| `class_diagram.md` | UML class diagram with methods, composition vs aggregation relationships |
| `sequence_diagrams.md` | Sequence diagrams for account management, AI recommendation, AR visualization, marketplace, dashboard, budget |
| `account_management_sequences.md` / `_states.md` | Detailed flow and state diagrams for auth module |
| `ai_recommendation_sequences.md` / `_states.md` | AI recommendation flow and state transitions |
| `ar_visualization_sequences.md` / `_states.md` | AR visualization flow and state transitions |
| `budget_calculation_sequences.md` / `_states.md` | Budget calculation flow |
| `marketplace_sequences.md` / `_states.md` | Marketplace/e-commerce flow |
| `dashboard_sequences.md` / `_states.md` | Dashboard data flow |
| `data_dictionary.md` | Complete data dictionary with all table attributes, types, and descriptions |
| `algorithm_design.md` | AI recommendation algorithm design |
| `security_design.md` | Security architecture |

---

## Development Methodology

**Evolutionary Prototyping** — Build early working prototypes, evaluate with stakeholders, refine iteratively.

Phases: Requirements → Analysis → Prototype Development → Client Evaluation → Refinement → (loop) → Final Design → Coding → Integration Testing → Maintenance

---

## Key Design Intent (for the redesign)

1. **Clean architecture**: Feature-based folder structure with separation of data/domain/presentation layers
2. **Reusable widget library**: Shared components (buttons, cards, inputs) under `shared/widgets/`
3. **Proper routing**: GoRouter or Navigator 2.0 with named routes instead of inline navigation
4. **Theme system**: Centralized light/dark theme with design tokens, not scattered `Color(0xFF...)` values
5. **Firebase integration**: Replace hardcoded data with Firestore real-time data + Firebase Auth
6. **State management**: Move from scattered Providers to a structured approach (Riverpod or Bloc)
7. **Backend API**: The `server/` directory contains a Dart shelf server stub — this should be the Node.js backend per the tech stack
8. **Accessibility & localization**: Support multiple languages (at minimum EN + BM) for the Malaysian market

---

## Project Constraints & Notes

- **Solo developer project** (FYP by Lim Yee Hang — acting as UI/UX designer, system analyst, developer, tester, and project manager)
- **Target platform**: Android primarily, with iOS compatibility via Flutter
- **Malaysian market**: MYR currency, local suppliers, Malaysian real estate context
- **No existing backend**: Firebase is planned but not integrated; the `server/` folder is a placeholder
- **Assets**: ~60 stock images for room types, furniture, textures, and wall materials — likely placeholders
