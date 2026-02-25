const express = require("express");
const router = express.Router();
const mysql = require("mysql2");
const admin = require("firebase-admin");

// ✅ Service Account JSON ka path
const serviceAccount = require("../chatapp-4e2d5-firebase-adminsdk-fbsvc-eaa32c50f3.json");

// ✅ Initialize Firebase Admin (agar already initialize nahi hua)
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

// ✅ MySQL Connection Pool
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
}).promise();

pool.query("SET time_zone = '+05:30'").then(() => {
  console.log("✅ Timezone set to IST");
}).catch(err => console.error("❌ Error setting timezone:", err));

// -------------------------------
// ✅ Helper: Send FCM Notification (Popup + Wakeup Supported)
// --------------------------------
async function sendFcmNotification(receiverId, encryptedText, chatId, senderId, senderName) {
  try {
    // 1️⃣ Receiver ka FCM token nikalna
    const [results] = await pool.query(
      "SELECT fcm_token FROM users WHERE user_id = ?",
      [receiverId]
    );
    const fcmToken = results[0]?.fcm_token;

    if (!fcmToken) {
      console.log(`❌ No FCM token found for user ID: ${receiverId}`);
      return;
    }

    // 2️⃣ Notification Payload
    const message = {
      notification: {
        title: senderName || "New Message",
        body: "You have a new message."
      },
      data: {
        message_text: encryptedText,
        chatId: String(chatId),
        senderId: String(senderId),
        is_chat_message: "true",
        click_action: "FLUTTER_NOTIFICATION_CLICK"  // 🔥 Required for background popup
      },
      token: fcmToken,
      android: {
        priority: "high",
        notification: {
          sound: "default",
          visibility: "public",
          priority: "max",         // 🔥 Heads-up popup ke liye
          channelId: "chat_messages", // 🔔 Android app me same channel banana hoga
          defaultSound: true
        }
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            alert: {
              title: senderName || "New Message",
              body: "You have a new message."
            },
            sound: "default"
          }
        }
      }
    };

    // 3️⃣ FCM Message Send
    const response = await admin.messaging().send(message);
    console.log("✅ Successfully sent FCM popup message:", response);

  } catch (err) {
    // Invalid token cleanup
    if (err.code === "messaging/registration-token-not-registered") {
      console.log(`❌ Removing invalid token for user ${receiverId}`);
      await pool.query(
        "UPDATE users SET fcm_token = NULL WHERE user_id = ?",
        [receiverId]
      );
    } else {
      console.error("❌ FCM send error:", err);
      throw err;
    }
  }
}

// -------------------------------
// 1️⃣ Check Backup
// -------------------------------
router.get("/check_backup", async (req, res) => {
  const userId = req.query.user_id;
  if (!userId) return res.status(400).json({ error: "user_id required" });

  try {
    const [results] = await pool.query(
      "SELECT COUNT(*) as total FROM messages WHERE sender_id=? OR receiver_id=?",
      [userId, userId]
    );
    const total = results[0].total;
    res.json({ has_backup: total > 0, total_messages: total });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 2️⃣ Restore Messages
// -------------------------------
router.get("/restore_messages", async (req, res) => {
  const userId = req.query.user_id;
  const limit = parseInt(req.query.limit) || 50;
  const offset = parseInt(req.query.offset) || 0;

  if (!userId) return res.status(400).json({ error: "user_id required" });

  try {
    const [results] = await pool.query(
      `SELECT message_id, chat_id, sender_id, receiver_id, message_type, 
              message_text, media_url, is_delivered, is_read, 
              is_deleted_sender, is_deleted_receiver, timestamp, 
              media_id, forwarded_from_id
       FROM messages
       WHERE sender_id=? OR receiver_id=? 
       ORDER BY timestamp DESC
       LIMIT ? OFFSET ?`,
      [userId, userId, limit, offset]
    );
    
    console.log(`✅ Restored ${results.length} messages for user ${userId}`);
    res.json({ messages: results });
  } catch (err) {
    console.error("❌ Error restoring messages:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 3️⃣ DELETE BACKUP API (NEW - Skip Button Ke Liye)
// -------------------------------
router.post("/delete_backup", async (req, res) => {
  const { user_id } = req.body;
  
  if (!user_id) {
    return res.status(400).json({ error: "user_id required" });
  }

  try {
    console.log(`🗑️ Starting backup deletion for user ${user_id}`);
    
    // 1️⃣ Pehle messages ko message_bin mein move karo
    const [moveResult] = await pool.query(
      `INSERT INTO message_bin 
       (message_id, sender_id, receiver_id, timestamp, deleted_by, deleted_at)
       SELECT message_id, sender_id, receiver_id, timestamp, 'both', NOW() 
       FROM messages 
       WHERE sender_id = ? OR receiver_id = ?`,
      [user_id, user_id]
    );

    console.log(`✅ Moved ${moveResult.affectedRows} messages to bin for user ${user_id}`);

    // 2️⃣ Phir messages delete karo
    const [deleteResult] = await pool.query(
      `DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?`,
      [user_id, user_id]
    );

    console.log(`✅ Deleted ${deleteResult.affectedRows} messages for user ${user_id}`);

    res.json({ 
      success: true, 
      message: "Backup deleted and moved to bin successfully",
      moved_to_bin: moveResult.affectedRows,
      deleted_messages: deleteResult.affectedRows
    });
    
  } catch (err) {
    console.error("❌ Error deleting backup:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 4️⃣ Delete Message (sender or receiver) with 1-minute delayed removal
// -------------------------------
router.post("/delete_message", async (req, res) => {
  const { messageId, userId, role } = req.body; // role = 'sender' or 'receiver'
  if (!messageId || !userId || !role) {
    return res.status(400).json({ error: "messageId, userId, and role are required" });
  }

  try {
    const updateField = role === "sender" ? "is_deleted_sender" : "is_deleted_receiver";

    // 1️⃣ Update messages table
    await pool.query(
      `UPDATE messages SET ${updateField} = 1 WHERE message_id = ?`,
      [messageId]
    );

    // 2️⃣ Get message details
    const [msg] = await pool.query("SELECT * FROM messages WHERE message_id = ?", [messageId]);
    if (msg.length === 0) return res.status(404).json({ error: "Message not found" });
    const message = msg[0];

    // 3️⃣ Check if message exists in bin
    const [binCheck] = await pool.query("SELECT * FROM message_bin WHERE message_id = ?", [messageId]);

    if (binCheck.length === 0) {
      // 🆕 Insert minimal data into bin
      await pool.query(
        `INSERT INTO message_bin 
          (message_id, sender_id, receiver_id, timestamp, deleted_by, deleted_at)
         VALUES (?, ?, ?, ?, ?, NOW())`,
        [
          message.message_id,
          message.sender_id,
          message.receiver_id,
          message.timestamp,
          role
        ]
      );
    } else {
      // 🔁 Update deleted_by if already exists
      let newDeletedBy = binCheck[0].deleted_by;
      if (newDeletedBy === "sender" && role === "receiver") newDeletedBy = "both";
      if (newDeletedBy === "receiver" && role === "sender") newDeletedBy = "both";

      await pool.query(
        "UPDATE message_bin SET deleted_by = ?, deleted_at = NOW() WHERE message_id = ?",
        [newDeletedBy, messageId]
      );
    }

    // 4️⃣ Schedule a check after 1 minute (auto-delete if both deleted)
    setTimeout(async () => {
      try {
        const [checkBin] = await pool.query(
          "SELECT deleted_by FROM message_bin WHERE message_id = ?",
          [messageId]
        );

        if (checkBin.length > 0 && checkBin[0].deleted_by === "both") {
          // Delete from both tables
          await pool.query("DELETE FROM messages WHERE message_id = ?", [messageId]);
          await pool.query("DELETE FROM message_bin WHERE message_id = ?", [messageId]);
          console.log(`🕒 Message ${messageId} deleted permanently after 1 minute`);
        }
      } catch (timerErr) {
        console.error("Timer delete error:", timerErr);
      }
    }, 60 * 1000); // 1 minute = 60000 ms

    res.json({ success: true, message: "Message deletion scheduled successfully." });

  } catch (err) {
    console.error("❌ Error deleting message:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 5️⃣ Save FCM Token
// -------------------------------
router.post("/save-fcm-token", async (req, res) => {
  const { userId, fcmToken } = req.body;
  if (!userId || !fcmToken) return res.status(400).json({ error: "Missing userId or fcmToken" });

  try {
    await pool.query("UPDATE users SET fcm_token = ? WHERE user_id = ?", [fcmToken, userId]);
    console.log(`✅ FCM token saved for user ${userId}`);
    res.json({ success: true, message: "FCM token saved successfully" });
  } catch (err) {
    console.error("❌ Error saving FCM token:", err);
    res.status(500).json({ error: err.message });
  }
});

// Add route with underscores for Flutter app compatibility
router.post("/save_fcm_token", async (req, res) => {
  const { userId, fcmToken } = req.body;
  if (!userId || !fcmToken) return res.status(400).json({ error: "Missing userId or fcmToken" });

  try {
    await pool.query("UPDATE users SET fcm_token = ? WHERE user_id = ?", [fcmToken, userId]);
    console.log(`✅ FCM token saved for user ${userId} (underscore route)`);
    res.json({ success: true, message: "FCM token saved successfully" });
  } catch (err) {
    console.error("❌ Error saving FCM token:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 6️⃣ Send FCM Notification via API (5 parameters)
// -------------------------------
router.post("/send-notification", async (req, res) => {
  const { receiverId, messageText, chatId, senderId, senderName } = req.body;

  if (!receiverId || !messageText || !chatId || !senderId || !senderName) {
    return res.status(400).json({ error: "Missing required fields (receiverId, messageText, chatId, senderId, senderName)" });
  }

  try {
    await sendFcmNotification(receiverId, messageText, chatId, senderId, senderName);
    res.json({ success: true, message: "Notification sent (if token exists)" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 7️⃣ Get Message Bin (Deleted Messages)
// -------------------------------
router.get("/message_bin", async (req, res) => {
  const userId = req.query.user_id;
  
  if (!userId) {
    return res.status(400).json({ error: "user_id required" });
  }

  try {
    const [results] = await pool.query(
      `SELECT mb.*, m.message_text, m.message_type, m.media_url
       FROM message_bin mb
       LEFT JOIN messages m ON mb.message_id = m.message_id
       WHERE mb.sender_id = ? OR mb.receiver_id = ?
       ORDER BY mb.deleted_at DESC`,
      [userId, userId]
    );
    
    res.json({ deleted_messages: results });
  } catch (err) {
    console.error("❌ Error fetching message bin:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 8️⃣ Permanent Delete from Bin
// -------------------------------
router.post("/permanent_delete", async (req, res) => {
  const { messageId } = req.body;
  
  if (!messageId) {
    return res.status(400).json({ error: "messageId required" });
  }

  try {
    // Delete from both tables
    await pool.query("DELETE FROM messages WHERE message_id = ?", [messageId]);
    await pool.query("DELETE FROM message_bin WHERE message_id = ?", [messageId]);
    
    res.json({ success: true, message: "Message permanently deleted" });
  } catch (err) {
    console.error("❌ Error permanent deleting:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 9️⃣ Restore from Bin
// -------------------------------
router.post("/restore_from_bin", async (req, res) => {
  const { messageId } = req.body;
  
  if (!messageId) {
    return res.status(400).json({ error: "messageId required" });
  }

  try {
    // Message bin se delete karo
    await pool.query("DELETE FROM message_bin WHERE message_id = ?", [messageId]);
    
    // Messages table mein flags reset karo
    await pool.query(
      "UPDATE messages SET is_deleted_sender = 0, is_deleted_receiver = 0 WHERE message_id = ?",
      [messageId]
    );
    
    res.json({ success: true, message: "Message restored successfully" });
  } catch (err) {
    console.error("❌ Error restoring from bin:", err);
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------
// 🔐 Health Check
// -------------------------------
router.get("/health", async (req, res) => {
  try {
    const [result] = await pool.query("SELECT 1 as healthy");
    res.json({ 
      status: "healthy", 
      database: "connected",
      timestamp: new Date().toISOString(),
      timezone: "IST"
    });
  } catch (err) {
    res.status(500).json({ 
      status: "unhealthy", 
      database: "disconnected",
      error: err.message 
    });
  }
});

// ✅ Export Router
module.exports = { router, sendFcmNotification };


