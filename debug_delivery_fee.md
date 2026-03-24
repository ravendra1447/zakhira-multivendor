# Delivery Fee 404 Error Debug

## Problem 🔴
User gets 404 error when updating delivery fee from Flutter app.

## Debugging Steps 🧪

### 1. Test if Routes are Loaded
```bash
# Start server and check console logs
node server.js

# Look for this message:
# ✅ Delivery fee update routes loaded successfully
```

### 2. Test Route Directly
```bash
# Test the test endpoint
curl http://localhost:3000/api/orders/test-delivery-fee

# Expected response:
# {
#   "success": true,
#   "message": "Delivery fee routes are working",
#   "timestamp": "2026-03-23T..."
# }
```

### 3. Test Actual Update Endpoint
```bash
# Test the actual update endpoint
curl -X PUT http://localhost:3000/api/orders/update-delivery-fee/229 \
  -H "Content-Type: application/json" \
  -d '{"deliveryFee": 300}'

# Check server console for:
# [DeliveryFee] Updating delivery fee for order 229: 300
```

### 4. Check Database Migration
```sql
-- Make sure the columns exist
DESCRIBE orders;

-- Should show:
-- delivery_fee
-- updated_delivery_fee
```

## Common Issues & Solutions 🛠️

### Issue 1: Route Not Loading
**Problem**: Module not found error
**Solution**: Check file path in server.js
```javascript
// Make sure this path is correct
const updateDeliveryFeeRoutes = require("./routes/order/updateDeliveryFee");
```

### Issue 2: Database Columns Missing
**Problem**: Column 'delivery_fee' doesn't exist
**Solution**: Run migration
```sql
ALTER TABLE orders 
ADD COLUMN delivery_fee DECIMAL(10, 2) DEFAULT 250.00,
ADD COLUMN updated_delivery_fee BOOLEAN DEFAULT FALSE;
```

### Issue 3: Port Conflict
**Problem**: Server not running on expected port
**Solution**: Check which port server is using
```bash
netstat -tulpn | grep :3000
```

### Issue 4: CORS Issues
**Problem**: Flutter app can't reach API
**Solution**: Check CORS settings
```javascript
app.use(cors({
  origin: ['http://localhost:3000', 'http://127.0.0.1:3000'],
  credentials: true
}));
```

## Flutter Debug Tips 📱

### Add Logging to Flutter
```dart
try {
  final response = await http.put(
    Uri.parse('${Config.baseNodeApiUrl}/api/orders/update-delivery-fee/${widget.orderId}'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'deliveryFee': deliveryFee}),
  );
  
  print('URL: ${Config.baseNodeApiUrl}/api/orders/update-delivery-fee/${widget.orderId}');
  print('Status Code: ${response.statusCode}');
  print('Response Body: ${response.body}');
  
} catch (e) {
  print('Error: $e');
}
```

### Check Config
```dart
// Make sure Config.baseNodeApiUrl is correct
print('Base URL: ${Config.baseNodeApiUrl}');
// Should be: http://localhost:3000 or your server URL
```

## Quick Test Script 🚀

Create a test file `test_delivery_fee.js`:
```javascript
const http = require('http');

const data = JSON.stringify({
  deliveryFee: 300
});

const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/api/orders/update-delivery-fee/229',
  method: 'PUT',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': data.length
  }
};

const req = http.request(options, (res) => {
  console.log(`Status: ${res.statusCode}`);
  console.log(`Headers: ${JSON.stringify(res.headers)}`);
  
  res.on('data', (chunk) => {
    console.log(`Body: ${chunk}`);
  });
});

req.on('error', (e) => {
  console.error(`Problem with request: ${e.message}`);
});

req.write(data);
req.end();
```

Run: `node test_delivery_fee.js`

## Expected Server Logs 📋

When working correctly, you should see:
```
✅ Delivery fee update routes loaded successfully
[DeliveryFee] Updating delivery fee for order 229: 300
[DeliveryFee] Update result: 1 rows affected
[DeliveryFee] Success - Subtotal: 10200, Delivery: 300, Total: 10500
```

## If Still Getting 404 🔴

1. **Restart Server**: `node server.js`
2. **Check Port**: Make sure server is running on correct port
3. **Verify URL**: Check Config.baseNodeApiUrl in Flutter
4. **Test Manually**: Use curl to test endpoint directly
5. **Check Logs**: Look for any error messages in server console

## Working URL Examples ✅

```
Test: http://localhost:3000/api/orders/test-delivery-fee
Update: http://localhost:3000/api/orders/update-delivery-fee/229
Get: http://localhost:3000/api/orders/get-delivery-fee/229
```
