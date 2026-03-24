const axios = require('axios');

// Test production API endpoints
async function testProductionAPI() {
  const baseURL = 'https://node-api.bangkokmart.in/api';
  
  console.log('🔍 Testing Production API...');
  console.log('Base URL:', baseURL);
  
  try {
    // Test 1: Check if server is reachable
    console.log('\n1. Testing server reachability...');
    const testResponse = await axios.get(`${baseURL}/orders/test-delivery-fee`);
    console.log('✅ Server reachable:', testResponse.data);
    
    // Test 2: Test delivery fee update
    console.log('\n2. Testing delivery fee update...');
    const updateResponse = await axios.put(
      `${baseURL}/orders/update-delivery-fee/229`,
      { deliveryFee: 200 },
      { headers: { 'Content-Type': 'application/json' } }
    );
    console.log('✅ Update successful:', updateResponse.data);
    
  } catch (error) {
    console.log('❌ Error:', error.response?.status, error.response?.data || error.message);
    
    if (error.response?.status === 404) {
      console.log('\n🔧 SOLUTION: Production server needs delivery fee routes update!');
      console.log('Upload these files to production:');
      console.log('- lib/server/routes/order/updateDeliveryFee.js');
      console.log('- Update server.js to include delivery fee routes');
    }
  }
}

testProductionAPI();
