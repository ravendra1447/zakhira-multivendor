const http = require('http');

// Test 1: Check if routes are loaded
console.log('Testing route availability...');

const testOptions = {
  hostname: 'localhost',
  port: 3000,
  path: '/api/orders/test-delivery-fee',
  method: 'GET'
};

const testReq = http.request(testOptions, (res) => {
  console.log(`Test Route Status: ${res.statusCode}`);
  res.on('data', (chunk) => {
    console.log('Test Route Response:', chunk.toString());
  });
});

testReq.on('error', (e) => {
  console.error('Test Route Error:', e.message);
});

testReq.end();

// Test 2: Test actual update
setTimeout(() => {
  console.log('\nTesting delivery fee update...');
  
  const data = JSON.stringify({
    deliveryFee: 300
  });
  
  const updateOptions = {
    hostname: 'localhost',
    port: 3000,
    path: '/api/orders/update-delivery-fee/229',
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': data.length
    }
  };
  
  const updateReq = http.request(updateOptions, (res) => {
    console.log(`Update Status: ${res.statusCode}`);
    res.on('data', (chunk) => {
      console.log('Update Response:', chunk.toString());
    });
  });
  
  updateReq.on('error', (e) => {
    console.error('Update Error:', e.message);
  });
  
  updateReq.write(data);
  updateReq.end();
}, 1000);
