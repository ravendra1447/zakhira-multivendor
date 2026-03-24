// ----------------- CHAT MARKETPLACE HELPER FUNCTIONS -----------------

const path = require('path');

// Helper functions for marketplace chat
async function updateOnlineStatus(pool, userId, isOnline) {
  try {
    await pool.execute(
      'UPDATE chat_participants SET is_online = ?, last_seen_at = ? WHERE user_id = ?',
      [isOnline, isOnline ? null : new Date(), userId]
    );
  } catch (error) {
    console.error('Error updating online status:', error);
  }
}

async function updateLastReadMessage(pool, chatRoomId, userId, messageId) {
  try {
    await pool.execute(
      'INSERT INTO chat_participants (chat_room_id, user_id, last_read_message_id) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE last_read_message_id = ?',
      [chatRoomId, userId, messageId, messageId]
    );
  } catch (error) {
    console.error('Error updating last read message:', error);
  }
}

// Marketplace chat socket event handlers
function setupMarketplaceSocket(io, pool) {
  io.on("connection", (socket) => {
    // ----------------- CHAT MARKETPLACE SOCKET EVENTS -----------------
    
    // Handle user registration (consistent with main server)
    socket.on('register', async (userId) => {
      console.log(`📝 Registering marketplace user: ${userId} for socket: ${socket.id}`);
      
      if (!userId) {
        console.warn("⚠️ Marketplace registration failed: userId is null or undefined.");
        return;
      }

      // Set userId for both marketplace and main server compatibility
      socket.userId = userId;
      socket.data.userId = userId; // For main server compatibility
      
      try {
        // Update online status
        await updateOnlineStatus(pool, userId, true);
        
        // Join user to their personal room for notifications
        socket.join(`user_${userId}`);
        socket.join(`user:${userId}`); // Main server room format
        
        console.log(`✅ Marketplace user ${userId} registered successfully`);
        
      } catch (error) {
        console.error('Error in marketplace register:', error);
        socket.emit('error', { message: 'Failed to register marketplace chat' });
      }
    });
    
    // User joins with their user ID for marketplace chat (legacy support)
    socket.on('user_join', async (data) => {
      const { userId } = data;
      
      // Set userId for both marketplace and main server compatibility
      socket.userId = userId;
      socket.data.userId = userId; // For main server compatibility
      
      try {
        // Update online status
        await updateOnlineStatus(pool, userId, true);
        
        // Join user to their personal room for notifications
        socket.join(`user_${userId}`);
        socket.join(`user:${userId}`); // Main server room format
        
        console.log(`?? User ${userId} joined marketplace chat`);
        
      } catch (error) {
        console.error('Error in user_join:', error);
        socket.emit('error', { message: 'Failed to join chat' });
      }
    });

    // Join marketplace chat room
    socket.on('join_chat_room', async (data) => {
      try {
        const { chatRoomId, userId } = data;
        console.log(`🚪 User ${userId} attempting to join chat room ${chatRoomId}`);
        console.log(`🔍 Data received:`, data);

        // First, ensure user is added as participant (fix for real-time messaging)
        await pool.execute(
          'INSERT INTO chat_participants (chat_room_id, user_id, last_active_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE last_active_at = ?',
          [chatRoomId, userId, new Date(), new Date()]
        );

        // Verify user is participant in this chat room
        const [participants] = await pool.execute(
          'SELECT * FROM chat_participants WHERE chat_room_id = ? AND user_id = ?',
          [chatRoomId, userId]
        );

        console.log(`🔍 Participants found: ${participants.length}`);

        if (participants.length === 0) {
          console.log(`❌ User ${userId} not authorized for room ${chatRoomId}`);
          socket.emit('error', { message: 'Not authorized to join this chat room' });
          return;
        }

        // Join socket room
        socket.join(`chat_room_${chatRoomId}`);
        socket.currentChatRoom = chatRoomId;
        
        console.log(`✅ User ${userId} joined chat room ${chatRoomId}`);
        
        // Emit confirmation to client
        const responseData = {
          chatRoomId: chatRoomId,
          userId: userId
        };
        console.log(`📤 Emitting joined_chat_room:`, responseData);
        socket.emit('joined_chat_room', responseData);
        
      } catch (error) {
        console.error('Error joining chat room:', error);
        socket.emit('error', { message: 'Failed to join chat room' });
      }
    });

    // Send marketplace chat message
    socket.on('send_message', async (data) => {
      const { chatRoomId, senderId, messageContent, messageType = 'text', productInfo = null, attachments = [] } = data;
      
      console.log('?? Processing marketplace message:', { chatRoomId, senderId, messageContent, messageType, productInfo, attachments: attachments.length });
      
      try {
        // Verify sender is participant in this chat room
        const [participants] = await pool.execute(
          'SELECT * FROM chat_participants WHERE chat_room_id = ? AND user_id = ?',
          [chatRoomId, senderId]
        );

        console.log('?? Participants check:', participants.length);

        if (participants.length === 0) {
          console.log('? User not authorized for chat room');
          socket.emit('error', { message: 'Not authorized to send message in this chat room' });
          return;
        }

        // Get product info if not provided
        let finalProductInfo = productInfo;
        if (!finalProductInfo) {
          console.log('🔍 Product info not provided, fetching from chat room...');
          const [chatRoomInfo] = await pool.execute(
            'SELECT product_id FROM chat_rooms WHERE id = ?',
            [chatRoomId]
          );
          
          console.log('🔍 Chat room info:', chatRoomInfo);
          
          if (chatRoomInfo.length > 0 && chatRoomInfo[0].product_id) {
            console.log('🔍 Fetching product for ID:', chatRoomInfo[0].product_id);
            const [productData] = await pool.execute(
              'SELECT id, name, price, images, description, status, category, subcategory, ' +
                     'available_qty, variations, sizes, attributes, selected_attribute_values, ' +
                     'price_slabs, marketplace_enabled, stock_mode, stock_by_color_size, ' +
                     'user_id, created_at, updated_at ' +
              'FROM products WHERE id = ?',
              [chatRoomInfo[0].product_id]
            );
            
            console.log('🔍 Product data result:', productData.length, 'items');
            
            if (productData.length > 0) {
              const product = productData[0];
              finalProductInfo = {
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
                userId: product.user_id,
                createdAt: product.created_at,
                updatedAt: product.updated_at
              };
              console.log('✅ Product info fetched for message:', finalProductInfo.name);
            } else {
              console.log('❌ No product found for ID:', chatRoomInfo[0].product_id);
            }
          } else {
            console.log('❌ No product_id found in chat room:', chatRoomId);
          }
        } else {
          console.log('✅ Using provided product info:', productInfo);
        }

        // Generate encryption key for this message
        const encryption = require(path.join(__dirname, '..', '..', 'utils', 'encryption'));
        const encryptionKey = encryption.generateKey();
        
        // Encrypt and compress the message content
        const encryptedContent = encryption.compressAndEncrypt(messageContent, encryptionKey);

        const now = new Date();

        console.log('?? Inserting message into database...');

        // Insert encrypted message into database
        const [result] = await pool.execute(
          'INSERT INTO chat_messages (chat_room_id, sender_id, message_type, message_content, encrypted_content, product_info, encryption_key, is_delivered, delivery_time) VALUES (?, ?, ?, ?, ?, ?, ?, TRUE, ?)',
          [chatRoomId, senderId, messageType, messageContent, encryptedContent, productInfo ? JSON.stringify(productInfo) : null, encryptionKey, now]
        );

        const messageId = result.insertId;
        console.log('? Message inserted with ID:', messageId);

        // Save attachments if any
        if (attachments && attachments.length > 0) {
          console.log('?? Saving attachments:', attachments.length);
          console.log('?? Attachment data:', JSON.stringify(attachments, null, 2));
          for (const attachment of attachments) {
            try {
              console.log('?? Processing attachment:', {
                fileName: attachment.fileName,
                filePath: attachment.filePath,
                fileSize: attachment.fileSize,
                fileType: attachment.fileType,
                thumbnailPath: attachment.thumbnailPath
              });
              
              await pool.execute(
                'INSERT INTO chat_message_attachments (message_id, file_name, file_path, file_size, file_type, thumbnail_path) VALUES (?, ?, ?, ?, ?, ?)',
                [messageId, attachment.fileName, attachment.filePath, attachment.fileSize, attachment.fileType, attachment.thumbnailPath || null]
              );
              console.log('?? Attachment saved:', attachment.fileName);
            } catch (attachmentError) {
              console.error('?? Error saving attachment:', attachmentError);
              console.error('?? Attachment error details:', {
                messageId: messageId,
                attachment: attachment,
                error: attachmentError.message
              });
            }
          }
        } else {
          console.log('?? No attachments to save');
        }

        // Get message details with sender info (without encrypted content)
        const [messageData] = await pool.execute(`
          SELECT m.id, m.chat_room_id, m.sender_id, m.message_type, m.message_content, m.product_info, m.is_read, m.is_delivered, m.delivery_time, m.created_at, m.updated_at,
                 u.name as sender_name, '' as sender_avatar
          FROM chat_messages m
          JOIN users u ON m.sender_id = u.user_id
          WHERE m.id = ?
        `, [messageId]);

        const message = messageData[0];
        
        // Get attachments for this message
        if (attachments && attachments.length > 0) {
          const [attachmentData] = await pool.execute(
            'SELECT * FROM chat_message_attachments WHERE message_id = ?',
            [messageId]
          );
          message.attachments = attachmentData;
        }
        
        console.log('?? Broadcasting message to room:', `chat_room_${chatRoomId}`);

        // Mark sender as active in this chat
        await pool.execute(
          'INSERT INTO chat_participants (chat_room_id, user_id, last_active_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE last_active_at = ?',
          [chatRoomId, senderId, now, now]
        );

        // Broadcast message to all participants in the room (without encryption key)
        io.to(`chat_room_${chatRoomId}`).emit('new_message', message);

        // Get chat room info to determine buyer and seller
        console.log('?? Getting chat room info for notification...');
        const [chatRoomInfo] = await pool.execute(
          'SELECT buyer_id, seller_id FROM chat_rooms WHERE id = ?',
          [chatRoomId]
        );
        
        console.log('?? Chat room info:', chatRoomInfo);
        
        if (chatRoomInfo.length > 0) {
          const { buyer_id, seller_id } = chatRoomInfo[0];
          
          // Determine who should receive notification (the person who didn't send the message)
          const recipientId = senderId === buyer_id ? seller_id : buyer_id;
          const recipientType = senderId === buyer_id ? 'seller' : 'buyer';
          
          console.log(`?? Sending notification to ${recipientType} (${recipientId})`);
          console.log(`?? Sender: ${senderId}, Buyer: ${buyer_id}, Seller: ${seller_id}`);
          
          // Check if recipient is online
          const recipientSockets = await io.in(`user:${recipientId}`).fetchSockets();
          console.log(`?? ${recipientType.charAt(0).toUpperCase() + recipientType.slice(1)} ${recipientId} has ${recipientSockets.length} active sockets`);
          
          // Send socket notification
          console.log('?? Sending socket notification...');
          io.to(`user:${recipientId}`).emit('new_chat_notification', {
            type: 'new_message',
            chatRoomId: chatRoomId,
            senderId: senderId,
            message: messageContent,
            productInfo: finalProductInfo,
            timestamp: now
          });
          console.log('?? Socket notification sent!');
          
          // Send FCM notification (push notification)
          try {
            // Initialize Firebase Admin with Google Services credentials
            const admin = require('firebase-admin');
            if (!admin.apps.length) {
              try {
                // Use Google Services JSON instead of Service Account
                const serviceAccount = {
                  "type": "service_account",
                  "project_id": "chatapp-4e2d5",
                  "private_key_id": "your-private-key-id",
                  "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n",
                  "client_email": "firebase-adminsdk-xxxxx@chatapp-4e2d5.iam.gserviceaccount.com",
                  "client_id": "your-client-id",
                  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                  "token_uri": "https://oauth2.googleapis.com/token",
                  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
                  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-xxxxx%40chatapp-4e2d5.iam.gserviceaccount.com"
                };
                
                admin.initializeApp({
                  credential: admin.credential.cert(serviceAccount)
                });
                console.log('? Firebase Admin initialized in chatHelpers');
              } catch (error) {
                console.error('? Firebase Admin initialization failed:', error);
                console.log('?? Running without FCM notifications');
                return;
              }
            }
            
            // Use the existing pool instead of creating new connection
            const [users] = await pool.execute(`
              SELECT name, email, normalized_phone, fcm_token
              FROM users 
              WHERE user_id = ?
            `, [recipientId]);

            if (users.length > 0) {
              const recipient = users[0];
              console.log(`?? ${recipientType.charAt(0).toUpperCase() + recipientType.slice(1)} found:`, recipient.name, 'FCM Token:', recipient.fcm_token ? 'YES' : 'NO');
              
              // Send FCM notification directly
              if (recipient.fcm_token) {
                if (admin.apps.length > 0) {
                  const title = finalProductInfo ? `New message about ${finalProductInfo.product_name || finalProductInfo.name || 'Product'}` : 'New Message';
                  const body = messageContent;
                  
                  console.log('🔔 Creating FCM notification:');
                  console.log('  finalProductInfo exists:', !!finalProductInfo);
                  console.log('  finalProductInfo.name:', finalProductInfo?.name);
                  console.log('  title:', title);
                  console.log('  body:', body);
                  console.log('  recipient:', recipient.name);
                  console.log('  recipientId:', recipientId);
                  console.log('  chatRoomId:', chatRoomId);
                  console.log('  senderId:', senderId);
                  
                  const chatRoomIdStr = chatRoomId.toString();
                  const senderIdStr = senderId.toString();
                  const productInfoStr = JSON.stringify(finalProductInfo);
                  
                  console.log('🔔 FCM Data types:');
                  console.log('  chatRoomId:', typeof chatRoomIdStr, chatRoomIdStr);
                  console.log('  senderId:', typeof senderIdStr, senderIdStr);
                  console.log('  productInfo:', typeof productInfoStr, productInfoStr);
                  
                  const message = {
                    notification: {
                      title: title,
                      body: body,
                    },
                    android: {
                      notification: {
                        sound: 'default',
                        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                        priority: 'high',
                      },
                    },
                    apns: {
                      payload: {
                        aps: {
                          sound: 'default',
                          badge: 1,
                        },
                      },
                    },
                    data: {
                      type: 'new_chat_message',
                      chatRoomId: chatRoomIdStr,
                      senderId: senderIdStr,
                      productInfo: productInfoStr
                    },
                    token: recipient.fcm_token,
                  };

                  const response = await admin.messaging().send(message);
                  console.log(`?? FCM notification sent to ${recipientType}:`, recipientId);
                  console.log('?? FCM Response:', response);
                } else {
                  console.log('?? Firebase Admin not initialized');
                }
              } else {
                console.log(`?? ${recipientType.charAt(0).toUpperCase() + recipientType.slice(1)} has no FCM token`);
              }
            } else {
              console.log(`?? ${recipientType.charAt(0).toUpperCase() + recipientType.slice(1)} not found`);
            }
            
          } catch (fcmError) {
            console.log('?? FCM notification failed:', fcmError.message);
          }
          
          console.log(`?? Sent notification to ${recipientType}:`, recipientId);
          console.log('?? Notification data:', {
            type: 'new_message',
            chatRoomId: chatRoomId,
            senderId: senderId,
            message: messageContent,
            productInfo: finalProductInfo
          });
        }

        // Update last read for sender
        await updateLastReadMessage(pool, chatRoomId, senderId, messageId);

      } catch (error) {
        console.error('? Error sending message:', error);
        socket.emit('error', { message: 'Failed to send message' });
      }
    });

    // Mark messages as read
    socket.on('mark_messages_read', async (data) => {
      const { chatRoomId, userId, messageId } = data;
      
      try {
        const now = new Date();
        
        // Update messages as read with read time
        await pool.execute(
          'UPDATE chat_messages SET is_read = TRUE, read_time = ? WHERE chat_room_id = ? AND sender_id != ? AND id <= ?',
          [now, chatRoomId, userId, messageId]
        );

        // Update last read for user and mark as active
        await pool.execute(
          'INSERT INTO chat_participants (chat_room_id, user_id, last_read_message_id, last_active_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE last_read_message_id = ?, last_active_at = ?',
          [chatRoomId, userId, messageId, now, messageId, now]
        );

        // Get updated unread count
        const [unreadCount] = await pool.execute(
          'SELECT COUNT(*) as count FROM chat_messages WHERE chat_room_id = ? AND sender_id != ? AND is_read = FALSE',
          [chatRoomId, userId]
        );

        socket.emit('messages_read', { 
          readTime: now,
          unreadCount: unreadCount[0].count
        });

      } catch (error) {
        console.error('Error marking messages as read:', error);
        socket.emit('error', { message: 'Failed to mark messages as read' });
      }
    });

    // Get marketplace chat history
    socket.on('get_chat_history', async (data) => {
      const { chatRoomId, userId, limit = 50, offset = 0 } = data;
      
      // Validate and convert parameters
      const chatRoomIdNum = parseInt(chatRoomId);
      const userIdNum = parseInt(userId);
      const limitNum = parseInt(limit) || 50;
      const offsetNum = parseInt(offset) || 0;
      
      console.log('📜 Getting chat history:', { chatRoomId: chatRoomIdNum, userId: userIdNum, limit: limitNum, offset: offsetNum });
      
      try {
        // Verify user is participant
        const [participants] = await pool.execute(
          'SELECT * FROM chat_participants WHERE chat_room_id = ? AND user_id = ?',
          [chatRoomIdNum, userIdNum]
        );

        if (participants.length === 0) {
          socket.emit('error', { message: 'Not authorized to view this chat history' });
          return;
        }

        // Get messages with encrypted content
        let messages;
        
        try {
          // Use JOIN query with literal values (working solution)
          console.log('🧪 Testing query with JOIN...');
          const [joinMessages] = await pool.execute(
            `SELECT m.*, u.name as sender_name, '' as sender_avatar
            FROM chat_messages m
            JOIN users u ON m.sender_id = u.user_id
            WHERE m.chat_room_id = ${chatRoomIdNum}
            ORDER BY m.created_at DESC
            LIMIT ${limitNum} OFFSET ${offsetNum}`
          );
          
          // Get attachments for all messages
          for (const message of joinMessages) {
            const [attachmentData] = await pool.execute(
              'SELECT * FROM chat_message_attachments WHERE message_id = ?',
              [message.id]
            );
            message.attachments = attachmentData;
          }
          
          messages = joinMessages;
          console.log('✅ JOIN query successful, got', messages.length, 'messages with attachments');
        } catch (joinErr) {
          console.log('❌ JOIN query failed, using fallback:', joinErr.message);
          // Fallback: try without user info
          const [fallbackMessages] = await pool.execute(
            `SELECT * FROM chat_messages WHERE chat_room_id = ${chatRoomIdNum} ORDER BY created_at DESC LIMIT ${limitNum} OFFSET ${offsetNum}`
          );
          messages = fallbackMessages;
          console.log('⚠️ Using fallback query without user info, got', messages.length, 'messages');
        }

        // Decrypt messages before sending
        const encryption = require(path.join(__dirname, '..', '..', 'utils', 'encryption'));
        const decryptedMessages = messages.map(message => {
          try {
            const decryptedContent = encryption.decryptAndDecompress(
              message.encrypted_content, 
              message.encryption_key
            );
            
            return {
              ...message,
              message_content: decryptedContent,
              encrypted_content: undefined, // Don't send encrypted content to client
              encryption_key: undefined // Don't send encryption key to client
            };
          } catch (error) {
            console.error('Error decrypting message:', error);
            return {
              ...message,
              message_content: '[Decryption Error]',
              encrypted_content: undefined,
              encryption_key: undefined
            };
          }
        });

        socket.emit('chat_history', { messages: decryptedMessages.reverse() });

      } catch (error) {
        console.error('Error getting chat history:', error);
        socket.emit('error', { message: 'Failed to get chat history' });
      }
    });

    // Handle marketplace chat user disconnect
    socket.on("disconnect", () => {
      // Get userId from both sources for compatibility
      const userId = socket.userId || socket.data?.userId;
      console.log(`🔌 Marketplace socket disconnected: ${socket.id}. User ID: ${userId}`);
      
      if (userId) {
        updateOnlineStatus(pool, userId, false).catch(err => {
          console.error('Error updating online status on marketplace disconnect:', err);
        });
        console.log(`❌ Marketplace user ${userId} disconnected and marked as offline`);
      } else {
        console.log(`⚠️ Marketplace socket disconnected but no userId was set`);
      }
    });
  });
}

module.exports = {
  setupMarketplaceSocket,
  updateOnlineStatus,
  updateLastReadMessage
};
