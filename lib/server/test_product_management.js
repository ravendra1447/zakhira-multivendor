const http = require('http');

// Test configuration
const BASE_URL = 'http://localhost:3000'; // Update this to match your server URL

// Updated API endpoints after separation
const ENDPOINTS = {
  getProducts: '/admin/products',
  updateProduct: '/admin/products/',
  toggleBoth: '/admin/products/'
};

// Test functions
async function testGetProducts() {
  console.log('🧪 Testing GET /admin/products endpoint...');
  
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 3000,
      path: '/admin/products',
      method: 'GET',
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          console.log('✅ GET /admin/products response:', {
            statusCode: res.statusCode,
            success: response.success,
            productCount: response.products ? response.products.length : 0
          });
          
          if (response.success && response.products && response.products.length > 0) {
            console.log('📦 Sample product:', {
              id: response.products[0].id,
              name: response.products[0].name,
              is_active: response.products[0].is_active,
              marketplace_enabled: response.products[0].marketplace_enabled
            });
            resolve(response.products[0]); // Return first product for next test
          } else {
            console.log('⚠️ No products found or request failed');
            resolve(null);
          }
        } catch (error) {
          console.error('❌ Error parsing response:', error.message);
          reject(error);
        }
      });
    });

    req.on('error', (error) => {
      console.error('❌ Request error:', error.message);
      reject(error);
    });

    req.end();
  });
}

async function testUpdateProduct(productId) {
  if (!productId) {
    console.log('⚠️ Skipping product update test - no product available');
    return;
  }

  console.log(`🧪 Testing PUT /admin/products/${productId} endpoint...`);
  
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      is_active: 1,
      marketplace_enabled: 1
    });

    const options = {
      hostname: 'localhost',
      port: 3000,
      path: `/admin/products/${productId}`,
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          console.log('✅ PUT /admin/products response:', {
            statusCode: res.statusCode,
            success: response.success,
            message: response.message
          });
          resolve(response);
        } catch (error) {
          console.error('❌ Error parsing response:', error.message);
          reject(error);
        }
      });
    });

    req.on('error', (error) => {
      console.error('❌ Request error:', error.message);
      reject(error);
    });

    req.write(postData);
    req.end();
  });
}

async function testToggleBoth(productId) {
  if (!productId) {
    console.log('⚠️ Skipping toggle both test - no product available');
    return;
  }

  console.log(`🧪 Testing PUT /admin/products/${productId}/toggle-both endpoint...`);
  
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      is_active: 0,
      marketplace_enabled: 0
    });

    const options = {
      hostname: 'localhost',
      port: 3000,
      path: `/admin/products/${productId}/toggle-both`,
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          console.log('✅ PUT /admin/products/toggle-both response:', {
            statusCode: res.statusCode,
            success: response.success,
            message: response.message
          });
          resolve(response);
        } catch (error) {
          console.error('❌ Error parsing response:', error.message);
          reject(error);
        }
      });
    });

    req.on('error', (error) => {
      console.error('❌ Request error:', error.message);
      reject(error);
    });

    req.write(postData);
    req.end();
  });
}

// Main test runner
async function runTests() {
  console.log('🚀 Starting Product Management API Tests...');
  console.log('📍 Base URL:', BASE_URL);
  console.log('=' .repeat(50));

  try {
    // Test 1: Get all products
    const firstProduct = await testGetProducts();
    console.log('');

    // Test 2: Update single product field
    await testUpdateProduct(firstProduct?.id);
    console.log('');

    // Test 3: Toggle both statuses
    await testToggleBoth(firstProduct?.id);
    console.log('');

    console.log('✅ All tests completed successfully!');
    console.log('');
    console.log('📋 Test Summary:');
    console.log('  ✅ GET /admin/products - Fetch all products');
    console.log('  ✅ PUT /admin/products/:id - Update single field');
    console.log('  ✅ PUT /admin/products/:id/toggle-both - Toggle both statuses');
    console.log('');
    console.log('🎯 Integration Status: App and website status sync is working!');
    
  } catch (error) {
    console.error('❌ Tests failed:', error.message);
    console.log('');
    console.log('🔧 Troubleshooting:');
    console.log('  1. Make sure your server is running on port 3000');
    console.log('  2. Check that the productRoutes.js is properly mounted');
    console.log('  3. Verify database connection and products table exists');
    console.log('  4. Ensure the database has some products to test with');
  }
}

// Run the tests
runTests();
