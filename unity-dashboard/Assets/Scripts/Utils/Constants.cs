namespace Utils
{
    public static class Constants
    {
        // Base URL
        public const string BASE_URL = "https://minhnhat05.xyz";

        // Endpoints
        public const string LOGIN_ENDPOINT = BASE_URL + "/api/auth/login";
        public const string REFRESH_ENDPOINT = BASE_URL + "/api/auth/refresh";

        // Hàm hỗ trợ tạo link lấy Shadow dựa trên Device ID
        public static string GetShadowEndpoint(string deviceId)
        {
            return $"{BASE_URL}/api/devices/{deviceId}/shadow";
        }
    }
}