// Quick fix for Zakhira website linking issue
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

async function quickFix() {
  try {
    console.log('=== QUICK FIX FOR ZAKHIRA ===');
    
    const domain = 'zakhira.in';
    const user_id = 1;
    
    // Step 1: Check if Zakhira website exists
    const [website] = await pool.execute(
      'SELECT * FROM websites WHERE domain = ?',
      [domain]
    );
    
    let websiteId;
    
    if (website.length === 0) {
      // Create Zakhira website
      console.log('Creating Zakhira website...');
      const [result] = await pool.execute(`
        INSERT INTO websites (website_name, domain, status, created_at, updated_at)
        VALUES (?, ?, 'Y', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `, ['Zakhira', domain]);
      
      websiteId = result.insertId;
      console.log('Zakhira website created with ID:', websiteId);
    } else {
      websiteId = website[0].website_id;
      console.log('Zakhira website exists with ID:', websiteId);
    }
    
    // Step 2: Check if user is already linked
    const [existingLink] = await pool.execute(
      'SELECT * FROM user_websites WHERE user_id = ? AND website_id = ?',
      [user_id, websiteId]
    );
    
    if (existingLink.length === 0) {
      // Create link
      console.log('Creating user-website link...');
      await pool.execute(`
        INSERT INTO user_websites (user_id, website_id, status, role, created_at, updated_at)
        VALUES (?, ?, 'Y', 'user', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `, [user_id, websiteId]);
      
      console.log('✅ Link created successfully!');
    } else {
      // Update existing link
      console.log('Updating existing link...');
      await pool.execute(`
        UPDATE user_websites 
        SET status = 'Y', updated_at = CURRENT_TIMESTAMP 
        WHERE user_id = ? AND website_id = ?
      `, [user_id, websiteId]);
      
      console.log('✅ Link updated successfully!');
    }
    
    // Step 3: Update website status
    await pool.execute(
      'UPDATE websites SET status = "Y", updated_at = CURRENT_TIMESTAMP WHERE website_id = ?',
      [websiteId]
    );
    
    console.log('✅ Website status updated!');
    
    // Step 4: Verify the link
    const [verify] = await pool.execute(`
      SELECT w.*, uw.status as link_status, uw.role
      FROM websites w
      INNER JOIN user_websites uw ON w.website_id = uw.website_id
      WHERE w.domain = ? AND uw.user_id = ?
    `, [domain, user_id]);
    
    if (verify.length > 0) {
      console.log('✅ VERIFICATION SUCCESSFUL:');
      console.log('Website:', verify[0].website_name);
      console.log('Domain:', verify[0].domain);
      console.log('Link Status:', verify[0].link_status);
      console.log('Role:', verify[0].role);
    } else {
      console.log('❌ VERIFICATION FAILED');
    }
    
    console.log('=== FIX COMPLETED ===');
    
  } catch (error) {
    console.error('❌ ERROR:', error.message);
  } finally {
    await pool.end();
  }
}

quickFix();
