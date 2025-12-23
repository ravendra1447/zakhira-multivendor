// server/routes/media_route.js
const express = require("express");
const router = express.Router();
const multer = require("multer");
const sharp = require("sharp");
const fsp = require("fs/promises");
const path = require("path");
const { v4: uuidv4 } = require("uuid");
const crypto = require("crypto");
const axios = require("axios");
const fs = require("fs");

const UPLOAD_DIR = path.join(__dirname, "../uploads");
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const uploads = new Map();
const storage = multer.memoryStorage();

// ? FIXED MULTER CONFIGURATION - SEPARATE INSTANCES
const uploadChunk = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 } });
const uploadImage = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 } });

const PHP_API_BASE = process.env.PHP_API_BASE || "http://184.168.126.71/api";
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || "MySecureKey123!";

// ? BODY PARSER MIDDLEWARE - SPECIFIC ROUTES KE LIYE
router.use(express.json({ limit: "50mb" }));
router.use(express.urlencoded({ extended: true, limit: "50mb" }));

// ? IN-MEMORY STORAGE FOR WHATSAPP FEATURES
const messageStore = new Map();
const chatStore = new Map();
const blockedUsers = new Map();

// ? MULTIPLE IMAGES UPLOAD TRACKING
const multiUploads = new Map();

// ? DUPLICATE MESSAGE PREVENTION - Track emitted messages by temp_id, message_id, AND groupId+imageIndex
const emittedMessages = new Map(); // temp_id -> { message_id, chat_id, group_id, image_index, sender_id, timestamp, emitted: boolean }
const emittedMessageIds = new Set(); // Track message_id separately to prevent duplicates from app restart
const emittedGroupIndex = new Map(); // groupId_imageIndex_chatId_senderId -> { message_id, timestamp } - PREVENT DUPLICATES

// ? CLEANUP OLD EMISSIONS (PREVENT MEMORY LEAK)
setInterval(() => {
  const now = Date.now();
  const maxAge = 24 * 60 * 60 * 1000; // 24 hours
  for (const [tempId, data] of emittedMessages.entries()) {
    if (now - data.timestamp > maxAge) {
      emittedMessages.delete(tempId);
      if (data.message_id) {
        emittedMessageIds.delete(data.message_id.toString());
      }
      // ? Also cleanup groupIndex tracking
      if (data.group_id && data.image_index !== undefined) {
        const groupCacheKey = `${data.group_id}_${data.image_index}_${data.chat_id}_${data.sender_id}`;
        emittedGroupIndex.delete(groupCacheKey);
      }
    }
  }
  // ? Also cleanup old groupIndex entries
  for (const [key, data] of emittedGroupIndex.entries()) {
    if (now - data.timestamp > maxAge) {
      emittedGroupIndex.delete(key);
      if (data.message_id) {
        emittedMessageIds.delete(data.message_id.toString());
      }
    }
  }
}, 60 * 60 * 1000); // Cleanup every hour

// ? ENCRYPTION FUNCTIONS
function encryptBuffer(buffer, secretKey) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(
    "aes-256-ctr",
    crypto.createHash("sha256").update(secretKey).digest(),
    iv
  );
  const encrypted = Buffer.concat([cipher.update(buffer), cipher.final()]);
  const result = Buffer.concat([iv, encrypted]);
  return result.toString("base64");
}

function decryptBuffer(encryptedBase64, secretKey) {
  try {
    const encryptedBuffer = Buffer.from(encryptedBase64, "base64");
    const iv = encryptedBuffer.subarray(0, 16);
    const encryptedData = encryptedBuffer.subarray(16);

    const decipher = crypto.createDecipheriv(
      "aes-256-ctr",
      crypto.createHash("sha256").update(secretKey).digest(),
      iv
    );

    const decrypted = Buffer.concat([
      decipher.update(encryptedData),
      decipher.final(),
    ]);
    return decrypted;
  } catch (error) {
    console.error("? Decryption error:", error);
    throw new Error("Decryption failed: " + error.message);
  }
}

// ? ENCRYPT FILE FUNCTION
async function encryptFile(filePath, outputFilename) {
  try {
    console.log(`?? Encrypting file: ${filePath}`);
    const buffer = await fsp.readFile(filePath);
    const encryptedBase64 = encryptBuffer(buffer, ENCRYPTION_KEY);
    const encryptedPath = path.join(UPLOAD_DIR, outputFilename);
    await fsp.writeFile(encryptedPath, encryptedBase64, "base64");
    console.log(`? File encrypted: ${outputFilename}`);
    return outputFilename;
  } catch (error) {
    console.error("? Encryption error:", error);
    throw error;
  }
}

// ? THUMBNAIL GENERATION FUNCTION - OPTIMIZED FOR SMALL SIZE (1-2 KB)
async function generateThumbnail(buffer) {
  try {
    console.log(`?? Generating optimized thumbnail...`);

    const startTime = Date.now();

    const thumbnailBase64 = await sharp(buffer)
      .resize(150, 150, {
        fit: "cover",
        withoutEnlargement: true,
      })
      .jpeg({
        quality: 10, // ? QUALITY 30% KAR DIYA (previously 70)
        chromaSubsampling: "4:2:0", // ? MORE COMPRESSION
        optimiseScans: true,
        trellisQuantisation: true,
        overshootDeringing: true,
      })
      .toBuffer()
      .then((buffer) => buffer.toString("base64"));

    const endTime = Date.now();
    const timeTaken = endTime - startTime;
    const sizeInKB = Math.round((thumbnailBase64.length * 0.75) / 1024);

    console.log(`? Thumbnail generated: ${sizeInKB} KB, Time: ${timeTaken}ms`);

    // ? EXTRA CHECK: AGAR 3KB SE BADA HAI TOH AUR COMPRESS KARO
    if (sizeInKB > 3) {
      console.log(
        `? Thumbnail still large (${sizeInKB}KB), applying extra compression...`
      );
      const moreCompressed = await sharp(buffer)
        .resize(120, 120, {
          // ? SIZE THODA AUR CHOTA
          fit: "cover",
          withoutEnlargement: true,
        })
        .jpeg({
          quality: 20, // ? AUR LOW QUALITY
          chromaSubsampling: "4:2:0",
          optimiseScans: true,
        })
        .toBuffer()
        .then((buffer) => buffer.toString("base64"));

      const newSizeInKB = Math.round((moreCompressed.length * 0.75) / 1024);
      console.log(`? Extra compressed thumbnail: ${newSizeInKB} KB`);
      return moreCompressed;
    }

    return thumbnailBase64;
  } catch (error) {
    console.error("? Error generating thumbnail:", error);
    return null;
  }
}

// ? GET USER DETAILS FROM PHP (FOR COMPATIBILITY)
async function getUserDetails(userId) {
  try {
    const res = await axios.get(`${PHP_API_BASE}/get_user_by_id.php`, {
      params: { user_id: userId },
    });
    return res.data?.success ? res.data.user : null;
  } catch {
    return null;
  }
}

// ? STORE MESSAGE IN MEMORY (FOR WHATSAPP FEATURES) - FIXED VERSION
function storeMessageInMemory(messageData) {
  const messageId = messageData.message_id;
  if (!messageId) {
    console.error("? Cannot store message without message_id");
    return null;
  }

  const message = {
    ...messageData,
    message_id: messageId,
    timestamp: messageData.timestamp || new Date().toISOString(),
    is_read: messageData.is_read || 0,
    is_delivered: messageData.is_delivered || 0,
    is_deleted_sender: 0,
    is_deleted_receiver: 0,
    stored_in: "node_memory",
  };

  messageStore.set(messageId.toString(), message);

  // Store in chat-specific array
  const chatId = parseInt(message.chat_id);
  if (!chatStore.has(chatId)) {
    chatStore.set(chatId, []);
  }

  // Avoid duplicates
  if (!chatStore.get(chatId).includes(messageId)) {
    chatStore.get(chatId).push(messageId);
  }

  console.log(
    `?? Message stored in Node memory: ${messageId} for chat ${chatId}`
  );
  return message;
}

// ? MULTIPLE IMAGES UPLOAD - INITIALIZE GROUP UPLOAD
router.post("/multi/images/init", async (req, res) => {
  try {
    console.log("?? /multi/images/init received body:", req.body);

    const { chat_id, sender_id, receiver_id, total_images, group_id } =
      req.body;

    if (!chat_id || !sender_id || !receiver_id || !total_images) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields",
        received: req.body,
      });
    }

    const group_upload_id = uuidv4();

    multiUploads.set(group_upload_id, {
      chat_id: parseInt(chat_id),
      sender_id: parseInt(sender_id),
      receiver_id: parseInt(receiver_id),
      total_images: parseInt(total_images),
      group_id: group_id || `group_${Date.now()}`,
      uploaded_images: 0,
      completed_images: [],
      created_at: new Date().toISOString(),
      // ? THUMBNAIL TRACKING FOR WHATSAPP-STYLE FLOW
      thumbnails_sent: 0,
      thumbnails_sent_list: [], // Track which image indices have thumbnails sent
      all_thumbnails_sent: false,
      // ? ACTUAL IMAGES TRACKING
      actual_images_ready: [], // Track which images have media_url ready
      actual_images_sent: 0,
    });

    console.log(
      `?? Multiple images upload initialized: ${group_upload_id}, Total: ${total_images} images`
    );

    res.json({
      success: true,
      group_upload_id,
      group_id: multiUploads.get(group_upload_id).group_id,
      total_images: parseInt(total_images),
    });
  } catch (e) {
    console.error("? /multi/images/init error:", e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ? MULTIPLE IMAGES - UPLOAD SINGLE IMAGE (FAST - THUMBNAIL FIRST, THEN MEDIA_URL)
router.post(
  "/multi/images/upload",
  express.urlencoded({ extended: true }),
  uploadImage.single("image"),
  async (req, res) => {
    try {
      // ? GET SOCKET ID FROM REQUEST (if available)
      const clientSocketId =
        req.headers["x-socket-id"] || req.body.socket_id || "HTTP_REQUEST";

      console.log("=== MULTI UPLOAD START ===");
      console.log("?? Client Socket ID:", clientSocketId);
      console.log(
        "File:",
        req.file
          ? `Yes (${req.file.originalname}, ${req.file.size} bytes)`
          : "NO FILE"
      );
      console.log("Body:", req.body);

      const { group_upload_id, image_index, temp_id, reply_to_message_id } =
        req.body;

      if (!group_upload_id || !image_index) {
        return res.status(400).json({
          success: false,
          message: "Missing group_upload_id or image_index",
          received: req.body,
        });
      }

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: "No file received",
        });
      }

      const groupSession = multiUploads.get(group_upload_id);
      if (!groupSession) {
        return res.status(400).json({
          success: false,
          message: "Invalid group_upload_id",
          received_id: group_upload_id,
        });
      }

      console.log(
        `?? Processing image ${parseInt(image_index) + 1}/${
          groupSession.total_images
        } for group ${group_upload_id}`
      );

      // ? STEP 1: GENERATE THUMBNAIL IMMEDIATELY
      const fileBuffer = req.file.buffer;
      const originalName = req.file.originalname;
      const ext = path.extname(originalName).toLowerCase();
      const base = `${group_upload_id}_img_${image_index}`;
      const finalTempId = temp_id || `temp_${Date.now()}_${image_index}`;

      let thumbnailBase64 = null;

      // Generate thumbnail only
      const thumbnailStartTime = Date.now();
      if ([".jpg", ".jpeg", ".png", ".webp"].includes(ext)) {
        console.log(
          `?? Generating optimized thumbnail for image ${image_index}...`
        );
        thumbnailBase64 = await generateThumbnail(fileBuffer);
      }
      const thumbnailTime = Date.now() - thumbnailStartTime;

      const io = req.app.get("socketio");

      // ? STEP 2: IMMEDIATELY SEND THUMBNAIL TO RECEIVER (ONLY TO RECEIVER - NOT SENDER)
      // ? CRITICAL FIX: Sender already has temp message, so don't send thumbnail to sender
      // ? Only send to receiver to prevent duplicates
      if (io && thumbnailBase64) {
        // ? CRITICAL: Check by groupId+imageIndex to prevent duplicates (MOST RELIABLE)
        const groupCacheKey = `${groupSession.group_id}_${image_index}_${groupSession.chat_id}_${groupSession.sender_id}`;

        if (!emittedGroupIndex.has(groupCacheKey)) {
          const [sender, receiver] = await Promise.all([
            getUserDetails(groupSession.sender_id),
            getUserDetails(groupSession.receiver_id),
          ]);

          const thumbnailMessage = {
            temp_id: finalTempId,
            chat_id: groupSession.chat_id,
            sender_id: groupSession.sender_id,
            receiver_id: groupSession.receiver_id,
            message_type: "media",
            message_text: "media",
            thumbnail_data: thumbnailBase64,
            is_processing: true,
            is_loading: true,
            upload_progress: 10,
            timestamp: new Date().toISOString(),
            sender_name: sender?.normalized_phone || null,
            receiver_name: receiver?.normalized_phone || null,
            sender_phone: sender?.normalized_phone || null,
            receiver_phone: receiver?.normalized_phone || null,
            reply_to_message_id: reply_to_message_id || null,
            // ? GROUP DATA
            group_id: groupSession.group_id,
            image_index: parseInt(image_index),
            total_images: groupSession.total_images,
            has_thumbnail: true,
            has_media_url: false,
            thumbnail_generation_time: thumbnailTime,
            thumbnail_size_kb: Math.round(
              (thumbnailBase64.length * 0.75) / 1024
            ),
          };

          // ? TRACK THIS EMISSION BY GROUP DATA (MOST RELIABLE)
          emittedMessages.set(finalTempId, {
            temp_id: finalTempId,
            chat_id: groupSession.chat_id,
            group_id: groupSession.group_id,
            image_index: parseInt(image_index),
            sender_id: groupSession.sender_id,
            message_id: null,
            timestamp: Date.now(),
            emitted: true,
            thumbnail_emitted: true,
          });

          // ? CRITICAL: Track by groupId+imageIndex (prevents duplicates even if temp_id changes)
          emittedGroupIndex.set(groupCacheKey, {
            temp_id: finalTempId,
            message_id: null,
            timestamp: Date.now(),
            thumbnail_emitted: true,
          });

          // ? CRITICAL FIX: Only emit to RECEIVER (not sender, not chat room)
          // Sender already has temp message, emitting to sender causes duplicates

          // ? GET ALL SOCKET IDs FOR RECEIVER (to track which sockets receive)
          const receiverSockets = await new Promise((resolve) => {
            const sockets = [];
            io.sockets.adapter.rooms
              .get(`user:${groupSession.receiver_id}`)
              ?.forEach((socketId) => {
                sockets.push(socketId);
              });
            resolve(sockets);
          });

          io.to(`user:${groupSession.receiver_id}`).emit(
            "message_thumbnail_ready",
            {
              ...thumbnailMessage,
              _server_socket_id: `SERVER_${Date.now()}`, // ? Server-side tracking ID
              _client_socket_id: clientSocketId, // ? Client socket that sent this
              _receiver_socket_ids: receiverSockets, // ? Which sockets will receive
            }
          );

          // ? TRACK THUMBNAIL SENT FOR THIS IMAGE
          const imageIdx = parseInt(image_index);
          if (!groupSession.thumbnails_sent_list.includes(imageIdx)) {
            groupSession.thumbnails_sent++;
            groupSession.thumbnails_sent_list.push(imageIdx);

            console.log(`?? [THUMBNAIL] Sent to RECEIVER ONLY:`);
            console.log(`   - Image Index: ${image_index}`);
            console.log(`   - Temp ID: ${finalTempId}`);
            console.log(`   - Cache Key: ${groupCacheKey}`);
            console.log(`   - Client Socket ID: ${clientSocketId}`);
            console.log(
              `   - Receiver Socket IDs: ${
                receiverSockets.join(", ") || "NONE"
              }`
            );
            console.log(`   - Server Tracking ID: SERVER_${Date.now()}`);
            console.log(
              `   - Thumbnails Sent: ${groupSession.thumbnails_sent}/${groupSession.total_images}`
            );

            // ? CHECK IF ALL THUMBNAILS ARE SENT
            if (
              groupSession.thumbnails_sent >= groupSession.total_images &&
              !groupSession.all_thumbnails_sent
            ) {
              groupSession.all_thumbnails_sent = true;
              console.log(
                `âœ… [ALL THUMBNAILS SENT] All ${groupSession.total_images} thumbnails sent! Now actual images can load.`
              );

              // ? EMIT EVENT TO NOTIFY ALL THUMBNAILS ARE READY
              if (io) {
                io.to(`user:${groupSession.receiver_id}`).emit(
                  "all_thumbnails_ready",
                  {
                    group_id: groupSession.group_id,
                    chat_id: groupSession.chat_id,
                    total_images: groupSession.total_images,
                    timestamp: new Date().toISOString(),
                  }
                );
                console.log(
                  `ðŸ“¢ [EVENT] all_thumbnails_ready emitted to receiver`
                );
              }

              // ? NOW SEND ALL PENDING ACTUAL IMAGES THAT ARE ALREADY READY
              if (io && groupSession.actual_images_ready.length > 0) {
                console.log(
                  `ðŸ“¤ [SENDING PENDING ACTUAL IMAGES] ${groupSession.actual_images_ready.length} images ready, sending now...`
                );

                // ? Send all ready actual images
                for (const actualImageData of groupSession.actual_images_ready) {
                  // ? Check if already sent
                  const existingGroupEmission = emittedGroupIndex.get(
                    actualImageData.groupCacheKey
                  );
                  if (
                    existingGroupEmission &&
                    existingGroupEmission.final_emitted
                  ) {
                    console.log(
                      `â­ï¸ [SKIP] Image ${
                        actualImageData.image_index + 1
                      } already sent`
                    );
                    continue;
                  }

                  const finalBroadcast = {
                    message_id: actualImageData.message_id,
                    chat_id: actualImageData.chat_id,
                    sender_id: actualImageData.sender_id,
                    receiver_id: actualImageData.receiver_id,
                    message_type: "media",
                    message_text: "media",
                    media_url: actualImageData.media_url,
                    thumbnail_data: actualImageData.thumbnail_data,
                    is_read: 0,
                    is_delivered: 0,
                    timestamp: actualImageData.timestamp,
                    sender_name:
                      actualImageData.sender?.normalized_phone || null,
                    receiver_name:
                      actualImageData.receiver?.normalized_phone || null,
                    sender_phone:
                      actualImageData.sender?.normalized_phone || null,
                    receiver_phone:
                      actualImageData.receiver?.normalized_phone || null,
                    temp_id: actualImageData.temp_id,
                    has_thumbnail: !!actualImageData.thumbnail_data,
                    has_media_url: true,
                    is_processing: false,
                    is_loading: false,
                    upload_progress: 100,
                    reply_to_message_id:
                      actualImageData.reply_to_message_id || null,
                    group_id: groupSession.group_id,
                    image_index: actualImageData.image_index,
                    total_images: groupSession.total_images,
                    thumbnail_size_kb: actualImageData.thumbnail_data
                      ? Math.round(
                          (actualImageData.thumbnail_data.length * 0.75) / 1024
                        )
                      : 0,
                  };

                  const receiverSockets = await new Promise((resolve) => {
                    const sockets = [];
                    io.sockets.adapter.rooms
                      .get(`user:${actualImageData.receiver_id}`)
                      ?.forEach((socketId) => {
                        sockets.push(socketId);
                      });
                    resolve(sockets);
                  });

                  io.to(`user:${actualImageData.receiver_id}`).emit(
                    "message_media_ready",
                    {
                      ...finalBroadcast,
                      _server_socket_id: `SERVER_${Date.now()}`,
                      _client_socket_id: actualImageData.clientSocketId,
                      _receiver_socket_ids: receiverSockets,
                    }
                  );

                  // ? Mark as sent
                  if (existingGroupEmission) {
                    existingGroupEmission.final_emitted = true;
                  } else {
                    emittedGroupIndex.set(actualImageData.groupCacheKey, {
                      temp_id: actualImageData.temp_id,
                      message_id: actualImageData.message_id_str,
                      timestamp: Date.now(),
                      final_emitted: true,
                    });
                  }

                  // ? Update emittedMessages tracking
                  const existingEmission = emittedMessages.get(
                    actualImageData.temp_id
                  );
                  if (existingEmission) {
                    existingEmission.final_emitted = true;
                  }

                  groupSession.actual_images_sent++;
                  console.log(
                    `âœ… [ACTUAL IMAGE SENT] Image ${
                      actualImageData.image_index + 1
                    } with media_url sent to receiver`
                  );
                }

                console.log(
                  `âœ… [COMPLETE] Sent ${groupSession.actual_images_sent} actual images after all thumbnails`
                );
              }
            }
          }
        } else {
          const existingEmission = emittedGroupIndex.get(groupCacheKey);
          console.log(`?? [THUMBNAIL DUPLICATE] Already emitted:`);
          console.log(`   - Group ID: ${groupSession.group_id}`);
          console.log(`   - Image Index: ${image_index}`);
          console.log(`   - Cache Key: ${groupCacheKey}`);
          console.log(`   - Client Socket ID: ${clientSocketId}`);
          console.log(
            `   - Existing Emission: ${JSON.stringify(existingEmission)}`
          );
          console.log(`   - Skipping duplicate`);
        }
      }

      // ? STEP 3: RESPOND QUICKLY TO CLIENT WITH THUMBNAIL
      res.json({
        success: true,
        message: `Image ${
          parseInt(image_index) + 1
        } thumbnail ready, processing media...`,
        data: {
          thumbnail_data: thumbnailBase64,
          temp_id: finalTempId,
          is_processing: true,
          has_thumbnail: !!thumbnailBase64,
          has_media_url: false,
          // ? GROUP DATA
          group_id: groupSession.group_id,
          image_index: parseInt(image_index),
          total_images: groupSession.total_images,
          thumbnail_generation_time: thumbnailTime,
          thumbnail_size_kb: thumbnailBase64
            ? Math.round((thumbnailBase64.length * 0.75) / 1024)
            : 0, // ? SIZE INFO
        },
      });

      // ? STEP 4: BACKGROUND PROCESSING FOR ACTUAL IMAGE (NON-BLOCKING)
      setImmediate(async () => {
        let tempFilePath = null;
        let compressedFilePath = null;

        try {
          console.log(
            `?? Background processing started for image ${image_index}...`
          );

          // ? PROGRESS UPDATE: 20% - Saving file
          if (io) {
            const progressData = {
              temp_id: finalTempId,
              chat_id: groupSession.chat_id,
              upload_progress: 20,
              is_loading: true,
              status: "Saving file...",
            };
            io.to(String(groupSession.chat_id)).emit(
              "message_upload_progress",
              progressData
            );
          }

          // Save original file temporarily
          tempFilePath = path.join(UPLOAD_DIR, `${base}_temp${ext}`);
          await fsp.writeFile(tempFilePath, fileBuffer);

          let finalPath = tempFilePath;

          // Compress image if needed
          if ([".jpg", ".jpeg", ".png", ".webp"].includes(ext)) {
            // ? PROGRESS UPDATE: 40% - Compressing
            if (io) {
              const progressData = {
                temp_id: finalTempId,
                chat_id: groupSession.chat_id,
                upload_progress: 40,
                is_loading: true,
                status: "Compressing image...",
              };
              io.to(String(groupSession.chat_id)).emit(
                "message_upload_progress",
                progressData
              );
            }

            console.log(`?? Compressing image ${image_index}...`);
            const compressed = path.join(
              UPLOAD_DIR,
              `${base}_compressed${ext}`
            );

            await sharp(tempFilePath)
              .resize({ width: 1920, withoutEnlargement: true })
              .jpeg({ quality: 90 })
              .toFile(compressed);

            await fsp.unlink(tempFilePath);
            finalPath = compressed;
            compressedFilePath = compressed;

            console.log(`? Image ${image_index} compressed`);
          }

          // ? PROGRESS UPDATE: 60% - Encrypting
          if (io) {
            const progressData = {
              temp_id: finalTempId,
              chat_id: groupSession.chat_id,
              upload_progress: 60,
              is_loading: true,
              status: "Encrypting...",
            };
            io.to(String(groupSession.chat_id)).emit(
              "message_upload_progress",
              progressData
            );
          }

          // Encrypt file
          const encryptedFilename = `${base}${ext}.enc`;
          const mediaUrl = await encryptFile(finalPath, encryptedFilename);

          const baseUrl = `${req.protocol}://${req.get("host")}`;
          const fullMediaUrl = `${baseUrl}/api/media/file/${mediaUrl}`;

          // ? PROGRESS UPDATE: 80% - Saving to database
          if (io) {
            const progressData = {
              temp_id: finalTempId,
              chat_id: groupSession.chat_id,
              upload_progress: 80,
              is_loading: true,
              status: "Saving to database...",
            };
            io.to(String(groupSession.chat_id)).emit(
              "message_upload_progress",
              progressData
            );
          }

          // Send to PHP API
          const payload = {
            chat_id: groupSession.chat_id,
            sender_id: groupSession.sender_id,
            receiver_id: groupSession.receiver_id,
            message_text: "media",
            media_url: fullMediaUrl,
            thumbnail_data: thumbnailBase64,
            temp_id: finalTempId,
            reply_to_message_id: reply_to_message_id || null,
            // ? GROUP DATA
            group_id: groupSession.group_id,
            image_index: parseInt(image_index),
            total_images: groupSession.total_images,
          };

          console.log(`?? Sending to PHP API for image ${image_index}...`);

          const resp = await axios.post(
            `${PHP_API_BASE}/send_message.php`,
            payload,
            {
              headers: { "Content-Type": "application/json" },
            }
          );

          if (!resp.data?.success)
            throw new Error(resp.data?.error || "PHP failed");

          const phpResponse = resp.data.data;

          // Store in Node memory
          const nodeMessageData = {
            message_id: phpResponse.message_id.toString(),
            chat_id: phpResponse.chat_id,
            sender_id: phpResponse.sender_id,
            receiver_id: phpResponse.receiver_id,
            message_text: "media",
            message_type: "media",
            media_url: fullMediaUrl,
            thumbnail_data: thumbnailBase64,
            is_read: 0,
            is_delivered: 0,
            timestamp: phpResponse.timestamp,
            reply_to_message_id: reply_to_message_id || null,
            // ? GROUP DATA
            group_id: groupSession.group_id,
            image_index: parseInt(image_index),
            total_images: groupSession.total_images,
          };

          storeMessageInMemory(nodeMessageData);

          // Get user details
          const [sender, receiver] = await Promise.all([
            getUserDetails(phpResponse.sender_id),
            getUserDetails(phpResponse.receiver_id),
          ]);

          // ? STEP 5: STORE ACTUAL IMAGE DATA (BUT WAIT FOR ALL THUMBNAILS BEFORE SENDING)
          // ? CRITICAL FIX: Check by groupId+imageIndex to prevent duplicates (MOST RELIABLE)
          const messageIdStr = phpResponse.message_id.toString();
          const groupCacheKey = `${groupSession.group_id}_${image_index}_${phpResponse.chat_id}_${phpResponse.sender_id}`;
          const imageIdx = parseInt(image_index);

          // ? STORE ACTUAL IMAGE DATA WHEN READY
          const actualImageData = {
            message_id: phpResponse.message_id,
            message_id_str: messageIdStr,
            chat_id: phpResponse.chat_id,
            sender_id: phpResponse.sender_id,
            receiver_id: phpResponse.receiver_id,
            media_url: fullMediaUrl,
            thumbnail_data: thumbnailBase64,
            temp_id: finalTempId,
            image_index: imageIdx,
            sender: sender,
            receiver: receiver,
            reply_to_message_id: reply_to_message_id || null,
            timestamp: phpResponse.timestamp,
            groupCacheKey: groupCacheKey,
            clientSocketId: clientSocketId,
          };

          // ? ADD TO ACTUAL IMAGES READY LIST
          if (
            !groupSession.actual_images_ready.find(
              (img) => img.image_index === imageIdx
            )
          ) {
            groupSession.actual_images_ready.push(actualImageData);
            console.log(
              `âœ… [ACTUAL IMAGE READY] Image ${imageIdx + 1}/${
                groupSession.total_images
              } ready (media_url available)`
            );
            console.log(
              `   - Total ready: ${groupSession.actual_images_ready.length}/${groupSession.total_images}`
            );
          }

          // ? UPDATE TRACKING (but don't emit yet)
          const existingEmission = emittedMessages.get(finalTempId);
          if (existingEmission) {
            existingEmission.message_id = messageIdStr;
          } else {
            emittedMessages.set(finalTempId, {
              temp_id: finalTempId,
              chat_id: phpResponse.chat_id,
              group_id: groupSession.group_id,
              image_index: imageIdx,
              sender_id: phpResponse.sender_id,
              message_id: messageIdStr,
              timestamp: Date.now(),
              emitted: true,
              thumbnail_emitted: true,
            });
          }

          // ? CRITICAL: Update groupIndex tracking
          const existingGroupEmission = emittedGroupIndex.get(groupCacheKey);
          if (existingGroupEmission) {
            existingGroupEmission.message_id = messageIdStr;
          } else {
            emittedGroupIndex.set(groupCacheKey, {
              temp_id: finalTempId,
              message_id: messageIdStr,
              timestamp: Date.now(),
              thumbnail_emitted: true,
            });
          }

          emittedMessageIds.add(messageIdStr);

          // ? CRITICAL: ONLY SEND ACTUAL IMAGES AFTER ALL THUMBNAILS ARE SENT
          if (groupSession.all_thumbnails_sent) {
            // ? All thumbnails sent, now send actual images
            console.log(
              `ðŸ“¤ [SENDING ACTUAL IMAGE] All thumbnails sent, sending actual image ${
                imageIdx + 1
              }...`
            );

            const finalBroadcast = {
              message_id: phpResponse.message_id,
              chat_id: phpResponse.chat_id,
              sender_id: phpResponse.sender_id,
              receiver_id: phpResponse.receiver_id,
              message_type: "media",
              message_text: "media",
              media_url: fullMediaUrl, // ? NOW SEND ACTUAL IMAGE URL
              thumbnail_data: thumbnailBase64,
              is_read: 0,
              is_delivered: 0,
              timestamp: phpResponse.timestamp,
              sender_name: sender?.normalized_phone || null,
              receiver_name: receiver?.normalized_phone || null,
              sender_phone: sender?.normalized_phone || null,
              receiver_phone: receiver?.normalized_phone || null,
              temp_id: finalTempId,
              has_thumbnail: !!thumbnailBase64,
              has_media_url: true, // ? NOW TRUE - ACTUAL IMAGE AVAILABLE
              is_processing: false,
              is_loading: false,
              upload_progress: 100,
              reply_to_message_id: reply_to_message_id || null,
              // ? GROUP DATA
              group_id: groupSession.group_id,
              image_index: imageIdx,
              total_images: groupSession.total_images,
              thumbnail_size_kb: thumbnailBase64
                ? Math.round((thumbnailBase64.length * 0.75) / 1024)
                : 0,
            };

            // ? CRITICAL FIX: Only emit to RECEIVER (not sender, not chat room)
            if (io) {
              const receiverSockets = await new Promise((resolve) => {
                const sockets = [];
                io.sockets.adapter.rooms
                  .get(`user:${phpResponse.receiver_id}`)
                  ?.forEach((socketId) => {
                    sockets.push(socketId);
                  });
                resolve(sockets);
              });

              io.to(`user:${phpResponse.receiver_id}`).emit(
                "message_media_ready",
                {
                  ...finalBroadcast,
                  _server_socket_id: `SERVER_${Date.now()}`,
                  _client_socket_id: clientSocketId,
                  _receiver_socket_ids: receiverSockets,
                }
              );

              // ? Mark as sent
              const existingGroupEmissionForThis =
                emittedGroupIndex.get(groupCacheKey);
              if (existingGroupEmissionForThis) {
                existingGroupEmissionForThis.final_emitted = true;
              }

              // ? Update emittedMessages tracking
              const existingEmissionForThis = emittedMessages.get(finalTempId);
              if (existingEmissionForThis) {
                existingEmissionForThis.final_emitted = true;
              }

              console.log(
                `âœ… [ACTUAL IMAGE SENT] Image ${
                  imageIdx + 1
                } with media_url sent to receiver`
              );
              console.log(`   - Message ID: ${phpResponse.message_id}`);
              console.log(`   - Media URL: ${fullMediaUrl}`);

              groupSession.actual_images_sent++;
            }
          } else {
            // ? Wait for all thumbnails - store but don't send yet
            console.log(
              `â³ [WAITING] Actual image ${
                imageIdx + 1
              } ready but waiting for all thumbnails...`
            );
            console.log(
              `   - Thumbnails sent: ${groupSession.thumbnails_sent}/${groupSession.total_images}`
            );
            console.log(`   - Will send when all thumbnails are ready`);
          }

          // Update group session
          groupSession.uploaded_images++;
          groupSession.completed_images.push({
            message_id: phpResponse.message_id,
            image_index: parseInt(image_index),
            media_url: fullMediaUrl,
            thumbnail_data: thumbnailBase64,
            thumbnail_size_kb: thumbnailBase64
              ? Math.round((thumbnailBase64.length * 0.75) / 1024)
              : 0, // ? SIZE INFO
          });

          console.log(
            `? Background processing completed for image ${image_index}`
          );
        } catch (bgError) {
          console.error(
            `? Background processing error for image ${image_index}:`,
            bgError
          );

          // Emit error event
          if (io) {
            io.to(String(groupSession.chat_id)).emit(
              "message_processing_error",
              {
                temp_id: finalTempId,
                image_index: parseInt(image_index),
                error: bgError.message,
              }
            );
          }
        } finally {
          // Cleanup temporary files
          if (tempFilePath && fs.existsSync(tempFilePath)) {
            await fsp.unlink(tempFilePath).catch(() => {});
          }
          if (compressedFilePath && fs.existsSync(compressedFilePath)) {
            await fsp.unlink(compressedFilePath).catch(() => {});
          }
        }
      });
    } catch (e) {
      console.error("? /multi/images/upload error:", e);
      res.status(500).json({
        success: false,
        message: e.message,
      });
    }
  }
);

// ? MULTIPLE IMAGES - COMPLETE GROUP UPLOAD
router.post("/multi/images/complete", async (req, res) => {
  try {
    const { group_upload_id } = req.body;

    if (!group_upload_id) {
      return res
        .status(400)
        .json({ success: false, message: "Missing group_upload_id" });
    }

    const groupSession = multiUploads.get(group_upload_id);
    if (!groupSession) {
      return res
        .status(400)
        .json({ success: false, message: "Invalid group_upload_id" });
    }

    console.log(`?? Completing group upload: ${group_upload_id}`);
    console.log(
      `? Uploaded ${groupSession.uploaded_images}/${groupSession.total_images} images`
    );

    const io = req.app.get("socketio");

    // ? EMIT GROUP COMPLETE EVENT
    if (io) {
      const completeData = {
        group_id: groupSession.group_id,
        chat_id: groupSession.chat_id,
        total_images: groupSession.total_images,
        uploaded_images: groupSession.uploaded_images,
        completed_at: new Date().toISOString(),
        message_ids: groupSession.completed_images.map((img) => img.message_id),
      };

      io.to(String(groupSession.chat_id)).emit(
        "group_upload_complete",
        completeData
      );
      io.to(`user:${groupSession.receiver_id}`).emit(
        "group_upload_complete",
        completeData
      );
    }

    // Cleanup session
    multiUploads.delete(group_upload_id);

    res.json({
      success: true,
      message: "Group upload completed successfully",
      data: {
        group_id: groupSession.group_id,
        chat_id: groupSession.chat_id,
        total_images: groupSession.total_images,
        uploaded_images: groupSession.uploaded_images,
        completed_images: groupSession.completed_images,
        completed_at: new Date().toISOString(),
      },
    });
  } catch (e) {
    console.error("? /multi/images/complete error:", e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ? SINGLE IMAGE UPLOAD (SIMPLE - THUMBNAIL + MEDIA_URL)
router.post("/media/init", async (req, res) => {
  try {
    const { chat_id, sender_id, original_name, total_size } = req.body;
    if (!chat_id || !sender_id || !original_name || !total_size) {
      return res
        .status(400)
        .json({ success: false, message: "Missing fields" });
    }

    const upload_id = uuidv4();
    const tempPath = path.join(UPLOAD_DIR, `${upload_id}.part`);

    uploads.set(upload_id, {
      tempPath,
      chat_id,
      sender_id,
      original_name,
      total_size: Number(total_size),
      received: 0,
    });

    await fsp.writeFile(tempPath, Buffer.alloc(0));
    res.json({ success: true, upload_id });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ? SINGLE IMAGE UPLOAD CHUNK
router.post("/media/chunk", uploadChunk.single("chunk"), async (req, res) => {
  try {
    const { upload_id } = req.body;
    const sess = uploads.get(upload_id);
    if (!sess)
      return res
        .status(400)
        .json({ success: false, message: "Invalid upload_id" });
    if (!req.file?.buffer)
      return res.status(400).json({ success: false, message: "Missing chunk" });

    await fsp.appendFile(sess.tempPath, req.file.buffer);
    sess.received += req.file.buffer.length;

    res.json({ success: true, received: sess.received });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ? SINGLE IMAGE FINALIZE (SIMPLE VERSION)
router.post("/media/finalize", async (req, res) => {
  let tempFilePath = null;

  try {
    const { upload_id, receiver_id, temp_id, reply_to_message_id } = req.body;
    const sess = uploads.get(upload_id);
    if (!sess)
      return res
        .status(400)
        .json({ success: false, message: "Invalid upload_id" });

    tempFilePath = sess.tempPath;
    const ext = path.extname(sess.original_name).toLowerCase();
    const base = path.basename(sess.tempPath, ".part");

    let finalPath = path.join(UPLOAD_DIR, base + ext);

    await fsp.rename(sess.tempPath, finalPath);
    tempFilePath = finalPath;

    console.log(`? File uploaded. Starting processing...`);

    // Read file buffer
    const originalBuffer = await fsp.readFile(finalPath);

    // Generate optimized thumbnail only
    let thumbnailBase64 = null;

    if ([".jpg", ".jpeg", ".png", ".webp"].includes(ext)) {
      thumbnailBase64 = await generateThumbnail(originalBuffer);
    }

    // Encrypt file
    const encryptedFilename = `${base}${ext}.enc`;
    const mediaUrl = await encryptFile(finalPath, encryptedFilename);

    const baseUrl = `${req.protocol}://${req.get("host")}`;
    const fullMediaUrl = `${baseUrl}/api/media/file/${mediaUrl}`;

    const io = req.app.get("socketio");

    // Send thumbnail immediately
    if (io && thumbnailBase64) {
      const thumbnailReady = {
        temp_id,
        chat_id: sess.chat_id,
        sender_id: sess.sender_id,
        receiver_id,
        message_type: "thumbnail_ready",
        thumbnail_data: thumbnailBase64,
        timestamp: new Date().toISOString(),
        thumbnail_size_kb: Math.round((thumbnailBase64.length * 0.75) / 1024), // ? SIZE INFO
      };
      io.to(String(sess.chat_id)).emit(
        "message_thumbnail_ready",
        thumbnailReady
      );
      io.to(`user:${receiver_id}`).emit(
        "message_thumbnail_ready",
        thumbnailReady
      );
    }

    // Send to PHP API
    const payload = {
      chat_id: sess.chat_id,
      sender_id: sess.sender_id,
      receiver_id: receiver_id,
      message_text: "media",
      media_url: fullMediaUrl,
      thumbnail_data: thumbnailBase64,
      temp_id: temp_id,
      reply_to_message_id: reply_to_message_id || null,
    };

    const resp = await axios.post(`${PHP_API_BASE}/send_message.php`, payload, {
      headers: { "Content-Type": "application/json" },
    });

    if (!resp.data?.success) throw new Error(resp.data?.error || "PHP failed");

    const phpResponse = resp.data.data;

    // Store in Node memory
    const nodeMessageData = {
      message_id: phpResponse.message_id.toString(),
      chat_id: phpResponse.chat_id,
      sender_id: phpResponse.sender_id,
      receiver_id: phpResponse.receiver_id,
      message_text: "media",
      message_type: "media",
      media_url: fullMediaUrl,
      thumbnail_data: thumbnailBase64,
      is_read: 0,
      is_delivered: 0,
      timestamp: phpResponse.timestamp,
      reply_to_message_id: reply_to_message_id || null,
    };

    storeMessageInMemory(nodeMessageData);

    // Get user details
    const [sender, receiver] = await Promise.all([
      getUserDetails(phpResponse.sender_id),
      getUserDetails(phpResponse.receiver_id),
    ]);

    // Broadcast final message
    const broadcast = {
      message_id: phpResponse.message_id,
      chat_id: phpResponse.chat_id,
      sender_id: phpResponse.sender_id,
      receiver_id: phpResponse.receiver_id,
      message_type: "media",
      message_text: "media",
      media_url: fullMediaUrl,
      thumbnail_data: thumbnailBase64,
      is_read: 0,
      is_delivered: 0,
      timestamp: phpResponse.timestamp,
      sender_name: sender?.normalized_phone || null,
      receiver_name: receiver?.normalized_phone || null,
      sender_phone: sender?.normalized_phone || null,
      receiver_phone: receiver?.normalized_phone || null,
      temp_id: temp_id,
      has_thumbnail: !!thumbnailBase64,
      has_media_url: true,
      reply_to_message_id: reply_to_message_id || null,
      thumbnail_size_kb: thumbnailBase64
        ? Math.round((thumbnailBase64.length * 0.75) / 1024)
        : 0, // ? SIZE INFO
    };

    // Emit final message
    if (io) {
      io.to(String(phpResponse.chat_id)).emit("new_message", broadcast);
      io.to(`user:${receiver_id}`).emit("new_message", broadcast);
      console.log(`? Media message sent and stored: ${phpResponse.message_id}`);
    }

    // Cleanup
    if (tempFilePath && fs.existsSync(tempFilePath)) {
      await fsp.unlink(tempFilePath);
    }

    uploads.delete(upload_id);

    res.json({
      success: true,
      message: "Uploaded successfully",
      data: {
        media_url: fullMediaUrl,
        thumbnail_data: thumbnailBase64,
        message_id: phpResponse.message_id,
        has_thumbnail: !!thumbnailBase64,
        has_media_url: true,
        reply_to_message_id: reply_to_message_id || null,
        thumbnail_size_kb: thumbnailBase64
          ? Math.round((thumbnailBase64.length * 0.75) / 1024)
          : 0, // ? SIZE INFO
      },
    });
  } catch (e) {
    console.error("? /media/finalize error:", e);

    // Cleanup
    if (tempFilePath && fs.existsSync(tempFilePath)) {
      await fsp.unlink(tempFilePath).catch(() => {});
    }

    res.status(500).json({ success: false, message: e.message });
  }
});

// ? SEND TEXT MESSAGE
router.post("/messages/send", async (req, res) => {
  try {
    const {
      chat_id,
      sender_id,
      receiver_id,
      message_text,
      message_type = "text",
      reply_to_message_id,
      temp_id,
    } = req.body;

    if (!chat_id || !sender_id || !receiver_id || !message_text) {
      return res
        .status(400)
        .json({ success: false, message: "Missing required fields" });
    }

    console.log(`?? Sending text message to chat ${chat_id}`);

    // ? SEND TO PHP API
    const payload = {
      chat_id: chat_id,
      sender_id: sender_id,
      receiver_id: receiver_id,
      message_text: message_text,
      message_type: message_type,
      reply_to_message_id: reply_to_message_id || null,
      temp_id: temp_id,
    };

    const phpResp = await axios.post(
      `${PHP_API_BASE}/send_message.php`,
      payload,
      {
        headers: { "Content-Type": "application/json" },
      }
    );

    if (!phpResp.data?.success) {
      throw new Error(phpResp.data?.error || "PHP failed to send message");
    }

    const phpResponse = phpResp.data.data;

    // ? STORE IN NODE MEMORY
    const nodeMessageData = {
      message_id: phpResponse.message_id.toString(),
      chat_id: phpResponse.chat_id,
      sender_id: phpResponse.sender_id,
      receiver_id: phpResponse.receiver_id,
      message_text: message_text,
      message_type: message_type,
      is_read: 0,
      is_delivered: 0,
      timestamp: phpResponse.timestamp,
      reply_to_message_id: reply_to_message_id || null,
    };

    storeMessageInMemory(nodeMessageData);

    const io = req.app.get("socketio");

    // ? BROADCAST MESSAGE
    if (io) {
      const broadcastData = {
        ...phpResponse,
        reply_to_message_id: reply_to_message_id || null,
      };

      io.to(String(chat_id)).emit("new_message", broadcastData);
      io.to(`user:${receiver_id}`).emit("new_message", broadcastData);
      console.log(
        `? Text message sent and stored in Node: ${phpResponse.message_id}`
      );
    }

    res.json({
      success: true,
      message: "Message sent successfully",
      data: phpResponse,
    });
  } catch (error) {
    console.error("? Error sending message:", error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ? SERVE MEDIA FILES
router.get("/media/file/:filename", async (req, res) => {
  try {
    const filename = req.params.filename;
    const filePath = path.join(UPLOAD_DIR, filename);

    console.log(`?? Serving file: ${filename}`);

    if (!fs.existsSync(filePath)) {
      console.warn(`? File not found: ${filePath}`);
      return res
        .status(404)
        .json({ success: false, message: "File not found" });
    }

    return serveEncryptedFile(filename, filePath, res);
  } catch (e) {
    console.error("? File serve error:", e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ? HELPER FUNCTION TO SERVE ENCRYPTED FILES
async function serveEncryptedFile(filename, filePath, res) {
  try {
    console.log(`?? Decrypting file: ${filename}`);

    const encryptedBase64 = await fsp.readFile(filePath, "base64");
    const decryptedBuffer = decryptBuffer(encryptedBase64, ENCRYPTION_KEY);

    const originalName = filename.replace(".enc", "");
    const ext = path.extname(originalName).toLowerCase();
    let contentType = "application/octet-stream";

    if ([".jpg", ".jpeg"].includes(ext)) contentType = "image/jpeg";
    else if (ext === ".png") contentType = "image/png";
    else if (ext === ".gif") contentType = "image/gif";
    else if (ext === ".webp") contentType = "image/webp";

    res.setHeader("Content-Type", contentType);
    res.setHeader("Cache-Control", "public, max-age=31536000");

    console.log(`? Served file: ${filename}`);
    return res.send(decryptedBuffer);
  } catch (decryptError) {
    console.error("? Decryption failed:", decryptError);
    return res.status(500).json({
      success: false,
      message: "Decryption failed: " + decryptError.message,
    });
  }
}

// ? HEALTH ENDPOINT
router.get("/health", (req, res) => {
  res.json({
    success: true,
    uploadsCount: uploads.size,
    multiUploadsCount: multiUploads.size,
    nodeMessagesCount: messageStore.size,
    chatsCount: chatStore.size,
    blockedUsersCount: blockedUsers.size,
    uploadDir: UPLOAD_DIR,
    message:
      "Media route - OPTIMIZED THUMBNAIL VERSION (1-2 KB target) - MULTIPLE FIXED",
  });
});

module.exports = router;
