const crypto = require('crypto');

class ChatEncryption {
  constructor() {
    this.algorithm = 'aes-256-gcm';
    this.keyLength = 32; // 256 bits
    this.ivLength = 16; // 128 bits
    this.tagLength = 16; // 128 bits
  }

  // Generate a random encryption key for each message
  generateKey() {
    return crypto.randomBytes(this.keyLength).toString('hex');
  }

  // Encrypt message content
  encrypt(text, keyHex) {
    try {
      const key = Buffer.from(keyHex, 'hex');
      const iv = crypto.randomBytes(this.ivLength);
      
      const cipher = crypto.createCipher(this.algorithm, key);
      cipher.setAAD(Buffer.from('chat-message', 'utf8'));
      
      let encrypted = cipher.update(text, 'utf8', 'hex');
      encrypted += cipher.final('hex');
      
      const tag = cipher.getAuthTag();
      
      // Combine iv + encrypted + tag
      const combined = iv.toString('hex') + ':' + encrypted + ':' + tag.toString('hex');
      
      return combined;
    } catch (error) {
      console.error('Encryption error:', error);
      throw new Error('Failed to encrypt message');
    }
  }

  // Decrypt message content
  decrypt(encryptedData, keyHex) {
    try {
      const key = Buffer.from(keyHex, 'hex');
      const parts = encryptedData.split(':');
      
      if (parts.length !== 3) {
        throw new Error('Invalid encrypted data format');
      }
      
      const iv = Buffer.from(parts[0], 'hex');
      const encrypted = parts[1];
      const tag = Buffer.from(parts[2], 'hex');
      
      const decipher = crypto.createDecipher(this.algorithm, key);
      decipher.setAuthTag(tag);
      decipher.setAAD(Buffer.from('chat-message', 'utf8'));
      
      let decrypted = decipher.update(encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');
      
      return decrypted;
    } catch (error) {
      console.error('Decryption error:', error);
      throw new Error('Failed to decrypt message');
    }
  }

  // Compress and encrypt for faster transmission
  compressAndEncrypt(text, keyHex) {
    try {
      // Simple compression - replace common patterns
      let compressed = text
        .replace(/\s+/g, ' ')  // Multiple spaces to single
        .replace(/\n+/g, '¶')  // Newlines to single character
        .trim();
      
      return this.encrypt(compressed, keyHex);
    } catch (error) {
      console.error('Compression and encryption error:', error);
      throw new Error('Failed to compress and encrypt message');
    }
  }

  // Decrypt and decompress
  decryptAndDecompress(encryptedData, keyHex) {
    try {
      const decrypted = this.decrypt(encryptedData, keyHex);
      
      // Decompress
      let decompressed = decrypted
        .replace(/¶/g, '\n')  // Restore newlines
        .replace(/\s+/g, ' ') // Normalize spaces
        .trim();
      
      return decompressed;
    } catch (error) {
      console.error('Decryption and decompression error:', error);
      throw new Error('Failed to decrypt and decompress message');
    }
  }

  // Generate hash for message integrity
  generateHash(content) {
    return crypto.createHash('sha256').update(content).digest('hex');
  }

  // Verify message integrity
  verifyHash(content, expectedHash) {
    const actualHash = this.generateHash(content);
    return actualHash === expectedHash;
  }
}

module.exports = new ChatEncryption();
