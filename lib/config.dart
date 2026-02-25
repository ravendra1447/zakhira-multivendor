class Config {
  //https://bangkokmart.in/api
  //static const String basePhpApiUrl = "http://184.168.126.71/api";
  static const String basePhpApiUrl = "https://bangkokmart.in/api";
  //https://node-api.bangkokmart.in/api

  //static const String baseNodeApiUrl = "http://184.168.126.71:3000/api";
  static const String baseNodeApiUrl = "https://node-api.bangkokmart.in/api";
  static const int chunkSize = 512 * 1024; // 512KB
  static const int concurrency = 3;
  
  // Chat server configuration - using working IP for marketplace chat
  //static const String chatServerUrl = "https://node-api.bangkokmart.in";
  static const String chatServerUrl = "http://184.168.126.71:3000";

  static const String apiBaseUrl = baseNodeApiUrl; // Use Node API for marketplace chat
  
  // Add your remove.bg API key here for professional cloud-based background removal
  // Get one for free at https://www.remove.bg/api
  static const String removeBgApiKey = "GE4g4mXAZytfgzYUrpvgJAFA";
}