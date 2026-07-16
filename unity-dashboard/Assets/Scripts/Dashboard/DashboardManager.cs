using UnityEngine;
using TMPro;
using Chart;
using System;

namespace Dashboard
{
    public class DashboardManager : MonoBehaviour
    {
        [Header("Clock")]
        public TextMeshProUGUI TMP_Time;

        [Header("Temperature")]
        public TextMeshProUGUI TMP_Temperature;
        public TextMeshProUGUI LCD_Temperature;

        [Header("Humidity")]
        public TextMeshProUGUI TMP_Humidity;
        public TextMeshProUGUI LCD_Humidity;

        [Header("CO")]
        public TextMeshProUGUI TMP_CO;
        public TextMeshProUGUI LCD_CO;

        [Header("NO2")]
        public TextMeshProUGUI TMP_NO2;
        public TextMeshProUGUI LCD_NO2;

        [Header("Relays")]
        public TextMeshProUGUI TMP_FanStatus;
        public TextMeshProUGUI TMP_PumpStatus;  // Đã sửa đổi theo UI
        public TextMeshProUGUI TMP_LightStatus; // Đã sửa đổi theo UI

        [Header("Device Mode")]
        public TextMeshProUGUI TMP_Mode;

        [Header("Chart System")]
        public ChartController chartController;

        // Thêm hàm Update này để đồng hồ chạy liên tục theo giờ của máy tính
        void Update()
        {
            if (TMP_Time != null)
            {
                // Dùng "HH:mm:ss" để hiển thị định dạng 24h (VD: 14:30:05)
                TMP_Time.text = System.DateTime.Now.ToString("hh:mm:ss");
            }
        }

        public void UpdateDashboard(ReportedData data)
        {
            // 1. CẬP NHẬT CẢM BIẾN
            string tempStr = data.temperature.HasValue ? data.temperature.Value.ToString("F1") : "--";
            TMP_Temperature.text = tempStr;
            LCD_Temperature.text = tempStr;

            string humStr = data.humidity.HasValue ? data.humidity.Value.ToString("F1") : "--";
            TMP_Humidity.text = humStr;
            LCD_Humidity.text = humStr;

            string coStr = data.co_ppm.HasValue ? data.co_ppm.Value.ToString("F2") : "--";
            TMP_CO.text = coStr;
            LCD_CO.text = coStr;

            string no2Str = data.no2_ppm.HasValue ? data.no2_ppm.Value.ToString("F2") : "--";
            TMP_NO2.text = no2Str;
            LCD_NO2.text = no2Str;

            // 2. CẬP NHẬT RELAY (Đã sửa lại map chuẩn UI)
            TMP_FanStatus.text = data.relay_1 ? "ON" : "OFF";
            TMP_PumpStatus.text = data.relay_2 ? "ON" : "OFF";
            TMP_LightStatus.text = data.relay_3 ? "ON" : "OFF";

            // 3. CẬP NHẬT MODE
            TMP_Mode.text = string.IsNullOrEmpty(data.mode) ? "--" : data.mode.ToUpper();

            // 4. CẬP NHẬT ĐỒNG HỒ (Đã vô hiệu hóa API time, chuyển lên hàm Update)
            /* 
            if (data.ts > 0)
            {
                DateTimeOffset dateTimeOffset = DateTimeOffset.FromUnixTimeMilliseconds(data.ts);
                TMP_Time.text = dateTimeOffset.LocalDateTime.ToString("hh:mm:ss");
            }
            */

            // 5. GỬI DỮ LIỆU SANG BIỂU ĐỒ
            if (data.temperature.HasValue) chartController.AddTemperature(data.temperature.Value);
            if (data.humidity.HasValue) chartController.AddHumidity(data.humidity.Value);
            if (data.co_ppm.HasValue) chartController.AddCO(data.co_ppm.Value);
            if (data.no2_ppm.HasValue) chartController.AddNO2(data.no2_ppm.Value);
        }
    }
}