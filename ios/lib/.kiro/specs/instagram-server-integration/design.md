# Design Document: Instagram Page Creation Server Integration

## Overview

This design addresses the critical Instagram page creation issue where the system currently uses local database product IDs instead of server-based product IDs, causing product ID mismatches and submission failures. The solution implements a server-first approach for Instagram page creation, mirroring the successful marketplace pattern to ensure consistent product identification and reliable URL generation.

The core architectural change shifts Instagram page creation from local database dependency to server-based product fetching, ensuring that all product references use server-side IDs throughout the Instagram creation workflow. This eliminates the ID mismatch problem and provides consistent product data across the application.

## Architecture

### Current Architecture (Problematic)
```
Instagram Page Creation Flow:
├── InstagramProductSelectionScreen
│   ├── Loads from Local Database (ProductDatabaseService)
│   ├── Merges with Server Data (inconsistent IDs)
│   └── Uses Local Product IDs for Selection
├── Product Selection Process
│   ├── References Local Database IDs
│   └── Causes ID Mismatch on Server Submission
└── Instagram Page Publishing
    ├── Submits Local Product IDs to Server
    ├── Server Cannot Resolve Local IDs
    └── Results in Submission Failures
```

### New Architecture (Server-First)
```
Instagram Page Creation Flow:
├── InstagramProductSelectionScreen
│   ├── Fetches from Server API (ProductService.getProducts)
│   ├── Uses Marketplace Pattern for Consistency
│   └── References Server Product IDs Exclusively
├── Product Selection Process
│   ├── Validates Server Product ID Availability
│   ├── Excludes Products Without Server IDs
│   └── Stores Server Product ID References
└── Instagram Page Publishing
    ├── Submits Server Product IDs to Server
    ├── Server Resolves IDs Successfully
    └── Generates Correct Product URLs
```

### Integration Points

1. **ProductService Integration**: Leverage existing server-based product fetching
2. **Marketplace Pattern Adoption**: Reuse proven server-first data loading
3. **ID Validation Layer**: Ensure server ID availability before operations
4. **URL Generation Service**: Centralized server-based URL construction
5. **Error Handling Framework**: Consistent error recovery across components

## Components and Interfaces

### 1. Enhanced InstagramProductSelectionScreen

The core component requiring modification to implement server-first product loading:

```dart
class InstagramProductSelectionScreen extends StatefulWidget {
  const InstagramProductSelectionScreen({super.key});
}

class _InstagramProductSelectionScreenState extends State<InstagramProductSelectionScreen> {
  List<Product> _serverProducts = [];
  List<Product> _filteredProducts = [];
  Set<int> _selectedServerProductIds = {};
  bool _loading = true;
  String? _errorMessage;
  int _excludedProductsCount = 0;
}
```

**Key Changes:**
- Remove local database dependency for product loading
- Implement marketplace-style server-based product fetching
- Add server ID validation and exclusion logic
- Enhance error handling for network failures
- Add product synchronization triggers

### 2. ServerProductService

A specialized service layer for Instagram-specific server product operations:

```dart
class ServerProductService {
  /// Fetch products for Instagram creation using server-only approach
  static Future<ServerProductResult> getProductsForInstagram({
    String status = 'publish',
    int? limit,
    int? offset,
  }) async;
  
  /// Validate that products have server IDs
  static List<Product> validateServerIds(List<Product> products);
  
  /// Update products for Instagram using server IDs
  static Future<Map<String, dynamic>> updateProductsForInstagram({
    required List<int> serverProductIds,
  }) async;
  
  /// Generate server-based product URLs
  static String generateProductUrl(int serverProductId);
  
  /// Trigger product synchronization
  static Future<SyncResult> syncProductsToServer() async;
}

class ServerProductResult {
  final List<Product> products;
  final List<Product> excludedProducts;
  final String? errorMessage;
  final bool success;
}
```

### 3. ProductIdValidator

A utility class for validating and managing product ID consistency:

```dart
class ProductIdValidator {
  /// Check if product has valid server ID
  static bool hasValidServerId(Product product);
  
  /// Filter products with server IDs only
  static List<Product> filterProductsWithServerIds(List<Product> products);
  
  /// Map local IDs to server IDs where possible
  static Future<Map<int, int>> mapLocalToServerIds(List<int> localIds);
  
  /// Validate server ID availability for Instagram operations
  static ValidationResult validateForInstagram(List<Product> products);
}

class ValidationResult {
  final List<Product> validProducts;
  final List<Product> invalidProducts;
  final List<String> errorMessages;
}
```

### 4. InstagramUrlGenerator

Centralized URL generation using server product IDs:

```dart
class InstagramUrlGenerator {
  /// Generate product URL using server ID
  static String generateProductUrl(int serverProductId);
  
  /// Generate Instagram page URL with server product references
  static String generateInstagramPageUrl(List<int> serverProductIds);
  
  /// Validate URL generation before publishing
  static bool validateUrls(List<int> serverProductIds);
  
  /// Update existing Instagram pages with server-based URLs
  static Future<void> migrateInstagramPageUrls();
}
```

## Data Models

### Enhanced Product Model Usage

The existing Product model will be used with emphasis on server ID fields:

```dart
// Existing Product model - emphasizing server ID usage
class Product {
  final int? id;           // Server ID (primary for Instagram operations)
  final int? localId;      // Local database ID (deprecated for Instagram)
  final int? serverId;     // Explicit server ID field
  final bool synced;       // Synchronization status
  // ... other existing fields
}
```

### Instagram Product Reference Model

New model for tracking Instagram page product references:

```dart
class InstagramProductReference {
  final String instagramPageId;
  final int serverProductId;
  final String productUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  
  InstagramProductReference({
    required this.instagramPageId,
    required this.serverProductId,
    required this.productUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });
}
```

### Server Product Fetch Configuration

Configuration model for server-based product fetching:

```dart
class InstagramProductFetchConfig {
  final String status;
  final bool marketplaceMode;
  final int? limit;
  final int? offset;
  final bool validateServerIds;
  final bool excludeUnsyncedProducts;
  
  const InstagramProductFetchConfig({
    this.status = 'publish',
    this.marketplaceMode = true,
    this.limit,
    this.offset,
    this.validateServerIds = true,
    this.excludeUnsyncedProducts = true,
  });
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Server-Based Product Data Consistency
*For any* Instagram product operation (loading, displaying, selecting, submitting), the system should use server-side product data exclusively, with all product references using server product IDs and no local database product IDs appearing in Instagram operations.
**Validates: Requirements 1.2, 1.6, 2.1, 2.2, 2.3**

### Property 2: Marketplace Pattern Consistency  
*For any* Instagram product gallery operation, the system should implement the same server-based product fetching logic as MarketplaceTab, including API calls with marketplace parameters, response parsing, deduplication using server IDs, and error handling.
**Validates: Requirements 1.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

### Property 3: Product Validation and Exclusion
*For any* product without a valid server ID, the system should exclude it from Instagram page creation, validate server ID availability before operations, notify users of exclusions, and display appropriate counts and messages.
**Validates: Requirements 2.5, 2.6, 4.1, 4.2, 4.3**

### Property 4: Server-Based URL Generation
*For any* Instagram page product URL generation, the system should construct URLs using server product IDs exclusively in the format /product/{server_product_id}, validate URL generation before publishing, and ensure all product links use server-based URLs.
**Validates: Requirements 5.1, 5.2, 5.3, 5.5, 5.6**

### Property 5: Data Freshness and Display Consistency
*For any* Instagram page display, the system should show product information fetched from server data, ensure images/names/prices match server-side data, reflect server changes, and maintain visual consistency with marketplace display.
**Validates: Requirements 6.1, 6.2, 6.3, 6.6**

### Property 6: Graceful Error Handling
*For any* error condition (server unavailability, individual product failures, missing products), the system should continue displaying available products, provide appropriate error messages, handle missing products gracefully, and log detailed information while showing user-friendly messages.
**Validates: Requirements 8.3, 8.6, 6.5**

### Property 7: Migration and ID Mapping
*For any* existing Instagram page with local product IDs, the system should attempt mapping to server IDs, update references where successful, mark failures for manual review, and remove all local ID references when migration is complete.
**Validates: Requirements 7.1, 7.2, 7.3, 7.6**

### Property 8: Intelligent Caching Behavior
*For any* cached product data, the system should validate cache freshness before display, refresh cached data when server information changes, show cached data while fetching updates, and optimize network requests while maintaining accuracy.
**Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.6**

### Property 9: Progressive Loading Implementation
*For any* large product catalog, the system should implement progressive loading to handle large datasets efficiently while maintaining server-based data consistency.
**Validates: Requirements 9.5**

### Property 10: Deduplication Using Server IDs
*For any* product deduplication operation, the system should use server product IDs as the primary key to ensure no duplicate products appear in Instagram galleries.
**Validates: Requirements 3.4**

<function_calls>
<invoke name="prework">
<parameter name="featureName">instagram-server-integration

## Error Handling

### Server Communication Failures
- **Network Unavailability**: Display clear error messages with retry options
- **API Response Errors**: Parse and display specific error messages from server
- **Timeout Handling**: Implement progressive timeout with exponential backoff
- **Partial Failures**: Continue operation with available data, log failures

### Product ID Validation Errors
- **Missing Server IDs**: Exclude products and notify users with clear explanations
- **Invalid ID Format**: Validate ID format before operations
- **ID Mismatch Detection**: Identify and report local/server ID inconsistencies
- **Synchronization Failures**: Provide sync options and detailed error reporting

### Instagram Page Creation Errors
- **Empty Product Selection**: Prevent creation with no valid products
- **URL Generation Failures**: Validate URLs before publishing
- **Publishing Errors**: Handle server-side publishing failures gracefully
- **Migration Errors**: Report and handle ID mapping failures during migration

### User Experience Error Handling
- **Progressive Error Disclosure**: Show basic errors first, detailed on request
- **Contextual Help**: Provide specific guidance for each error type
- **Recovery Actions**: Always provide actionable next steps
- **Error Persistence**: Remember and display recurring error patterns

## Testing Strategy

### Dual Testing Approach
This feature will use both unit testing and property-based testing for comprehensive coverage:

**Unit Tests** will focus on:
- Specific server API integration scenarios
- Error handling edge cases
- Migration logic with known data sets
- URL generation with specific product IDs
- UI behavior with mock server responses

**Property-Based Tests** will focus on:
- Universal properties across all server product data
- Comprehensive input coverage through randomization
- Validation of correctness properties defined above
- Server ID consistency across all operations

### Property-Based Testing Configuration
- **Testing Library**: Use `flutter_test` with custom property test helpers for server integration
- **Minimum Iterations**: 100 iterations per property test
- **Test Tags**: Each property test tagged with format: **Feature: instagram-server-integration, Property {number}: {property_text}**

### Test Coverage Areas

#### Server Integration Testing
- ProductService.getProducts API calls with marketplace parameters
- Server response parsing and error handling
- Network failure simulation and recovery
- Server ID validation and exclusion logic

#### Instagram Product Gallery Testing
- Server-based product loading and display
- Product selection using server IDs
- Search and filtering with server data
- Error state handling and user feedback

#### URL Generation Testing
- Server-based URL construction and validation
- URL format compliance and accessibility
- Link resolution using server product IDs
- Migration of existing URLs to server-based format

#### Migration Testing
- Local to server ID mapping logic
- Migration report generation and accuracy
- Backward compatibility during transition
- Cleanup of local ID references

#### Property Testing Implementation
- Each correctness property implemented as a single property-based test
- Server ID consistency validation across all operations
- Marketplace pattern compliance verification
- Error handling property validation

### Testing Implementation Notes
- All tests will use server-based data patterns for consistency
- Mock server responses will simulate real API behavior
- Integration tests will verify end-to-end Instagram creation flow
- Performance tests will validate caching and progressive loading

## Implementation Considerations

### Performance Optimization
- **Intelligent Caching**: Cache server product data with freshness validation
- **Progressive Loading**: Load products in batches for large catalogs
- **Network Optimization**: Minimize API calls while maintaining data accuracy
- **Background Sync**: Sync products in background without blocking UI

### Data Consistency
- **Server-First Approach**: Always prioritize server data over local cache
- **ID Validation**: Validate server IDs before any Instagram operations
- **Synchronization Status**: Track and display product sync status
- **Conflict Resolution**: Handle conflicts between local and server data

### Migration Strategy
- **Gradual Migration**: Migrate existing Instagram pages incrementally
- **Compatibility Layer**: Maintain backward compatibility during transition
- **Rollback Capability**: Ability to rollback if migration issues occur
- **Progress Tracking**: Monitor and report migration progress

### Security Considerations
- **API Authentication**: Ensure proper authentication for server API calls
- **Data Validation**: Validate all server responses before processing
- **Error Information**: Avoid exposing sensitive server information in errors
- **Access Control**: Verify user permissions for Instagram operations

### Scalability Considerations
- **Pagination Support**: Handle large product catalogs with pagination
- **Caching Strategy**: Implement multi-level caching for performance
- **Load Balancing**: Design for multiple server instances
- **Rate Limiting**: Respect server rate limits and implement backoff

### Future Extensibility
- **Modular Design**: Separate server integration from UI components
- **Plugin Architecture**: Allow for different server backends
- **Configuration Management**: Externalize server endpoints and parameters
- **Analytics Integration**: Track Instagram creation success rates and errors