# 404 Error Troubleshooting Guide

## 🔍 **Step-by-Step Debug**

### **Step 1: Server Health Check**
```bash
# 1. Server restart करें
Ctrl + C
node server.js

# 2. Console में check करें:
# ✅ Delivery fee update routes loaded successfully
```

### **Step 2: Route Testing**
```bash
# Browser में यह URLs test करें:

# Test 1: Server Health
http://localhost:3000/api/test-routes

# Test 2: Delivery Fee Test
http://localhost:3000/api/orders/test-delivery-fee

# Test 3: Manual Update Test
curl -X PUT http://localhost:3000/api/orders/update-delivery-fee/229 \
  -H "Content-Type: application/json" \
  -d '{"deliveryFee": 300}'
```

### **Step 3: Flutter Debugging**
Flutter app run करने के बाद console में check करें:

```
Testing API reachability...
Test Response Status: 200
Test Response Body: {"success": true, "message": "Delivery fee routes are working"...}
Updating delivery fee...
Update Response Status: 200
Update Response Body: {"success": true, "data": {...}}
```

## 🔴 **404 Error Causes**

### **Cause 1: Server Not Running**
**Symptoms**: सभी requests fail
**Solution**: Server restart करें

### **Cause 2: Wrong Port**
**Symptoms**: Connection refused
**Solution**: Port check करें
```bash
netstat -an | findstr :3000
```

### **Cause 3: Routes Not Loaded**
**Symptoms**: 404 on specific endpoints
**Solution**: Console logs check करें

### **Cause 4: Wrong URL in Flutter**
**Symptoms**: 404 only from Flutter
**Solution**: Config.baseNodeApiUrl check करें
```dart
print('Base URL: ${Config.baseNodeApiUrl}');
```

## 🛠️ **Quick Fixes**

### **Fix 1: Server Restart**
```bash
# Complete server restart
taskkill /f /im node.exe  # Windows
node server.js
```

### **Fix 2: URL Verification**
Flutter में check करें:
```dart
final url = '${Config.baseNodeApiUrl}/api/orders/update-delivery-fee/${widget.orderId}';
print('Full URL: $url');
```

### **Fix 3: Manual Database Check**
```sql
-- Direct database update test
UPDATE orders SET delivery_fee = 300, updated_delivery_fee = TRUE WHERE id = 229;
```

## 📋 **Expected Success Flow**

### **Server Console:**
```
✅ Delivery fee update routes loaded successfully
[DeliveryFee] Order: 229, Fee: 300
[DeliveryFee] Update result: 1 rows affected
[DeliveryFee] Success - Subtotal: 10200, Delivery: 300, Total: 10500
```

### **Flutter Console:**
```
Testing API reachability...
Test Response Status: 200
Test Response Body: {"success": true, "message": "Delivery fee routes are working"...}
Updating delivery fee...
Update Response Status: 200
Update Response Body: {"success": true, "data": {"delivery_fee": 300, "subtotal": 10200, "total": 10500}}
```

### **API Response:**
```json
{
  "success": true,
  "message": "Delivery fee updated successfully",
  "data": {
    "delivery_fee": 300,
    "subtotal": 10200,
    "total": 10500
  }
}
```

## 🚨 **If Still Getting 404**

### **Check 1: Server Logs**
Server console में exact error message देखें

### **Check 2: Network**
Postman या curl से test करें

### **Check 3: Flutter Configuration**
Config.dart में base URL check करें

### **Check 4: Route Conflicts**
दूसरी routes check करें कि कोई conflict तो नहीं है

## 🎯 **Final Test**

यह command run करें:
```bash
curl -v -X PUT http://localhost:3000/api/orders/update-delivery-fee/229 \
  -H "Content-Type: application/json" \
  -d '{"deliveryFee": 300}'
```

`-v` flag detailed output देगा जहाँ exact problem show होगा।

**Run इसे और result बताएं!**
