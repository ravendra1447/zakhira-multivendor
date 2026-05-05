import React, { useState, useEffect } from 'react';
import axios from 'axios';

const WebsiteLinkButton = ({ 
  domain, 
  userId, 
  onLinkStatusChanged,
  className = '',
  style = {}
}) => {
  const [isLoading, setIsLoading] = useState(false);
  const [isLinked, setIsLinked] = useState(false);
  const [websiteData, setWebsiteData] = useState(null);

  useEffect(() => {
    checkLinkStatus();
  }, [domain, userId]);

  const checkLinkStatus = async () => {
    setIsLoading(true);
    
    try {
      const cleanDomain = domain
        .replace(/^https?:\/\//, '')
        .replace(/^www\./, '')
        .toLowerCase();

      const response = await axios.get(`/api/status/${userId}/${cleanDomain}`);
      
      if (response.data.success) {
        setIsLinked(response.data.linked);
        setWebsiteData(response.data.data);
        onLinkStatusChanged?.(response.data.linked, response.data.data);
      }
    } catch (error) {
      console.error('Error checking link status:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const linkWebsite = async () => {
    setIsLoading(true);
    
    try {
      const response = await axios.post('/api/verify-app', {
        domain: domain,
        user_id: userId,
      });
      
      if (response.data.success) {
        setIsLinked(true);
        setWebsiteData(response.data.data);
        onLinkStatusChanged?.(true, response.data.data);
        
        // Show success message
        alert(response.data.message || 'Website linked successfully!');
      } else {
        // Handle admin contact case
        if (response.data.requires_admin) {
          showAdminContactDialog(response.data.admin_last4);
        } else {
          alert(response.data.message || 'Linking failed');
        }
      }
    } catch (error) {
      console.error('Error linking website:', error);
      alert('Error: ' + (error.response?.data?.message || error.message));
    } finally {
      setIsLoading(false);
    }
  };

  const unlinkWebsite = async () => {
    console.log('=== UNLINK WEBSITE CALLED ===');
    console.log('Domain:', domain);
    console.log('UserId:', userId);
    
    setIsLoading(true);
    
    try {
      const response = await axios.post('/api/unlink-website', {
        domain: domain,
        user_id: userId,
      });
      
      console.log('Unlink Response:', response.data);
      
      if (response.data.success) {
        setIsLinked(false);
        setWebsiteData(null);
        onLinkStatusChanged?.(false, null);
        
        // Show success message
        alert(response.data.message || 'Website unlinked successfully!');
      } else {
        alert(response.data.message || 'Unlinking failed');
      }
    } catch (error) {
      console.error('Error unlinking website:', error);
      alert('Error: ' + (error.response?.data?.message || error.message));
    } finally {
      setIsLoading(false);
    }
  };

  const showAdminContactDialog = (last4Digits) => {
    const message = `
This website requires admin verification. Please contact the administrator.

Admin: ****${last4Digits}
    `.trim();
    
    alert(message);
  };

  if (isLoading) {
    return (
      <div 
        className={`inline-flex items-center px-4 py-2 bg-gray-200 rounded-lg ${className}`}
        style={style}
      >
        <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-gray-600 mr-2"></div>
        <span className="text-gray-600 font-medium">Checking...</span>
      </div>
    );
  }

  if (isLinked) {
    return (
      <div 
        className={`w-full p-3 bg-green-50 border border-green-300 rounded-lg ${className}`}
        style={style}
      >
        {/* Linked status row */}
        <div className="flex items-center mb-2">
          <svg className="w-5 h-5 text-green-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z" clipRule="evenodd" />
          </svg>
          <span className="text-green-700 font-bold text-sm">Linked</span>
          {websiteData && (
            <span className="ml-2 px-2 py-1 bg-green-600 text-white text-xs font-medium rounded-full">
              {websiteData.website_name || 'Website'}
            </span>
          )}
        </div>
        
        {/* Unlink button - Full width on mobile */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            unlinkWebsite();
          }}
          className="w-full inline-flex items-center justify-center px-4 py-2 bg-red-500 text-white text-sm font-medium rounded hover:bg-red-600 transition-colors shadow-sm"
          title="Unlink this website"
        >
          <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
          </svg>
          Unlink Website
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={linkWebsite}
      className={`inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors ${className}`}
      style={style}
    >
      <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
        <path fillRule="evenodd" d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z" clipRule="evenodd" />
      </svg>
      Link
    </button>
  );
};

export default WebsiteLinkButton;
