// Test API endpoint
const axios = require('axios');

async function testAPI() {
  try {
    console.log('=== TESTING API ===');
    
    // Test the verify-app endpoint
    const response = await axios.post('http://localhost:3000/api/verify-app', {
      domain: 'zakhira.in',
      user_id: 1
    });
    
    console.log('API Response:', response.data);
    
  } catch (error) {
    console.error('API Error:', error.message);
    if (error.response) {
      console.error('Error Response:', error.response.data);
    }
  }
}

testAPI();
