// Test script to verify the unlink endpoint is working
const axios = require('axios');

async function testUnlinkEndpoint() {
  try {
    console.log('Testing unlink endpoint...');
    
    // Test the endpoint is accessible
    const response = await axios.post('http://localhost:3000/api/unlink-website', {
      user_id: 'test',
      domain: 'test.com'
    });
    
    console.log('Response status:', response.status);
    console.log('Response data:', response.data);
    
  } catch (error) {
    if (error.response) {
      console.log('Error status:', error.response.status);
      console.log('Error data:', error.response.data);
    } else {
      console.log('Network error:', error.message);
    }
  }
}

testUnlinkEndpoint();
