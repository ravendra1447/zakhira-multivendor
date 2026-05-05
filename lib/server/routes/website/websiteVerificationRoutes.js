const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

// POST - Verify and link website
router.post('/verify-app', async (req, res) => {
  try {
    const { domain, user_id } = req.body;
    
    console.log('=== VERIFY APP REQUEST ===');
    console.log('Request body:', { domain, user_id });
    
    if (!domain || !user_id) {
      console.log('Missing required fields');
      return res.status(400).json({
        success: false,
        message: 'Domain and user_id are required'
      });
    }

    // Clean domain (remove protocol, www, etc.)
    const cleanDomain = domain.replace(/^https?:\/\//, '').replace(/^www\./, '').toLowerCase();
    console.log('Clean domain:', cleanDomain);

    // Step 1: Check if domain exists in database
    const [existingWebsite] = await pool.execute(
      'SELECT * FROM websites WHERE domain = ?',
      [cleanDomain]
    );
    
    let website;
    
    if (existingWebsite.length === 0) {
      // Domain not found in database - admin approval required
      console.log('❌ Domain not found in database:', cleanDomain);
      return res.json({
        success: false,
        message: `Domain ${cleanDomain} not found in database. Please contact administrator to add this domain.`,
        requires_admin: true,
        verification: {
          method: 'database',
          database_match: false,
          domain: cleanDomain
        }
      });
    } else {
      website = existingWebsite[0];
      console.log('✅ Domain found in database:', website);
      
      // Now verify IP for existing database domain
      console.log('=== IP VERIFICATION FOR DATABASE DOMAIN ===');
      const dns = require('dns').promises;
      
      try {
        // Check both IPv4 and IPv6 addresses
        let allAddresses = [];
        
        try {
          const ipv4Addresses = await dns.resolve4(cleanDomain);
          allAddresses = allAddresses.concat(ipv4Addresses);
          console.log('IPv4 addresses:', ipv4Addresses);
        } catch (ipv4Error) {
          console.log('No IPv4 addresses found');
        }
        
        try {
          const ipv6Addresses = await dns.resolve6(cleanDomain);
          allAddresses = allAddresses.concat(ipv6Addresses);
          console.log('IPv6 addresses:', ipv6Addresses);
        } catch (ipv6Error) {
          console.log('No IPv6 addresses found');
        }
        
        console.log('All detected IPs:', allAddresses);
        
        // Your server IPs (including Cloudflare IPs for your domains)
        const yourServerIPs = [
          '184.168.126.71',  // Your main VPS IP
          '104.21.64.15',    // Cloudflare IP for bangkokmart.in
          '172.67.174.26',   // Cloudflare IP for bangkokmart.in
          '2606:4700:3030::ac43:ae1a',  // Cloudflare IPv6 for bangkokmart.in
          '2606:4700:3033::6815:400f',  // Cloudflare IPv6 for bangkokmart.in
          'localhost',       // Local development
          '127.0.0.1'        // Local loopback
        ];
        
        const isYourServer = allAddresses.some(ip => 
          yourServerIPs.includes(ip)
        );
        
        console.log('Is your server:', isYourServer);
        console.log('Detected IPs:', allAddresses);
        console.log('Your server IPs:', yourServerIPs);
        
        if (!isYourServer) {
          console.log('❌ Database domain hosted on external server');
          return res.json({
            success: false,
            message: `Database domain ${cleanDomain} is hosted on external server (${allAddresses.join(', ')}). Administrator verification required.`,
            requires_admin: true,
            verification: {
              method: 'ip',
              database_match: true,
              server_match: false,
              detected_ip: allAddresses.join(', '),
              your_server_ips: yourServerIPs,
              domain: cleanDomain
            }
          });
        }
        
        console.log('✅ Database domain hosted on your server');
        
      } catch (dnsError) {
        console.log('❌ DNS resolution failed:', dnsError.message);
        return res.json({
          success: false,
          message: `Database domain ${cleanDomain} DNS resolution failed. Please contact administrator.`,
          requires_admin: true,
          verification: {
            method: 'ip',
            database_match: true,
            error: 'DNS resolution failed',
            domain: cleanDomain
          }
        });
      }
    }

    // Step 2: Handle user-website link (with proper unlinking support)
    const [existingLink] = await pool.execute(
      'SELECT * FROM user_websites WHERE user_id = ? AND website_id = ?',
      [user_id, website.website_id]
    );

    console.log('Existing link found:', existingLink.length > 0 ? 'YES' : 'NO');
    if (existingLink.length > 0) {
      console.log('Current link status:', existingLink[0].status);
      console.log('Current link data:', existingLink[0]);
    }
    
    if (existingLink.length === 0) {
      // Create new link
      console.log('Creating new user-website link...');
      await pool.execute(`
        INSERT INTO user_websites (user_id, website_id, status, role, created_at, updated_at)
        VALUES (?, ?, 'Y', 'user', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `, [user_id, website.website_id]);
      
      console.log('New link created successfully');
    } else {
      // Always update existing link to 'Y' (relink functionality)
      console.log('Updating existing link to ACTIVE...');
      await pool.execute(`
        UPDATE user_websites 
        SET status = 'Y', updated_at = CURRENT_TIMESTAMP 
        WHERE user_id = ? AND website_id = ?
      `, [user_id, website.website_id]);
      
      console.log('Link updated to ACTIVE successfully');
    }

    // Also update website status to active
    await pool.execute(
      'UPDATE websites SET status = "Y", updated_at = CURRENT_TIMESTAMP WHERE website_id = ?',
      [website.website_id]
    );

    // Step 3: Verify database connection and link
    console.log('=== DATABASE VERIFICATION ===');
    
    // Test database connection
    try {
      const [dbTest] = await pool.execute('SELECT 1 as test');
      console.log('✅ Database connection: OK');
    } catch (dbError) {
      console.log('❌ Database connection: FAILED');
      return res.status(500).json({
        success: false,
        message: 'Database connection failed. Please contact administrator.',
        requires_admin: true
      });
    }

    // Verify the link was created successfully
    const [verifyLink] = await pool.execute(`
      SELECT w.*, uw.status as link_status, uw.role
      FROM websites w
      INNER JOIN user_websites uw ON w.website_id = uw.website_id
      WHERE w.domain = ? AND uw.user_id = ?
    `, [cleanDomain, user_id]);

    console.log('=== LINK VERIFICATION ===');
    if (verifyLink.length > 0) {
      console.log('✅ LINK VERIFICATION SUCCESSFUL:');
      console.log('Website:', verifyLink[0].website_name);
      console.log('Domain:', verifyLink[0].domain);
      console.log('Link Status:', verifyLink[0].link_status);
      console.log('Role:', verifyLink[0].role);
      
      // Check if this is a production database or requires admin approval
      const isProductionDomain = cleanDomain.includes('bangkokmart.in') || 
                                cleanDomain.includes('zakhira.in') ||
                                cleanDomain.includes('.com');
      
      console.log('Domain type:', isProductionDomain ? 'PRODUCTION' : 'DEVELOPMENT');
      
      if (isProductionDomain) {
        // Production domains work normally
        res.json({
          success: true,
          message: 'Website linked successfully',
          verification: {
            method: 'ip',
            server_match: true,
            verified: true
          },
          data: {
            website_id: verifyLink[0].website_id,
            website_name: verifyLink[0].website_name,
            domain: verifyLink[0].domain,
            status: 'linked'
          }
        });
      } else {
        // Non-standard domains might need admin approval
        console.log('⚠️ Non-standard domain detected');
        res.json({
          success: true,
          message: 'Website linked successfully',
          verification: {
            method: 'ip',
            server_match: true,
            verified: true
          },
          data: {
            website_id: verifyLink[0].website_id,
            website_name: verifyLink[0].website_name,
            domain: verifyLink[0].domain,
            status: 'linked'
          }
        });
      }
    } else {
      console.log('❌ LINK VERIFICATION FAILED');
      console.log('Possible causes:');
      console.log('1. Database transaction failed');
      console.log('2. User ID not found in database');
      console.log('3. Website ID mismatch');
      
      // Check if user exists
      const [userCheck] = await pool.execute(
        'SELECT user_id FROM users WHERE user_id = ?',
        [user_id]
      );
      
      if (userCheck.length === 0) {
        console.log('❌ User not found in database');
        return res.status(404).json({
          success: false,
          message: 'User account not found. Please contact administrator.',
          requires_admin: true
        });
      }
      
      // If user exists but link failed, it might be a database issue
      res.status(500).json({
        success: false,
        message: 'Database linking failed. Please contact administrator.',
        requires_admin: true
      });
    }

  } catch (error) {
    console.error('=== ERROR IN VERIFY WEBSITE ===');
    console.error('Error details:', {
      message: error.message,
      stack: error.stack,
      domain: domain,
      user_id: user_id
    });
    res.status(500).json({
      success: false,
      message: 'Internal server error: ' + error.message
    });
  }
});

// GET - Check website linking status
router.get('/status/:userId/:domain', async (req, res) => {
  try {
    const { userId, domain } = req.params;
    const cleanDomain = domain.replace(/^https?:\/\//, '').replace(/^www\./, '').toLowerCase();

    const [result] = await pool.execute(`
      SELECT w.*, uw.status as user_status, uw.role
      FROM websites w
      LEFT JOIN user_websites uw ON w.website_id = uw.website_id AND uw.user_id = ?
      WHERE w.domain = ?
    `, [userId, cleanDomain]);

    if (result.length === 0) {
      return res.json({
        success: true,
        linked: false,
        message: 'Website not found'
      });
    }

    const website = result[0];
    const isLinked = website.user_status === 'Y';

    res.json({
      success: true,
      linked: isLinked,
      data: {
        website_id: website.website_id,
        website_name: website.website_name,
        domain: website.domain,
        status: isLinked ? 'linked' : 'not_linked',
        role: website.role
      }
    });

  } catch (error) {
    console.error('Error checking website status:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// POST - Unlink website
router.post('/unlink-website', async (req, res) => {
  try {
    const { domain, user_id } = req.body;
    
    console.log('=== UNLINK WEBSITE REQUEST ===');
    console.log('Request body:', { domain, user_id });
    
    if (!domain || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Domain and user_id are required'
      });
    }

    // Clean domain
    const cleanDomain = domain.replace(/^https?:\/\//, '').replace(/^www\./, '').toLowerCase();

    // Find website
    const [website] = await pool.execute(
      'SELECT * FROM websites WHERE domain = ?',
      [cleanDomain]
    );

    if (website.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Website not found'
      });
    }

    // Update user-website link to 'N' (unlinked)
    const [result] = await pool.execute(`
      UPDATE user_websites 
      SET status = 'N', updated_at = CURRENT_TIMESTAMP 
      WHERE user_id = ? AND website_id = ?
    `, [user_id, website[0].website_id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Link not found'
      });
    }

    console.log('=== VERIFYING UNLINK OPERATION ===');
    
    // Verify the unlink was successful
    const [verifyUnlink] = await pool.execute(`
      SELECT w.*, uw.status as user_status, uw.role
      FROM websites w
      LEFT JOIN user_websites uw ON w.website_id = uw.website_id AND uw.user_id = ?
      WHERE w.domain = ?
    `, [user_id, cleanDomain]);

    if (verifyUnlink.length > 0) {
      const isActuallyUnlinked = verifyUnlink[0].user_status === 'N' || verifyUnlink[0].user_status === null;
      
      console.log('Verification result:');
      console.log('- Website found:', verifyUnlink[0].website_name);
      console.log('- User status:', verifyUnlink[0].user_status);
      console.log('- Actually unlinked:', isActuallyUnlinked);
      
      if (isActuallyUnlinked) {
        console.log('✅ Unlink verification SUCCESSFUL');
        res.json({
          success: true,
          message: 'Website unlinked successfully',
          data: {
            website_id: website[0].website_id,
            website_name: website[0].website_name,
            domain: website[0].domain,
            status: 'unlinked'
          }
        });
      } else {
        console.log('❌ Unlink verification FAILED - status not updated');
        res.status(500).json({
          success: false,
          message: 'Database update failed. Please try again or contact administrator.',
          requires_admin: true
        });
      }
    } else {
      console.log('❌ Unlink verification FAILED - website not found');
      res.status(500).json({
        success: false,
        message: 'Verification failed. Please contact administrator.',
        requires_admin: true
      });
    }

  } catch (error) {
    console.error('Error unlinking website:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error: ' + error.message
    });
  }
});

module.exports = router;
