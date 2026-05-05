import React, { useState, useEffect } from 'react';
import axios from 'axios';
import WebsiteLinkButton from './WebsiteLinkButton';

const WebsiteLinking = ({ userId }) => {
  const [linkedWebsites, setLinkedWebsites] = useState([]);
  const [availableWebsites, setAvailableWebsites] = useState([]);
  const [isLoadingLinked, setIsLoadingLinked] = useState(false);
  const [isLoadingAvailable, setIsLoadingAvailable] = useState(false);
  const [domain, setDomain] = useState('');

  useEffect(() => {
    loadLinkedWebsites();
    loadAvailableWebsites();
  }, [userId]);

  const loadLinkedWebsites = async () => {
    setIsLoadingLinked(true);
    
    try {
      const response = await axios.get(`/api/websites/user/${userId}`);
      
      if (response.data.success) {
        setLinkedWebsites(response.data.data || []);
      }
    } catch (error) {
      console.error('Error loading linked websites:', error);
    } finally {
      setIsLoadingLinked(false);
    }
  };

  const loadAvailableWebsites = async () => {
    setIsLoadingAvailable(true);
    
    try {
      const response = await axios.get('/api/websites/available');
      
      if (response.data.success) {
        const available = response.data.data || [];
        
        // Filter out already linked websites
        const filteredAvailable = available.filter(website => 
          !linkedWebsites.some(linked => linked.website_id === website.website_id)
        );
        
        setAvailableWebsites(filteredAvailable);
      }
    } catch (error) {
      console.error('Error loading available websites:', error);
    } finally {
      setIsLoadingAvailable(false);
    }
  };

  const onLinkStatusChanged = (isLinked, websiteData) => {
    if (isLinked) {
      // Add to linked websites
      setLinkedWebsites(prev => [...prev, websiteData]);
      
      // Remove from available websites
      setAvailableWebsites(prev => 
        prev.filter(website => website.website_id !== websiteData.website_id)
      );
    }
  };

  const handleUnlinkWebsite = async (websiteId, domain) => {
    try {
      const response = await axios.post('/api/unlink-website', {
        domain: domain,
        user_id: userId,
      });
      
      if (response.data.success) {
        // Remove from linked websites
        setLinkedWebsites(prev => 
          prev.filter(website => website.website_id !== websiteId)
        );
        
        // Add back to available websites
        const unlinkedWebsite = linkedWebsites.find(w => w.website_id === websiteId);
        if (unlinkedWebsite) {
          setAvailableWebsites(prev => [...prev, unlinkedWebsite]);
        }
        
        alert(response.data.message || 'Website unlinked successfully!');
      } else {
        alert(response.data.message || 'Unlinking failed');
      }
    } catch (error) {
      console.error('Error unlinking website:', error);
      alert('Error: ' + (error.response?.data?.message || error.message));
    }
  };

  const handleLinkNewWebsite = async () => {
    if (!domain.trim()) return;
    
    try {
      const response = await axios.post('/api/verify-app', {
        domain: domain.trim(),
        user_id: userId,
      });
      
      if (response.data.success) {
        // Add to linked websites
        setLinkedWebsites(prev => [...prev, response.data.data]);
        
        // Clear domain input
        setDomain('');
        
        // Refresh available websites
        loadAvailableWebsites();
        
        alert('Website linked successfully!');
      } else {
        if (response.data.requires_admin) {
          alert(`Contact Admin: ****${response.data.admin_last4}`);
        } else {
          alert(response.data.message || 'Failed to link website');
        }
      }
    } catch (error) {
      console.error('Error linking website:', error);
      alert('Error: ' + (error.response?.data?.message || error.message));
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-2xl font-bold text-gray-900 mb-6">Link Website</h1>

        {/* Link New Website Section */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
          <h2 className="text-lg font-semibold text-gray-800 mb-4">Link New Website</h2>
          <div className="flex gap-2">
            <input
              type="text"
              value={domain}
              onChange={(e) => setDomain(e.target.value)}
              placeholder="Enter website domain..."
              className="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              onKeyPress={(e) => e.key === 'Enter' && handleLinkNewWebsite()}
            />
            <button
              onClick={handleLinkNewWebsite}
              className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
            >
              Link
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Your Linked Websites */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <h2 className="text-lg font-semibold text-gray-800 mb-4">Your Linked Websites</h2>
            
            {isLoadingLinked ? (
              <div className="flex justify-center py-8">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
              </div>
            ) : linkedWebsites.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <svg className="mx-auto h-12 w-12 text-gray-300 mb-3" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z" clipRule="evenodd" />
                </svg>
                <p>No linked websites</p>
              </div>
            ) : (
              <div className="space-y-3">
                {linkedWebsites.map((website) => (
                  <div key={website.website_id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div className="flex items-center space-x-3">
                      <div className="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center">
                        <svg className="w-4 h-4 text-green-600" fill="currentColor" viewBox="0 0 20 20">
                          <path fillRule="evenodd" d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z" clipRule="evenodd" />
                        </svg>
                      </div>
                      <div>
                        <h3 className="font-medium text-gray-900">{website.website_name}</h3>
                        <p className="text-sm text-gray-500">{website.domain}</p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleUnlinkWebsite(website.website_id, website.domain)}
                      className="px-3 py-1 text-xs font-medium bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors"
                      title="Unlink this website"
                    >
                      Unlink
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Available Websites */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <h2 className="text-lg font-semibold text-gray-800 mb-4">Available Websites</h2>
            
            {isLoadingAvailable ? (
              <div className="flex justify-center py-8">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
              </div>
            ) : availableWebsites.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <svg className="mx-auto h-12 w-12 text-gray-300 mb-3" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M4 4a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2H4zm12 2H4v8h12V6z" clipRule="evenodd" />
                </svg>
                <p>No available websites</p>
              </div>
            ) : (
              <div className="space-y-3">
                {availableWebsites.map((website) => (
                  <div key={website.website_id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div className="flex items-center space-x-3">
                      <div className="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                        <svg className="w-4 h-4 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                          <path fillRule="evenodd" d="M4 4a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2H4zm12 2H4v8h12V6z" clipRule="evenodd" />
                        </svg>
                      </div>
                      <div>
                        <h3 className="font-medium text-gray-900">{website.website_name}</h3>
                        <p className="text-sm text-gray-500">{website.domain}</p>
                      </div>
                    </div>
                    <WebsiteLinkButton
                      domain={website.domain}
                      userId={userId}
                      onLinkStatusChanged={(isLinked, websiteData) => {
                        if (isLinked) {
                          onLinkStatusChanged(true, {
                            ...websiteData,
                            website_id: website.website_id,
                            website_name: website.website_name,
                            domain: website.domain
                          });
                        }
                      }}
                      className="text-sm"
                    />
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default WebsiteLinking;
