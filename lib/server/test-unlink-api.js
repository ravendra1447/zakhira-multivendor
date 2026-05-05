// Test script to verify unlink API endpoint
const axios = require('axios');

async function testUnlinkApi() {
  try {
    console.log('Testing unlink API endpoint...');
    
    // Test data - replace with actual user ID and domain
    const testData = {
      user_id: 1, // Replace with actual user ID
      domain: 'example.com' // Replace with actual domain
    };
    
    const response = await axios.post('http://localhost:3000/api/unlink-website', testData);
    
    console.log('Response:', response.data);
    console.log('Unlink API test completed successfully!');
    
  } catch (error) {
    console.error('Error testing unlink API:', error.response?.data || error.message);
  }
}

testUnlinkApi();
