// Test IP-based domain verification
const axios = require('axios');

async function testIPVerification() {
  const testDomains = [
    'bangkokmart.in',      // Your domain (should match)
    'zakhira.in',          // Your domain (should match) 
    'google.com',          // External domain (should require admin)
    'facebook.com',        // External domain (should require admin)
    'localhost',           // Local (should match)
    'nonexistent.domain'    // Invalid domain (should fail)
  ];

  for (const domain of testDomains) {
    console.log(`\n=== Testing: ${domain} ===`);
    
    try {
      const response = await axios.post('http://localhost:3000/api/verify-app', {
        domain: domain,
        user_id: 1
      });

      console.log('Status:', response.status);
      console.log('Success:', response.data.success);
      
      if (response.data.verification) {
        console.log('Verification Method:', response.data.verification.method);
        console.log('Server Match:', response.data.verification.server_match);
        console.log('Verified:', response.data.verification.verified);
        
        if (response.data.verification.detected_ip) {
          console.log('Detected IP:', response.data.verification.detected_ip);
        }
        if (response.data.verification.your_server_ips) {
          console.log('Your Server IPs:', response.data.verification.your_server_ips);
        }
      }
      
      console.log('Message:', response.data.message);
      
    } catch (error) {
      if (error.response) {
        console.log('Error Status:', error.response.status);
        console.log('Error Message:', error.response.data.message);
        
        if (error.response.data.verification) {
          console.log('Verification Error:', error.response.data.verification.error);
        }
      } else {
        console.log('Network Error:', error.message);
      }
    }
  }
}

testIPVerification();
