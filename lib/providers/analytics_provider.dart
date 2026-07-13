import 'package:flutter/material.dart';

// Analytics and Report Data Provider
class AnalyticsProvider extends ChangeNotifier {
  // User Design Report Data
  Map<String, dynamic> getUserDesignReport() {
    return {
      'totalDesigns': 15,
      'completedDesigns': 12,
      'inProgressDesigns': 3,
      'favoriteStyles': ['Modern', 'Industrial', 'Minimalist'],
      'roomTypes': {
        'Living Room': 5,
        'Bedroom': 4,
        'Kitchen': 3,
        'Bathroom': 2,
        'Dining Room': 1,
      },
      'designTrends': {
        'Modern': 35,
        'Industrial': 25,
        'Minimalist': 20,
        'Scandinavian': 15,
        'Bohemian': 5,
      },
      'monthlyDesigns': {
        'Jan': 2,
        'Feb': 3,
        'Mar': 4,
        'Apr': 3,
        'May': 2,
        'Jun': 1,
      },
      'colorPreferences': {
        'Neutral': 40,
        'Blue': 25,
        'Green': 20,
        'Warm': 15,
      },
      'furnitureCategories': {
        'Sofa': 8,
        'Dining Table': 6,
        'Bed': 5,
        'Storage': 4,
        'Lighting': 3,
      },
      'designCompletionRate': 80.0,
      'averageDesignTime': 3.5, // days
      'popularColorSchemes': {
        'Neutral & White': 30,
        'Blue & Gray': 25,
        'Warm Earth Tones': 20,
        'Green & Natural': 15,
        'Bold & Contrast': 10,
      },
      'designSatisfaction': 4.2,
      'aiRecommendationAccuracy': 85.0,
    };
  }

  // User Budget Plan Report Data
  Map<String, dynamic> getUserBudgetReport() {
    return {
      'totalBudget': 25000,
      'spentAmount': 18750,
      'remainingBudget': 6250,
      'budgetUtilization': 75.0,
      'budgetCategories': {
        'Furniture': 12000,
        'Lighting': 3500,
        'Decor': 2500,
        'Storage': 750,
      },
      'monthlySpending': {
        'Jan': 3000,
        'Feb': 4500,
        'Mar': 3800,
        'Apr': 4200,
        'May': 3250,
      },
      'budgetAlerts': [
        {'category': 'Furniture', 'message': '80% of budget used', 'severity': 'warning'},
        {'category': 'Lighting', 'message': 'Budget exceeded by 15%', 'severity': 'critical'},
      ],
      'costSavings': 6250,
      'budgetEfficiency': 85.0,
      'spendingTrends': {
        'Furniture': 48.0,
        'Lighting': 14.0,
        'Decor': 10.0,
        'Storage': 3.0,
        'Other': 25.0,
      },
      'upcomingExpenses': [
        {'item': 'Dining Table', 'estimatedCost': 2500, 'priority': 'high'},
        {'item': 'Wall Art', 'estimatedCost': 800, 'priority': 'medium'},
        {'item': 'Rug', 'estimatedCost': 1200, 'priority': 'medium'},
      ],
    };
  }

  // Supplier Sales Report Data
  Map<String, dynamic> getSupplierSalesReport() {
    return {
      'totalSales': 125000,
      'monthlySales': 18500,
      'totalOrders': 156,
      'averageOrderValue': 801.28,
      'salesGrowth': 23.5,
      'profitMargin': 35.0,
      'customerRetentionRate': 78.0,
      'topProducts': [
        {'name': 'Modern Sofa Set', 'sales': 25000, 'units': 12},
        {'name': 'Industrial Dining Table', 'sales': 18000, 'units': 8},
        {'name': 'Minimalist Bed Frame', 'sales': 15000, 'units': 10},
        {'name': 'LED Pendant Lights', 'sales': 12000, 'units': 24},
        {'name': 'Storage Cabinet', 'sales': 9000, 'units': 6},
      ],
      'salesByCategory': {
        'Furniture': 65000,
        'Lighting': 25000,
        'Decor': 20000,
        'Storage': 15000,
      },
      'monthlySalesData': {
        'Jan': 12000,
        'Feb': 15000,
        'Mar': 18000,
        'Apr': 22000,
        'May': 25000,
        'Jun': 23000,
      },
      'customerMetrics': {
        'newCustomers': 45,
        'returningCustomers': 111,
        'averageCustomerRating': 4.6,
        'customerSatisfaction': 92.0,
      },
      'performanceMetrics': {
        'conversionRate': 15.5,
        'averageResponseTime': 2.3, // hours
        'fulfillmentRate': 98.5,
        'returnRate': 2.1,
      },
    };
  }

  // Comprehensive Analytics Report
  Map<String, dynamic> getComprehensiveAnalyticsReport() {
    return {
      'userEngagement': {
        'activeUsers': 1250,
        'dailyActiveUsers': 180,
        'sessionDuration': 12.5, // minutes
        'featureUsage': {
          'AR_Scanning': 65,
          'AI_Recommendations': 80,
          'Marketplace': 45,
          'Budget_Tracking': 35,
        },
      },
      'performanceMetrics': {
        'appLoadTime': 2.3, // seconds
        'arRenderingFps': 60,
        'aiResponseTime': 1.8, // seconds
        'searchResponseTime': 0.8, // seconds
      },
      'businessMetrics': {
        'totalRevenue': 450000,
        'monthlyGrowth': 12.5,
        'customerAcquisitionCost': 45,
        'lifetimeValue': 850,
        'churnRate': 8.5,
      },
      'designAnalytics': {
        'popularStyles': {
          'Modern': 35,
          'Minimalist': 25,
          'Scandinavian': 20,
          'Industrial': 15,
          'Bohemian': 5,
        },
        'roomPreferences': {
          'Living Room': 40,
          'Bedroom': 30,
          'Kitchen': 15,
          'Bathroom': 10,
          'Dining Room': 5,
        },
        'colorTrends': {
          'Neutral': 45,
          'Blue': 25,
          'Green': 20,
          'Warm': 10,
        },
      },
      'marketplaceAnalytics': {
        'totalProducts': 1250,
        'activeSuppliers': 45,
        'averageRating': 4.3,
        'conversionRate': 12.5,
        'topCategories': {
          'Furniture': 40,
          'Lighting': 25,
          'Decor': 20,
          'Storage': 15,
        },
      },
    };
  }

  // Real-time Dashboard Data
  Map<String, dynamic> getRealTimeDashboardData() {
    return {
      'currentUsers': 156,
      'activeSessions': 89,
      'recentOrders': 12,
      'pendingDesigns': 8,
      'systemStatus': 'Healthy',
      'performanceAlerts': [],
      'recentActivities': [
        {'type': 'design_created', 'user': 'John Doe', 'time': '2 min ago'},
        {'type': 'order_placed', 'user': 'Jane Smith', 'time': '5 min ago'},
        {'type': 'ar_scan', 'user': 'Mike Johnson', 'time': '8 min ago'},
        {'type': 'ai_recommendation', 'user': 'Sarah Wilson', 'time': '12 min ago'},
      ],
    };
  }
} 