// Simple test for website linking
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

async function testWebsiteLink() {
  try {
    console.log('=== TESTING WEBSITE LINK ===');
    
    const domain = 'zakhira.in';
    const user_id = 1;
    const cleanDomain = domain.replace(/^https?:\/\//, '').replace(/^www\./, '').toLowerCase();
    
    console.log('1. Clean domain:', cleanDomain);
    
    // Check if website exists
    const [website] = await pool.execute(
      'SELECT * FROM websites WHERE domain = ?',
      [cleanDomain]
    );
    
    console.log('2. Website found:', website.length > 0 ? 'YES' : 'NO');
    if (website.length > 0) {
      console.log('Website ID:', website[0].website_id);
      console.log('Website Name:', website[0].website_name);
      console.log('Website Status:', website[0].status);
    }
    
    // Check user exists
    const [user] = await pool.execute(
      'SELECT * FROM users WHERE user_id = ?',
      [user_id]
    );
    
    console.log('3. User found:', user.length > 0 ? 'YES' : 'NO');
    if (user.length > 0) {
      console.log('User ID:', user[0].user_id);
      console.log('User Name:', user[0].name);
      console.log('User Role:', user[0].role);
    }
    
    // Check existing link
    if (website.length > 0) {
      const [existingLink] = await pool.execute(
        'SELECT * FROM user_websites WHERE user_id = ? AND website_id = ?',
        [user_id, website[0].website_id]
      );
      
      console.log('4. Existing link found:', existingLink.length > 0 ? 'YES' : 'NO');
      if (existingLink.length > 0) {
        console.log('Link Status:', existingLink[0].status);
        console.log('Link Role:', existingLink[0].role);
      }
    }
    
    console.log('=== TEST COMPLETED ===');
    
  } catch (error) {
    console.error('TEST ERROR:', error);
  } finally {
    await pool.end();
  }
}

testWebsiteLink();
