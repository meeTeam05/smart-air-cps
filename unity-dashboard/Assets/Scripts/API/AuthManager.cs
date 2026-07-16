using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;
using Utils;

namespace API
{
    public class AuthManager : MonoBehaviour
    {
        // Lưu trữ Token công khai để đọc, nhưng chỉ ghi ở nội bộ class này
        public string AccessToken { get; private set; }
        public string RefreshToken { get; private set; }

        /// <summary>
        /// Gọi API Đăng nhập
        /// </summary>
        public void Login(string email, string password, Action<bool> onComplete = null)
        {
            StartCoroutine(LoginCoroutine(email, password, onComplete));
        }

        private IEnumerator LoginCoroutine(string email, string password, Action<bool> onComplete)
        {
            LoginRequest requestData = new LoginRequest(email, password);
            string jsonBody = JsonUtility.ToJson(requestData);

            using (UnityWebRequest request = new UnityWebRequest(Constants.LOGIN_ENDPOINT, "POST"))
            {
                byte[] bodyRaw = Encoding.UTF8.GetBytes(jsonBody);
                request.uploadHandler = new UploadHandlerRaw(bodyRaw);
                request.downloadHandler = new DownloadHandlerBuffer();
                request.SetRequestHeader("Content-Type", "application/json");

                yield return request.SendWebRequest();

                if (request.result == UnityWebRequest.Result.Success)
                {
                    LoginResponse response = JsonUtility.FromJson<LoginResponse>(request.downloadHandler.text);
                    AccessToken = response.accessToken;
                    RefreshToken = response.refreshToken;

                    Debug.Log("[AuthManager] Login Success!");
                    onComplete?.Invoke(true);
                }
                else
                {
                    Debug.LogError("[AuthManager] Login Failed: " + request.error);
                    onComplete?.Invoke(false);
                }
            }
        }

        /// <summary>
        /// Gọi API Refresh Token
        /// </summary>
        public void RefreshAccessToken(Action<bool> onComplete = null)
        {
            StartCoroutine(RefreshCoroutine(onComplete));
        }

        private IEnumerator RefreshCoroutine(Action<bool> onComplete)
        {
            if (string.IsNullOrEmpty(RefreshToken))
            {
                Debug.LogError("[AuthManager] No Refresh Token available to refresh.");
                onComplete?.Invoke(false);
                yield break;
            }

            RefreshRequest requestData = new RefreshRequest(RefreshToken);
            string jsonBody = JsonUtility.ToJson(requestData);

            using (UnityWebRequest request = new UnityWebRequest(Constants.REFRESH_ENDPOINT, "POST"))
            {
                byte[] bodyRaw = Encoding.UTF8.GetBytes(jsonBody);
                request.uploadHandler = new UploadHandlerRaw(bodyRaw);
                request.downloadHandler = new DownloadHandlerBuffer();
                request.SetRequestHeader("Content-Type", "application/json");

                yield return request.SendWebRequest();

                if (request.result == UnityWebRequest.Result.Success)
                {
                    RefreshResponse response = JsonUtility.FromJson<RefreshResponse>(request.downloadHandler.text);
                    AccessToken = response.accessToken;
                    RefreshToken = response.refreshToken;

                    Debug.Log("[AuthManager] Refresh Token Success!");
                    onComplete?.Invoke(true);
                }
                else
                {
                    Debug.LogError("[AuthManager] Refresh Token Failed: " + request.error);
                    onComplete?.Invoke(false);
                }
            }
        }
    }
}