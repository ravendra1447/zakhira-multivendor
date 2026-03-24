const express = require('express');
const router = express.Router();
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const mysql = require('mysql2/promise');
const PaymentUrlObfuscator = require('../../utils/paymentUrlObfuscator');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});
// Configure multer for file uploads
const upload = multer({ dest: 'uploads/qr-codes/' });

// Route: Send WhatsApp with QR Code (No Verification Required)
router.post('/send-with-qr', async (req, res) => {
  try {
    const { orderId, customerPhone, message, qrCodeBase64 } = req.body;

    if (!orderId || !customerPhone || !message || !qrCodeBase64) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields'
      });
    }

    // Save QR code to server
    const timestamp = Date.now();
    const qrFileName = `qr_${orderId}_${timestamp}.jpeg`;
    const qrFilePath = path.join(__dirname, '../../../uploads/qr-codes/', qrFileName);

    // Create directory if it doesn't exist
    const qrDir = path.dirname(qrFilePath);
    if (!fs.existsSync(qrDir)) {
      fs.mkdirSync(qrDir, { recursive: true });
    }

    // Save base64 QR code
    const qrBuffer = Buffer.from(qrCodeBase64, 'base64');
    fs.writeFileSync(qrFilePath, qrBuffer);

    // Generate public URL for QR code
    const qrPublicUrl = `http://184.168.126.71/api/uploads/qr-codes/${qrFileName}`;

    // Method 1: WhatsApp Business API (if available)
    try {
      const whatsappResponse = await sendViaWhatsAppAPI(
        customerPhone,
        message,
        qrPublicUrl
      );

      if (whatsappResponse.success) {
        return res.json({
          success: true,
          method: 'whatsapp_api',
          message: 'Message sent via WhatsApp API',
          qrUrl: qrPublicUrl
        });
      }
    } catch (apiError) {
      console.log('WhatsApp API not available, trying alternative methods...');
    }

    // Method 2: Generate WhatsApp Web Automation Link
    const webAutomationUrl = await generateWhatsAppWebLink(
      customerPhone,
      message,
      qrPublicUrl
    );

    // Method 3: Create custom WhatsApp deep link
    const deepLink = generateWhatsAppDeepLink(
      customerPhone,
      message,
      qrPublicUrl
    );

    return res.json({
      success: true,
      method: 'deep_link',
      message: 'Use the provided link to send message with QR code',
      qrUrl: qrPublicUrl,
      webAutomationUrl,
      deepLink,
      instructions: {
        step1: 'Click on the deep link to open WhatsApp',
        step2: 'The QR code will be automatically attached',
        step3: 'Send the message to the customer'
      }
    });

  } catch (error) {
    console.error('Error in send-with-qr:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
});

// WhatsApp Business API Integration
async function sendViaWhatsAppAPI(phone, message, qrUrl) {
  try {
    // This would require WhatsApp Business API setup
    // For now, return mock response
    return {
      success: false,
      message: 'WhatsApp Business API not configured'
    };

    /* 
    // Actual implementation would be:
    const response = await axios.post('https://graph.facebook.com/v18.0/YOUR_PHONE_NUMBER_ID/messages', {
      messaging_product: 'whatsapp',
      to: phone,
      type: 'template',
      template: {
        name: 'order_payment',
        language: { code: 'en' },
        components: [{
          type: 'header',
          parameters: [{
            type: 'image',
            image: { link: qrUrl }
          }]
        }, {
          type: 'body',
          parameters: [{
            type: 'text',
            text: message
          }]
        }]
      }
    }, {
      headers: {
        'Authorization': 'Bearer YOUR_ACCESS_TOKEN',
        'Content-Type': 'application/json'
      }
    });
    
    return { success: true, data: response.data };
    */
  } catch (error) {
    return { success: false, error: error.message };
  }
}

// Generate WhatsApp Web Automation URL
async function generateWhatsAppWebLink(phone, message, qrUrl) {
  try {
    // Create a web page that automates WhatsApp Web
    const automationUrl = `http://184.168.126.71/whatsapp-automation?phone=${phone}&message=${encodeURIComponent(message)}&qr=${encodeURIComponent(qrUrl)}`;
    return automationUrl;
  } catch (error) {
    return null;
  }
}

// Generate Custom WhatsApp Deep Link
function generateWhatsAppDeepLink(phone, message, qrUrl) {
  try {
    // Method 1: Use WhatsApp's undocumented image parameter
    const encodedMessage = encodeURIComponent(message);
    const encodedQr = encodeURIComponent(qrUrl);

    // Try different WhatsApp URL formats
    const urls = [
      `https://wa.me/${phone}?text=${encodedMessage}&media=${encodedQr}`,
      `https://api.whatsapp.com/send?phone=${phone}&text=${encodedMessage}&attachment=${encodedQr}`,
      `whatsapp://send?phone=${phone}&text=${encodedMessage}&image=${encodedQr}`
    ];

    // Return the most likely to work
    return urls[0];
  } catch (error) {
    return `https://wa.me/${phone}?text=${encodeURIComponent(message)}`;
  }
}

// Route: WhatsApp Web Automation
router.get('/automation', async (req, res) => {
  try {
    const { phone, message, qr } = req.query;

    // Serve HTML page for WhatsApp automation
    const html = `
    <!DOCTYPE html>
    <html>
    <head>
        <title>WhatsApp Automation</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body>
        <div style="padding: 20px; text-align: center;">
            <h2>?? WhatsApp Automation</h2>
            <p>Opening WhatsApp with QR code...</p>
            <div id="status">Initializing...</div>
        </div>
        
        <script>
            const phone = '${phone}';
            const message = '${message.replace(/'/g, "\\'")}';
            const qrUrl = '${qr}';
            
            // Open WhatsApp
            setTimeout(() => {
                window.open(\`https://wa.me/\${phone}?text=\${encodeURIComponent(message)}\`, '_blank');
                document.getElementById('status').innerHTML = '? WhatsApp opened! QR code prepared.';
                
                // Auto-close after 3 seconds
                setTimeout(() => {
                    window.close();
                }, 3000);
            }, 1000);
        </script>
    </body>
    </html>
    `;

    res.setHeader('Content-Type', 'text/html');
    res.send(html);

  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Route: Get Default QR Code
router.get('/default-qr', (req, res) => {
  try {
    const defaultQrPath = path.join(__dirname, '../../../uploads/qr-codes/upi_qr_code.jpeg');

    if (fs.existsSync(defaultQrPath)) {
      res.sendFile(defaultQrPath);
    } else {
      // If default QR doesn't exist, return working URL
      const qrUrl = 'https://bangkokmart.in/uploads/qr-codes/upi_qr_code.jpeg';
      res.json({
        success: true,
        message: 'Default QR code available at URL',
        qrUrl: qrUrl
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Route: Send WhatsApp with Default QR Code
router.post('/send-with-default-qr', async (req, res) => {
  try {
    const { orderId, customerPhone, message } = req.body;

    if (!orderId || !customerPhone || !message) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields'
      });
    }

    // Use default QR code URL - using working URL
    const defaultQrUrl = 'https://bangkokmart.in/uploads/qr-codes/upi_qr_code.jpeg';
    const timestamp = Date.now();

    // Generate WhatsApp deep link
    const deepLink = `https://wa.me/${customerPhone}?text=${encodeURIComponent(message)}&media=${encodeURIComponent(defaultQrUrl)}`;

    return res.json({
      success: true,
      method: 'default_qr',
      message: 'Using default QR code for WhatsApp sharing',
      qrUrl: defaultQrUrl,
      deepLink: deepLink,
      instructions: {
        step1: 'Click on the deep link to open WhatsApp',
        step2: 'The default QR code will be attached',
        step3: 'Send the message to the customer'
      }
    });

  } catch (error) {
    console.error('Error in send-with-default-qr:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
});

// Route: Enhanced QR Code Page with Timer and Share
router.get('/payment-qr/:orderParam', async (req, res) => {
  try {
    const { orderParam } = req.params;
    
    // Extract actual order ID from parameter (handles both direct IDs and obfuscated tokens)
    const orderId = PaymentUrlObfuscator.getOrderIdFromParam(orderParam);
    
    if (!orderId) {
      console.error(`[PaymentQR] Invalid order parameter: ${orderParam}`);
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid order parameter',
        error: 'Could not extract order ID from parameter'
      });
    }
    
    console.log(`[PaymentQR] Extracted Order ID: ${orderId} from parameter: ${orderParam}`);

    // Fetch order amount and calculate total with delivery fee
    let subtotalAmount = 0;
    let deliveryFee = 250; // Default delivery fee
    let totalAmount = 0;
    
    try {
      // Get order details including manual delivery fee
      const [orders] = await pool.execute(
        'SELECT total_amount, delivery_fee, updated_delivery_fee FROM orders WHERE id = ?',
        [orderId]
      );
      
      if (orders.length > 0) {
        const order = orders[0];
        subtotalAmount = parseFloat(order.total_amount) || 0;
        
        // Use manual delivery fee if updated, otherwise use default
        if (order.updated_delivery_fee && order.delivery_fee !== null) {
          deliveryFee = parseFloat(order.delivery_fee) || 250;
          console.log(`[PaymentQR] Using manual delivery fee: ${deliveryFee}`);
        } else {
          // Get current shipping rate from database
          const [shippingRates] = await pool.execute(
            'SELECT rate FROM shipping_rates WHERE is_active = TRUE ORDER BY id LIMIT 1'
          );
          
          if (shippingRates.length > 0) {
            deliveryFee = parseFloat(shippingRates[0].rate) || 250;
            console.log(`[PaymentQR] Using default shipping rate: ${deliveryFee}`);
          }
        }
        
        totalAmount = subtotalAmount + deliveryFee;
      }
    } catch (e) {
      console.error('Error fetching order amount:', e);
      // Fallback to default values
      subtotalAmount = 0;
      deliveryFee = 250;
      totalAmount = deliveryFee;
    }

    // DEBUG: Log amount and type
    console.log(`[PaymentQR] Order: ${orderId}, Subtotal: ${subtotalAmount}, Delivery: ${deliveryFee}, Total: ${totalAmount}`);

    const upiId = 'ravendra8957370964-1@oksbi';
    const upiName = 'Ravendra Kumar';
    const qrUrl = 'https://bangkokmart.in/uploads/qr-codes/upi_qr_code.jpeg';

    // Ensure amount is formatted to 2 decimal places (e.g. "100.00")
    const formattedAmount = Number(totalAmount).toFixed(2);

    // UPI Deep Link with Amount and Order ID - Enhanced for PhonePe and GPay note field
    // Using 'remark' parameter for better compatibility with note field
    const upiLink = `upi://pay?pa=${upiId}&pn=${encodeURIComponent(`Order ${orderId} Payment - ${upiName}`)}&tr=ORDER${orderId}&tn=Order%20ID%3A%20${orderId}&am=${formattedAmount}&mam=${formattedAmount}&cu=INR&remark=Order%20ID%3A%20${orderId}`;

    console.log('[PaymentQR] Generated UPI Link:', upiLink);

    const html = `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Pay for Order #${orderId}</title>
        <meta property="og:image" content="${qrUrl}">
        <meta property="og:title" content="Payment for Order #${orderId}">
        <meta property="og:description" content="Secure Payment Link">
        <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --primary: #6366f1;
                --primary-dark: #4f46e5;
                --success: #10b981;
                --warning: #f59e0b;
                --danger: #ef4444;
                --bg-gradient: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
                --card-bg: rgba(255, 255, 255, 0.95);
                --shadow: 0 10px 30px -5px rgba(0, 0, 0, 0.1);
            }

            * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Outfit', sans-serif; }

            body {
                background: var(--bg-gradient);
                min-height: 100vh;
                display: flex;
                flex-direction: column; /* Ensure vertical stacking */
                align-items: center; /* Center horizontally */
                justify-content: flex-start; /* Align to top */
                padding: 20px 16px; /* Top padding 20px */
                color: #1f2937;
            }

            .container {
                background: var(--card-bg);
                backdrop-filter: blur(10px);
                border-radius: 20px;
                box-shadow: var(--shadow);
                width: 100%; /* Full width allowing for padding */
                max-width: 380px; 
                padding: 16px; 
                text-align: center;
                border: 1px solid rgba(255, 255, 255, 0.6);
                animation: slideUp 0.6s cubic-bezier(0.16, 1, 0.3, 1);
                margin: 0 auto; /* Remove vertical margin reliance */
            }

            @keyframes slideUp {
                from { transform: translateY(20px); opacity: 0; }
                to { transform: translateY(0); opacity: 1; }
            }

            .header { margin-bottom: 12px; }
            
            .badge {
                display: inline-flex;
                align-items: center;
                padding: 3px 10px;
                background: #e0e7ff;
                color: var(--primary-dark);
                border-radius: 20px;
                font-weight: 600;
                font-size: 0.8rem;
                margin-bottom: 6px;
                box-shadow: 0 2px 5px rgba(99, 102, 241, 0.15);
            }

            h1 { font-size: 1.35rem; font-weight: 700; color: #111827; margin-bottom: 2px; }
            p.subtitle { color: #6b7280; font-size: 0.85rem; }

            .amount-display {
                font-size: 1.6rem;
                font-weight: 800;
                color: #111827;
                margin: 4px 0;
                letter-spacing: -0.5px;
            }



            .qr-wrapper {
                position: relative;
                padding: 10px;
                background: white;
                border-radius: 16px;
                box-shadow: inset 0 0 0 1px rgba(0,0,0,0.05);
                margin: 0 auto 15px;
                max-width: 250px; /* Larger QR container */
            }

            .qr-image {
                width: 100%;
                height: auto;
                border-radius: 8px;
                display: block;
            }

            .scan-anim {
                position: absolute;
                top: 10px; left: 10px; right: 10px; height: 2px;
                background: var(--primary);
                box-shadow: 0 0 10px var(--primary);
                animation: scan 2s infinite ease-in-out;
                opacity: 0.6;
            }

            @keyframes scan {
                0% { top: 10px; }
                50% { top: calc(100% - 10px); }
                100% { top: 10px; }
            }

            .status-indicator {
                margin-top: 10px;
                padding: 8px;
                border-radius: 10px;
                font-weight: 600;
                transition: all 0.3s ease;
                font-size: 0.85rem;
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 6px;
            }

            .status-pending { background: #f3f4f6; color: #4b5563; }
            .status-success { background: #d1fae5; color: #065f46; transform: scale(1.05); }
            .status-expired { background: #fee2e2; color: #991b1b; }

            .actions { display: grid; gap: 8px; margin-top: 15px; }
            
            .btn {
                display:flex; justify-content: center; align-items: center;
                padding: 10px; /* Reduced button size */
                border: none;
                border-radius: 12px;
                font-weight: 600;
                font-size: 0.9rem;
                cursor: pointer;
                transition: transform 0.2s, box-shadow 0.2s;
                text-decoration: none;
                gap: 8px;
            }

            .btn:active { transform: scale(0.98); }
            
            .btn-primary {
                background: #25D366;
                color: white;
                box-shadow: 0 4px 12px rgba(37, 211, 102, 0.3);
            }
            
            .btn-secondary {
                background: white;
                color: #4b5563;
                border: 1px solid #e5e7eb;
            }

            @keyframes progress { from { width: 100%; } to { width: 0%; } }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <div class="badge">Order #${orderId}</div>
                <h1>Payment Request</h1>
                <div style="text-align: center; margin-bottom: 8px;">
                    <div style="font-size: 0.9rem; color: #6b7280; margin-bottom: 4px;">Order Summary:</div>
                    <div style="display: flex; justify-content: space-between; align-items: center; background: #f9fafb; padding: 8px 12px; border-radius: 8px; border: 1px solid #e5e7eb; margin-bottom: 4px;">
                        <span style="font-size: 0.8rem; color: #6b7280;">Subtotal:</span>
                        <span style="font-size: 0.8rem; font-weight: 600;">&#8377;${Number(subtotalAmount).toFixed(2)}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; align-items: center; background: #f9fafb; padding: 8px 12px; border-radius: 8px; border: 1px solid #e5e7eb; margin-bottom: 4px;">
                        <span style="font-size: 0.8rem; color: #6b7280;">Delivery:</span>
                        <span style="font-size: 0.8rem; font-weight: 600;">&#8377;${Number(deliveryFee).toFixed(2)}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; align-items: center; background: #e0f2fe; padding: 8px 12px; border-radius: 8px; border: 1px solid #0ea5e9;">
                        <span style="font-size: 0.9rem; font-weight: 600; color: #0369a1;">Total Amount:</span>
                        <span style="font-size: 1.1rem; font-weight: 800; color: #0369a1;">&#8377;${formattedAmount}</span>
                    </div>
                </div>
                <p class="subtitle">Complete your payment securely</p>
            </div>
            

            
            <div class="qr-wrapper">
                <div class="scan-anim" id="scanLine"></div>
                <!-- Using QuickChart API for better reliability, with fallback to static image -->
                <img src="https://quickchart.io/qr?text=${encodeURIComponent(upiLink)}&size=400&margin=1&ecLevel=L" 
                     alt="Scan to Pay" 
                     class="qr-image" 
                     id="qrcode"
                     onclick="copyUPI()">
            </div>
            
            <div style="text-align: center; margin-bottom: 12px;">
                <span style="font-size: 0.9rem; font-weight: 600; color: #374151; background: #f9fafb; padding: 4px 12px; border-radius: 8px; border: 1px solid #e5e7eb;">
                    Bangkokmart
                </span>
            </div>

            <div style="background: #f3f4f6; padding: 8px 12px; border-radius: 10px; margin-bottom: 12px; display: flex; align-items: center; justify-content: space-between;">
                <div style="text-align: left; overflow: hidden;">
                    <span style="font-size: 0.7rem; color: #6b7280; display: block;">UPI ID</span>
                    <span style="font-weight: 600; font-size: 0.85rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block; max-width: 180px;" id="upiIdDisplay">${upiId}</span>
                </div>
                <button onclick="copyUpiId()" style="background: white; border: 1px solid #d1d5db; padding: 4px 8px; border-radius: 6px; font-size: 0.75rem; font-weight: 600; color: #4b5563; cursor: pointer;">
                    Copy
                </button>
            </div>

            <p style="font-size: 0.8rem; color: #6b7280; margin-bottom: 5px;">
                Scan with any UPI App<br>
                <span style="font-size: 0.7rem; opacity: 0.7;">(GPay, PhonePe, Paytm, etc.)</span>
            </p>
            
            <!-- Payment Instruction -->
            <div style="background: #fef3c7; border: 1px solid #f59e0b; padding: 10px; border-radius: 8px; margin-bottom: 10px;">
                <p style="font-size: 0.8rem; color: #92400e; margin: 0; text-align: center; font-weight: 600;">
                    📸 After payment done, share screenshot for confirmation
                </p>
            </div>
        </div>

        <div id="successOverlay" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: white; z-index: 1000; flex-direction: column; justify-content: center; align-items: center; text-align: center;">
            <div style="width: 80px; height: 80px; background: #d1fae5; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin-bottom: 20px; animation: popIn 0.5s ease;">
                <svg width="50" height="50" viewBox="0 0 24 24" fill="none" stroke="#059669" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="20 6 9 17 4 12"></polyline>
                </svg>
            </div>
            <h1 style="font-size: 1.8rem; color: #065f46; margin-bottom: 10px;">Payment Successful!</h1>
            <p style="color: #4b5563; font-size: 1rem;">ORDER #${orderId} Confirmed</p>
            <p style="margin-top: 5px; font-weight: 700; font-size: 1.2rem;">&#8377;${formattedAmount}</p>
            
            <button onclick="window.close()" style="margin-top: 30px; padding: 12px 24px; background: #059669; color: white; border: none; border-radius: 12px; font-weight: 600; cursor: pointer;">
                Close
            </button>
        </div>

        <style>
            @keyframes pulse {
                0% { box-shadow: 0 0 0 0 rgba(79, 70, 229, 0.7); }
                70% { box-shadow: 0 0 0 10px rgba(79, 70, 229, 0); }
                100% { box-shadow: 0 0 0 0 rgba(79, 70, 229, 0); }
            }
            @keyframes popIn {
                0% { transform: scale(0); opacity: 0; }
                80% { transform: scale(1.1); opacity: 1; }
                100% { transform: scale(1); }
            }
        </style>

        <script>
            // Server-side variables injected
            const orderId = "${orderId}";
            const orderParam = "${orderParam}"; // Keep original parameter for status checking
            const upiLink = "${upiLink}";
            
            // UI elements
            const statusEl = document.getElementById('status');
            const statusText = document.getElementById('statusText');
            const statusIcon = document.getElementById('statusIcon');
            


            function setStatus(state) {
                if (!statusEl) return;
                statusEl.className = 'status-indicator';
                if (state === 'paid') {
                    // Show Full Screen Success
                    const overlay = document.getElementById('successOverlay');
                    if(overlay) {
                        overlay.style.display = 'flex';
                    }
                    
                    statusEl.classList.add('status-success');
                    if (statusText) statusText.textContent = 'Payment Received!';
                    // SVG Checkmark
                    if (statusIcon) statusIcon.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"></polyline></svg>';
                    
                    const scanLine = document.getElementById('scanLine');
                    if (scanLine) scanLine.style.display = 'none';

                    
                } else if (state === 'expired') {
                    statusEl.classList.add('status-expired');
                    if (statusText) statusText.textContent = 'Link Expired';
                    // SVG Alert Triangle
                    if (statusIcon) statusIcon.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg>';
                } else {
                    statusEl.classList.add('status-pending');
                }
            }

            function checkStatus() {
                // Poll for status using the original parameter (could be obfuscated)
                fetch('/api/whatsapp/check-payment-status/' + orderParam)
                    .then(res => res.json())
                    .then(data => {
                        if (data.paid) setStatus('paid');
                    })
                    .catch(e => console.error(e));
            }

            // Poll every 3 seconds
            setInterval(checkStatus, 3000);

            // --- Actions ---
            function confirmOnWhatsApp() {
                const adminPhone = '919654394183';
                const message = 'Hello Admin, I have made the payment for Order #' + orderId + '. Please find the attached screenshot for verification. Thank you!';
                
                // Directly open WhatsApp without updating database
                const whatsappUrl = 'https://wa.me/' + adminPhone + '?text=' + encodeURIComponent(message);
                window.location.href = whatsappUrl;
            }




            function copyUPI() {
                // Copy the deep link itself if clicked
                navigator.clipboard.writeText(upiLink).then(() => {
                    alert('UPI Link copied!');
                });
            }

            function copyUpiId() {
                // Copy just the UPI ID string
                const idText = document.getElementById('upiIdDisplay').innerText;
                navigator.clipboard.writeText(idText).then(() => {
                    const btn = event.target; // Simple way to get button
                    const originalText = btn.innerText;
                    btn.innerText = 'Copied!';
                    setTimeout(() => btn.innerText = originalText, 2000);
                }).catch(err => {
                    console.error('Failed to copy: ', err);
                });
            }
        </script>
    </body>
    </html>
    `;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(html);

  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Route: Check Payment Status
router.get('/check-payment-status/:orderParam', async (req, res) => {
  try {
    const { orderParam } = req.params;
    
    // Extract actual order ID from parameter (handles both direct IDs and obfuscated tokens)
    const orderId = PaymentUrlObfuscator.getOrderIdFromParam(orderParam);
    
    if (!orderId) {
      console.error(`[CheckPaymentStatus] Invalid order parameter: ${orderParam}`);
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid order parameter',
        error: 'Could not extract order ID from parameter'
      });
    }

    // Check database for actual payment status
    const [rows] = await pool.execute(
      'SELECT payment_status FROM orders WHERE id = ?',
      [orderId]
    );

    let isPaid = false;
    if (rows.length > 0) {
      // Check for 'paid' or 'success' or 'completed' to be safe, though 'paid' is standard here
      const status = rows[0].payment_status ? rows[0].payment_status.toLowerCase() : '';
      isPaid = (status === 'paid' || status === 'success' || status === 'completed');
    }

    res.json({
      orderId: orderId,
      paid: isPaid,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Error checking payment status:', error);
    res.status(500).json({ error: error.message });
  }
});

// Route: Mark Payment as Success (For manual confirmation or testing)
router.post('/payment-success/:orderParam', async (req, res) => {
  try {
    const { orderParam } = req.params;
    
    // Extract actual order ID from parameter (handles both direct IDs and obfuscated tokens)
    const orderId = PaymentUrlObfuscator.getOrderIdFromParam(orderParam);
    
    if (!orderId) {
      console.error(`[PaymentSuccess] Invalid order parameter: ${orderParam}`);
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid order parameter',
        error: 'Could not extract order ID from parameter'
      });
    }

    // Update order status to Processing and payment to Paid
    await pool.execute(
      "UPDATE orders SET payment_status = 'Paid', order_status = 'Processing', payment_method = 'UPI' WHERE id = ?",
      [orderId]
    );

    console.log(`[Payment] Order #${orderId} marked as Paid manually.`);
    res.json({ success: true, message: 'Updated successfully' });
  } catch (error) {
    console.error('Error updating payment:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
