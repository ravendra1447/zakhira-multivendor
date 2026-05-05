// Check DNS resolution for bangkokmart.in
const dns = require('dns').promises;

async function checkDNS() {
  const domain = 'bangkokmart.in';
  
  console.log(`=== DNS Check for: ${domain} ===`);
  
  try {
    // A record check
    const addresses = await dns.resolve4(domain);
    console.log('A Records (IPv4):', addresses);
    
    // AAAA record check (IPv6)
    try {
      const ipv6Addresses = await dns.resolve6(domain);
      console.log('AAAA Records (IPv6):', ipv6Addresses);
    } catch (ipv6Error) {
      console.log('No IPv6 records found');
    }
    
    // MX record check
    try {
      const mxRecords = await dns.resolveMx(domain);
      console.log('MX Records (Mail):', mxRecords);
    } catch (mxError) {
      console.log('No MX records found');
    }
    
    // NS record check
    try {
      const nsRecords = await dns.resolveNs(domain);
      console.log('NS Records (Name Servers):', nsRecords);
    } catch (nsError) {
      console.log('No NS records found');
    }
    
    // CNAME record check
    try {
      const cnameRecord = await dns.resolveCname(domain);
      console.log('CNAME Record:', cnameRecord);
    } catch (cnameError) {
      console.log('No CNAME record found');
    }
    
    // TXT record check
    try {
      const txtRecords = await dns.resolveTxt(domain);
      console.log('TXT Records:', txtRecords);
    } catch (txtError) {
      console.log('No TXT records found');
    }
    
    // Check if any IP matches your server
    const yourServerIPs = ['184.168.126.71', 'localhost', '127.0.0.1'];
    const matchingIPs = addresses.filter(ip => yourServerIPs.includes(ip));
    
    console.log('\n=== IP Comparison ===');
    console.log('Your Server IPs:', yourServerIPs);
    console.log('Detected IPs:', addresses);
    console.log('Matching IPs:', matchingIPs);
    console.log('Is your server?', matchingIPs.length > 0);
    
  } catch (error) {
    console.error('DNS resolution failed:', error);
  }
}

checkDNS();
