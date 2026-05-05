// Test script for availability deletion functionality
const mysql = require('mysql2/promise');

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

async function testAvailabilityDeletion() {
  console.log('🧪 Testing Product Variant Deletion on Unavailable Status');
  
  try {
    const connection = await pool.getConnection();
    
    // Test 1: Check if order is in pending status
    const orderId = 385; // Using the order ID from the image
    const [orderCheck] = await connection.execute(
      'SELECT id, order_status FROM orders WHERE id = ?',
      [orderId]
    );
    
    if (orderCheck.length === 0) {
      console.log('❌ Order not found');
      return;
    }
    
    console.log(`📋 Order #${orderId} status: ${orderCheck[0].order_status}`);
    
    if (orderCheck[0].order_status !== 'Pending') {
      console.log('⚠️ Order is not in Pending status - variant deletion will not work');
      console.log('💡 To test this feature, you need a pending order');
    } else {
      console.log('✅ Order is in Pending status - variant deletion should work');
    }
    
    // Test 2: Check order items
    const [orderItems] = await connection.execute(
      'SELECT * FROM order_items WHERE order_id = ?',
      [orderId]
    );
    
    console.log(`📦 Found ${orderItems.length} items in order`);
    
    for (const item of orderItems) {
      console.log(`   Item ${item.id}: ${item.product_name} - Color: ${item.color}, Size: ${item.size}, Availability: ${item.availability_status}`);
    }
    
    // Test 3: Check if product variants exist in database
    if (orderItems.length > 0) {
      const firstItem = orderItems[0];
      const productId = firstItem.product_id;
      const color = firstItem.color;
      const size = firstItem.size;
      
      console.log(`\n🔍 Checking variants for Product ID: ${productId}, Color: ${color}, Size: ${size}`);
      
      // Check product_variants table
      const [variants] = await connection.execute(
        'SELECT * FROM product_variants WHERE product_id = ? AND color_name = ? AND size = ?',
        [productId, color, size]
      );
      
      console.log(`📊 product_variants: ${variants.length} found`);
      
      // Check product_colors table
      const [colors] = await connection.execute(
        'SELECT * FROM product_colors WHERE product_id = ? AND color_name = ?',
        [productId, color]
      );
      
      console.log(`🎨 product_colors: ${colors.length} found`);
      
      // Check product_sizes table
      const [sizes] = await connection.execute(
        'SELECT * FROM product_sizes WHERE product_id = ? AND size = ?',
        [productId, size]
      );
      
      console.log(`📏 product_sizes: ${sizes.length} found`);
      
      if (variants.length === 0 && colors.length === 0 && sizes.length === 0) {
        console.log('⚠️ No product variants found - nothing to test deletion');
      }
    }
    
    // Test 4: Simulate the API call (without actually deleting)
    console.log('\n🔄 Simulating API call to update availability...');
    console.log('📤 POST /orders/update-availability');
    console.log('📄 Body: {');
    console.log(`   "orderId": ${orderId},`);
    console.log(`   "itemId": ${orderItems[0]?.id},`);
    console.log('   "availabilityStatus": 1  // 1 = Unavailable');
    console.log('}');
    
    console.log('\n✅ Test completed successfully!');
    console.log('💡 To actually test the deletion:');
    console.log('   1. Make sure you have a pending order');
    console.log('   2. Go to the order details screen');
    console.log('   3. Change the availability dropdown to "Unavailable"');
    console.log('   4. Check the console logs and database for deletion');
    
    connection.release();
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
}

// Run the test
testAvailabilityDeletion().then(() => {
  console.log('\n🏁 Test script finished');
  process.exit(0);
}).catch(error => {
  console.error('💥 Test script crashed:', error);
  process.exit(1);
});
