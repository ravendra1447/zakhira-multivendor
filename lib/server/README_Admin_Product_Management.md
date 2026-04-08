# Admin Product Management System

## 📁 File Structure

```
lib/
├── screens/admin/
│   └── product_management_screen.dart    # Flutter UI for product management
├── server/routes/
│   ├── productRoutes.js                  # Main product routes (unchanged)
│   └── adminProductRoutes.js             # Admin-specific product management routes
└── server/
    ├── server.js                         # Main server file (updated)
    └── test_product_management.js        # API testing script
```

## 🔗 API Endpoints

### Admin Product Management Routes (`/api/admin/products`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/admin/products` | Get all products for admin management |
| PUT | `/api/admin/products/:id` | Update single product field |
| PUT | `/api/admin/products/:id/toggle-both` | Toggle both statuses simultaneously |

### Main Product Routes (`/api/products`)
- All existing product routes remain unchanged
- No impact on current functionality

## 🎯 Features

### Product Management Screen
- **Search**: Find products by name, category, or brand
- **Filters**: All, Active, Inactive, Marketplace Enabled, Marketplace Disabled
- **Auto-refresh**: 10-second interval updates
- **Manual refresh**: On-demand data refresh
- **Status toggles**: Individual and combined status controls

### Status Management
- **`is_active`**: Controls overall product status (syncs with website)
- **`marketplace_enabled`**: Controls marketplace visibility
- **Toggle Both**: Simultaneous status changes

## 🚀 How to Use

### 1. Access the Feature
1. Open Admin Dashboard
2. Click menu (⋮) in top-right
3. Select "Manage Products"

### 2. Manage Products
1. **Search products** using the search bar
2. **Apply filters** to view specific product categories
3. **Toggle status** by clicking the status buttons:
   - Green/Red: Active/Inactive
   - Blue/Orange: Marketplace/Not in Marketplace
   - Purple: Toggle Both (simultaneous)

### 3. Test the API
```bash
cd lib/server
node test_product_management.js
```

## 🔄 Database Integration

### Products Table Fields
- `is_active` (tinyint): Overall product status
- `marketplace_enabled` (tinyint): Marketplace visibility
- `updated_at` (timestamp): Last modification time

### Status Sync
- Changes in app immediately reflect on website
- Both platforms share the same database
- Real-time synchronization

## 🛠️ Technical Implementation

### Frontend (Flutter)
- **File**: `product_management_screen.dart`
- **State Management**: StatefulWidget with auto-refresh
- **UI Components**: Cards, chips, toggle buttons
- **API Integration**: HTTP requests with error handling

### Backend (Node.js)
- **File**: `adminProductRoutes.js`
- **Database**: MySQL with connection pooling
- **Validation**: Input validation and error handling
- **Security**: Admin-only access control

### Separation Benefits
1. **Clean Code**: Admin routes separated from main product routes
2. **Easy Maintenance**: Independent management of admin features
3. **No Confusion**: Clear distinction between admin and public APIs
4. **Scalability**: Easy to add more admin features

## 📱 Mobile App Integration

### Navigation Flow
```
Dashboard → Menu → Manage Products → Product List → Status Toggle
```

### User Experience
- **Visual Feedback**: Color-coded status indicators
- **Success Messages**: SnackBar notifications
- **Loading States**: Progress indicators
- **Error Handling**: User-friendly error messages

## 🌐 Website Integration

### Status Synchronization
- **App Changes** → **Database** → **Website Updates**
- **Website Changes** → **Database** → **App Updates**
- **Real-time**: Immediate reflection across platforms

### Benefits
- **Consistent Experience**: Same product status everywhere
- **Central Control**: Single point of management
- **Efficiency**: No duplicate management needed

## 🔧 Troubleshooting

### Common Issues
1. **API Not Working**: Check server.js route registration
2. **Database Errors**: Verify MySQL connection and table structure
3. **UI Not Updating**: Check Flutter state management
4. **Status Not Syncing**: Verify database field updates

### Testing Commands
```bash
# Start server
node lib/server/server.js

# Test API endpoints
node lib/server/test_product_management.js

# Check logs for errors
tail -f logs/server.log
```

## 📊 Performance Considerations

### Optimization
- **Connection Pooling**: Reuse database connections
- **Auto-refresh**: Configurable intervals
- **Caching**: Local data caching in Flutter
- **Pagination**: For large product lists (future enhancement)

### Security
- **Admin Validation**: Only admin users can access
- **Input Sanitization**: Prevent SQL injection
- **Error Handling**: No sensitive data exposure

---

## ✅ Summary

The Admin Product Management system provides:
- **Complete Control**: Manage product visibility and status
- **Easy Integration**: Separated routes for clarity
- **Real-time Sync**: App and website synchronization
- **User-Friendly**: Intuitive interface with visual feedback
- **Scalable**: Easy to extend and maintain

This implementation ensures that administrators can efficiently manage product visibility across both the mobile app and website from a single, unified interface.
