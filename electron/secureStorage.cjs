'use strict';

const Store = require('electron-store');
const crypto = require('crypto');
const os = require('os');
const machineId = require('node-machine-id');

// This class handles secure storage of sensitive data like API keys
class SecureStorage {
  constructor() {
    // Create a secure store with encryption
    this.store = new Store({
      name: 'secure-storage',
      encryptionKey: this.getEncryptionKey(), // Use a device-specific encryption key
      clearInvalidConfig: true,
    });
  }

  // Generate a device-specific encryption key
  getEncryptionKey() {
    try {
      // Use machine ID as a base for the encryption key
      const id = machineId.machineIdSync();
      // Create a deterministic key based on machine ID and a salt
      const hash = crypto.createHash('sha256')
        .update(id + 'snapgrid-salt-dontchange')
        .digest('hex');
      return hash;
    } catch (error) {
      console.error('Error generating encryption key:', error);
      // Fallback to a less secure but still somewhat random key
      return crypto.createHash('sha256')
        .update(os.hostname() + os.userInfo().username + 'snapgrid-salt')
        .digest('hex');
    }
  }

  // Encrypt a value before storing it
  encrypt(text) {
    if (!text) return null;
    
    try {
      // Generate a random initialization vector
      const iv = crypto.randomBytes(16);
      // Create cipher using encryption key and IV
      const cipher = crypto.createCipheriv(
        'aes-256-cbc',
        Buffer.from(this.getEncryptionKey().substring(0, 32)),
        iv
      );
      
      // Encrypt the data
      let encrypted = cipher.update(text, 'utf8', 'hex');
      encrypted += cipher.final('hex');
      
      // Return IV + encrypted data as a single string (IV needed for decryption)
      return iv.toString('hex') + ':' + encrypted;
    } catch (error) {
      console.error('Encryption error:', error);
      return null;
    }
  }

  // Decrypt a stored value
  decrypt(encryptedText) {
    if (!encryptedText) return null;
    
    try {
      // Split the IV from the encrypted data
      const parts = encryptedText.split(':');
      if (parts.length !== 2) return null;
      
      const iv = Buffer.from(parts[0], 'hex');
      const encrypted = parts[1];
      
      // Create decipher using encryption key and IV
      const decipher = crypto.createDecipheriv(
        'aes-256-cbc',
        Buffer.from(this.getEncryptionKey().substring(0, 32)),
        iv
      );
      
      // Decrypt the data
      let decrypted = decipher.update(encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');
      
      return decrypted;
    } catch (error) {
      console.error('Decryption error:', error);
      return null;
    }
  }

  // Store a key securely
  setApiKey(service, key) {
    if (!service || !key) return false;
    
    try {
      const encryptedKey = this.encrypt(key);
      this.store.set(`apiKeys.${service}`, encryptedKey);
      return true;
    } catch (error) {
      console.error(`Error storing API key for ${service}:`, error);
      return false;
    }
  }

  // Retrieve a key
  getApiKey(service) {
    if (!service) return null;
    
    try {
      const encryptedKey = this.store.get(`apiKeys.${service}`);
      if (!encryptedKey) return null;
      
      return this.decrypt(encryptedKey);
    } catch (error) {
      console.error(`Error retrieving API key for ${service}:`, error);
      return null;
    }
  }

  // Check if a key exists
  hasApiKey(service) {
    return this.getApiKey(service) !== null;
  }

  // Delete a key
  deleteApiKey(service) {
    if (!service) return false;
    
    try {
      this.store.delete(`apiKeys.${service}`);
      return true;
    } catch (error) {
      console.error(`Error deleting API key for ${service}:`, error);
      return false;
    }
  }
}

module.exports = SecureStorage; 