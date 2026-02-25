const { sendFcmNotification } = require('../../backup');

class MarketplaceNotificationService {
  static async sendNotificationToBuyer(chatRoom, sellerMessage, sellerId) {
    try {
      console.log('🔔 Sending notification to buyer for chat room:', chatRoom.id);
      console.log('🔍 Chat room data:', chatRoom);
      console.log('🔍 Product ID:', chatRoom.product_id);
      
      // Get buyer's FCM token and name from database
      const getBuyerQuery = `
        SELECT name, fcm_token FROM users 
        WHERE user_id = ? AND fcm_token IS NOT NULL AND fcm_token != ''
      `;
      
      const [buyerResults] = await global.pool.execute(getBuyerQuery, [chatRoom.buyer_id]);
      
      if (buyerResults.length === 0) {
        console.log('❌ No FCM token found for buyer:', chatRoom.buyer_id);
        return;
      }
      
      const buyerFcmToken = buyerResults[0].fcm_token;
      const buyerName = buyerResults[0].name || 'Buyer';
      
      // Get seller info
      const getSellerQuery = `
        SELECT name FROM users 
        WHERE user_id = ?
      `;
      
      const [sellerResults] = await global.pool.execute(getSellerQuery, [sellerId]);
      const sellerName = sellerResults[0]?.name || 'Seller';
      
      // Get product info if available
      let productInfo = null;
      if (chatRoom.product_id && chatRoom.product_id > 0) {
        console.log('🔍 Fetching product info for ID:', chatRoom.product_id);
        const getProductQuery = `
          SELECT id, name, price, images, description, status, category, subcategory, 
                 available_qty, images, variations, sizes, attributes, selected_attribute_values,
                 price_slabs, marketplace_enabled, stock_mode, stock_by_color_size, instagram_url,
                 user_id, created_at, updated_at
          FROM products 
            WHERE id = ?
        `;
        
        const [productResults] = await global.pool.execute(getProductQuery, [chatRoom.product_id]);
        if (productResults.length > 0) {
          const product = productResults[0];
          productInfo = {
            id: product.id,
            name: product.name,
            price: product.price,
            images: product.images ? JSON.parse(product.images) : [],
            description: product.description,
            status: product.status,
            category: product.category,
            subcategory: product.subcategory,
            availableQty: product.available_qty,
            variations: product.variations ? JSON.parse(product.variations) : [],
            sizes: product.sizes ? JSON.parse(product.sizes) : [],
            attributes: product.attributes ? JSON.parse(product.attributes) : {},
            selectedAttributeValues: product.selected_attribute_values ? JSON.parse(product.selected_attribute_values) : {},
            priceSlabs: product.price_slabs ? JSON.parse(product.price_slabs) : [],
            marketplaceEnabled: product.marketplace_enabled,
            stockMode: product.stock_mode,
            stockByColorSize: product.stock_by_color_size ? JSON.parse(product.stock_by_color_size) : {},
            instagramUrl: product.instagram_url,
            sellerName: sellerName,
            userId: product.user_id,
            createdAt: product.created_at,
            updatedAt: product.updated_at
          };
          console.log('✅ Product info loaded for buyer notification:', productInfo);
        } else {
          console.log('⚠️ No product found for ID:', chatRoom.product_id);
        }
      } else {
        console.log('⚠️ No product ID in chat room or product_id is null/zero');
      }
      
      // Send FCM notification to buyer
      const notificationTitle = productInfo 
        ? `New message from ${sellerName} about ${productInfo.name}`
        : `New message from ${sellerName}`;
        
      await sendFcmNotification(
        buyerFcmToken,
        notificationTitle,
        sellerMessage.length > 50 ? sellerMessage.substring(0, 50) + '...' : sellerMessage,
        {
          type: 'new_chat_message',
          chatRoomId: chatRoom.id,
          senderId: sellerId,
          senderName: sellerName,
          productInfo: productInfo ? JSON.stringify(productInfo) : null
        }
      );
      
    } catch (error) {
      console.error('❌ Error sending notification to buyer:', error);
    }
  }
  
  static async sendNotificationToSeller(chatRoom, buyerMessage, buyerId) {
    try {
      console.log('🔔 Sending notification to seller for chat room:', chatRoom.id);
      
      // Get seller's FCM token and name from database
      const getSellerTokenQuery = `
        SELECT name, fcm_token FROM users 
        WHERE user_id = ? AND fcm_token IS NOT NULL AND fcm_token != ''
      `;
      
      const [sellerResults] = await global.pool.execute(getSellerTokenQuery, [chatRoom.seller_id]);
      
      if (sellerResults.length === 0) {
        console.log('❌ No FCM token found for seller:', chatRoom.seller_id);
        return;
      }
      
      const sellerFcmToken = sellerResults[0].fcm_token;
      const sellerName = sellerResults[0].name || 'Seller';
      
      // Get buyer info
      const getBuyerQuery = `
        SELECT name FROM users 
        WHERE user_id = ?
      `;
      
      const [buyerResults] = await global.pool.execute(getBuyerQuery, [buyerId]);
      const buyerName = buyerResults[0]?.name || 'Buyer';
      
      // Get product info if available
      let productInfo = null;
      if (chatRoom.product_id && chatRoom.product_id > 0) {
        const getProductQuery = `
          SELECT id, name, price, images FROM products 
            WHERE id = ?
        `;
        
        const [productResults] = await global.pool.execute(getProductQuery, [chatRoom.product_id]);
        if (productResults.length > 0) {
          const product = productResults[0];
          productInfo = {
            id: product.id,
            name: product.name,
            price: product.price,
            images: product.images ? JSON.parse(product.images) : [],
            userId: chatRoom.seller_id // Seller is the product owner
          };
          console.log('✅ Product info loaded for seller notification:', productInfo);
        } else {
          console.log('⚠️ No product found for ID:', chatRoom.product_id);
        }
      }
      
      // Send FCM notification to seller
      const notificationTitle = productInfo 
        ? `New message from ${buyerName} about ${productInfo.name}`
        : `New message from ${buyerName}`;
        
      await sendFcmNotification(
        sellerFcmToken,
        notificationTitle,
        buyerMessage.length > 50 ? buyerMessage.substring(0, 50) + '...' : buyerMessage,
        {
          type: 'new_chat_message',
          chatRoomId: chatRoom.id,
          senderId: buyerId,
          senderName: buyerName,
          productInfo: productInfo ? JSON.stringify(productInfo) : null
        }
      );
      
    } catch (error) {
      console.error('❌ Error sending notification to seller:', error);
    }
  }
}

module.exports = MarketplaceNotificationService;
