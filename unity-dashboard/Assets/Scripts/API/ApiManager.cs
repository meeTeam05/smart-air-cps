using System.Collections;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json; // Bắt buộc dùng thư viện này để parse kiểu float?
using Utils;
using Dashboard; // Để gọi DashboardManager

namespace API
{
    public class ApiManager : MonoBehaviour
    {
        [Header("Backend Config")]
        [Tooltip("Backend account email. Configure this in the Unity Inspector.")]
        public string email = "";
        [Tooltip("Backend account password. Do not commit real credentials.")]
        public string password = "";
        [Tooltip("Device ID whose shadow data should be displayed.")]
        public string deviceId = "";
        public float pollingInterval = 2f; // Thời gian delay giữa mỗi lần gọi (giây)

        [Header("References")]
        public AuthManager authManager;
        public DashboardManager dashboardManager;

        private void Start()
        {
            // Bước 1 & 2: Khởi động Unity -> Tự động Login và lưu Token
            Debug.Log("[ApiManager] Bắt đầu tự động đăng nhập...");
            authManager.Login(email, password, OnLoginComplete);
        }

        private void OnLoginComplete(bool success)
        {
            if (success)
            {
                // Bước 3: Đăng nhập thành công -> Bắt đầu Poll API định kỳ
                StartCoroutine(PollShadowDataRoutine());
            }
            else
            {
                Debug.LogError("[ApiManager] Đăng nhập thất bại, không thể lấy dữ liệu.");
            }
        }

        private IEnumerator PollShadowDataRoutine()
        {
            while (true)
            {
                string url = Constants.GetShadowEndpoint(deviceId);
                using (UnityWebRequest request = UnityWebRequest.Get(url))
                {
                    // Gắn Access Token vào Header
                    request.SetRequestHeader("Authorization", "Bearer " + authManager.AccessToken);

                    yield return request.SendWebRequest();

                    if (request.result == UnityWebRequest.Result.Success)
                    {
                        // Bước 4 & 5: Đọc JSON Shadow và Parse thành ReportedData
                        ShadowResponse shadow = JsonConvert.DeserializeObject<ShadowResponse>(request.downloadHandler.text);

                        if (shadow != null && shadow.reported != null)
                        {
                            // Bước 6: Gọi DashboardManager
                            dashboardManager.UpdateDashboard(shadow.reported);
                        }
                    }
                    else
                    {
                        Debug.LogError("[ApiManager] Lỗi lấy Shadow: " + request.error);

                        // Nếu lỗi 401 (Hết hạn Token), có thể gọi authManager.RefreshAccessToken() tại đây
                        if (request.responseCode == 401)
                        {
                            Debug.LogWarning("[ApiManager] Token hết hạn, đang thử làm mới...");
                            // Tạm thời dừng vòng lặp hiện tại để chờ xử lý token
                        }
                    }
                }

                // Chờ một khoảng thời gian trước khi gọi lần tiếp theo
                yield return new WaitForSeconds(pollingInterval);
            }
        }
    }
}
