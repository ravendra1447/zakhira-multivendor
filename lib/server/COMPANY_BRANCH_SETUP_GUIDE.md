# Company & Branch Management System Setup Guide

## Overview
This system adds multi-company and multi-branch support to your WhatsApp chat application with the following workflow:
- **Branch admin publishes product** → **Order comes in** → **Assigned admin gets notification**

## Features Implemented

### 1. Database Schema
- ✅ `companies` table - Store multiple companies/brands
- ✅ `branches` table - Store branches for each company
- ✅ Modified `users` table - Added `company_id` and `branch_id` columns
- ✅ Modified `orders` table - Added `company_id`, `branch_id`, `assigned_admin_id` columns
- ✅ Modified `products` table - Added `company_id`, `branch_id`, `published_by_admin_id` columns

### 2. Management Interface
- ✅ **Company Management Form** (`/company_management.html`)
  - Add/Edit/Delete companies
  - Add/Edit/Delete branches
  - Assign users to companies and branches

### 3. APIs Created
- ✅ **Company Management** (`/api/companies`)
  - GET `/` - List all companies
  - POST `/` - Create new company
  - PUT `/:company_id` - Update company
  - DELETE `/:company_id` - Delete company
  - GET `/:company_id/branches` - Get company branches
  - POST `/:company_id/branches` - Create branch
  - PUT `/:company_id/branches/:branch_id` - Update branch
  - DELETE `/:company_id/branches/:branch_id` - Delete branch

- ✅ **User Assignment** (`/api/users`)
  - PUT `/assign-company-branch` - Assign user to company/branch
  - GET `/user-info/:phone` - Get user's company/branch info
  - GET `/by-company-branch/:company_id/:branch_id?` - Get users by company/branch
  - GET `/branch-admins/:company_id/:branch_id` - Get branch admins

- ✅ **Product Publishing** (Updated)
  - Products now automatically get `company_id`, `branch_id`, and `published_by_admin_id`
  - Branch admin info is automatically pulled from user profile

- ✅ **Order Routing** (Updated)
  - Orders automatically get assigned to the branch admin who published the product
  - Company and branch info is automatically set from product

- ✅ **FCM Notifications** (`/api/notifications`)
  - POST `/order-placed` - Send notification to branch admin on new order
  - GET `/user/:user_id` - Get user notifications
  - PUT `/:notification_id/read` - Mark notification as read
  - POST `/branch-admins` - Send custom notification to branch admins

- ✅ **Branch Filtering** (`/api/filter`)
  - GET `/products/branch/:branch_id` - Get products by branch
  - GET `/orders/branch/:branch_id` - Get orders by branch
  - GET `/users/branch/:branch_id` - Get users by branch
  - GET `/products/company/:company_id` - Get products by company
  - GET `/orders/company/:company_id` - Get orders by company
  - GET `/stats/branch/:branch_id` - Get branch statistics
  - GET `/stats/company/:company_id` - Get company statistics
  - GET `/orders/admin/:admin_id` - Get admin's assigned orders

## Setup Instructions

### 1. Run Database Migration
```bash
# Navigate to server directory
cd lib/server

# Run the migration
mysql -u chatuser -p chat_db < migrations/create_companies_and_branches_tables.sql
```

### 2. Install Firebase Admin SDK (for notifications)
```bash
cd lib/server
npm install firebase-admin
```

### 3. Add Firebase Service Account
Place your Firebase service account file at:
```
lib/server/firebase-service-account.json
```

### 4. Start the Server
```bash
cd lib/server
node server.js
```

### 5. Access Management Interface
Open in browser:
```
http://localhost:3000/company_management.html
```

## Workflow Example

### Step 1: Create Company and Branch
1. Open `company_management.html`
2. Go to "Companies" tab
3. Add a new company (e.g., "Test Company")
4. Go to "Branches" tab
5. Add a new branch (e.g., "Delhi Branch")

### Step 2: Assign Branch Admin
1. Go to "User Assignment" tab
2. Enter user's phone number
3. Select company and branch
4. Click "Assign User"

### Step 3: Branch Admin Publishes Product
When the branch admin publishes a product through the existing product system:
- Product automatically gets `company_id`, `branch_id`, `published_by_admin_id`
- The admin's company/branch info is pulled from their user profile

### Step 4: Customer Places Order
When a customer orders a product:
- Order automatically gets `company_id`, `branch_id`, `assigned_admin_id`
- The assigned admin is the one who published the product
- FCM notification is sent to the assigned admin

### Step 5: Admin Gets Notification
The branch admin receives:
- FCM push notification on their device
- Database notification record
- Order appears in their admin dashboard

## API Usage Examples

### Get Branch Products
```javascript
fetch('/api/filter/products/branch/1')
  .then(res => res.json())
  .then(data => console.log(data.data));
```

### Get Branch Orders
```javascript
fetch('/api/filter/orders/branch/1')
  .then(res => res.json())
  .then(data => console.log(data.data));
```

### Get Branch Statistics
```javascript
fetch('/api/filter/stats/branch/1')
  .then(res => res.json())
  .then(data => console.log(data.data));
```

### Send Custom Notification to Branch Admins
```javascript
fetch('/api/notifications/branch-admins', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    company_id: 1,
    branch_id: 1,
    title: 'New Announcement',
    message: 'Special discount available!',
    data: { type: 'promotion' }
  })
});
```

## Testing the System

### 1. Test Company/Branch Creation
- Use the management interface to create test data
- Verify data in database tables

### 2. Test User Assignment
- Assign a test user to a branch
- Check user record has correct `company_id` and `branch_id`

### 3. Test Product Publishing
- Login as assigned user
- Publish a product
- Verify product has correct company/branch/admin info

### 4. Test Order Flow
- Place an order for the published product
- Check order has correct assignment
- Verify notification is sent to admin

### 5. Test Filtering
- Use filter APIs to get branch-specific data
- Verify correct data is returned

## Important Notes

1. **Backward Compatibility**: Existing products and orders will have NULL company/branch fields until updated
2. **User Assignment**: Users must be assigned to companies/branches before they can publish products
3. **FCM Setup**: Firebase service account is required for push notifications
4. **Security**: All APIs validate company/branch relationships to prevent data access issues

## Troubleshooting

### Migration Issues
- Check MySQL connection: `mysql -u chatuser -p chat_db`
- Verify table creation: `SHOW TABLES LIKE '%compan%'; SHOW TABLES LIKE '%branch%';`

### Notification Issues
- Check Firebase service account file exists and is valid
- Verify user has `fcm_token` in database
- Check server logs for FCM errors

### Assignment Issues
- Verify user exists in users table
- Check company and branch exist
- Ensure foreign key constraints are satisfied

This system provides a complete multi-branch workflow with proper order routing and notifications as requested!
