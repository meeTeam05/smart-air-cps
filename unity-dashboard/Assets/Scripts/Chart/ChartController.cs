using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using EasyChart;
using EasyChart.UGUI;

namespace Chart
{
    /// <summary>
    /// Bộ đệm dữ liệu dạng vòng (ring buffer) cho lịch sử cảm biến.
    /// Tránh chi phí O(n) của List.RemoveAt(0) và không cấp phát lại mảng mỗi lần thêm điểm mới.
    /// Index 0 luôn là điểm cũ nhất, Index (Count-1) luôn là điểm mới nhất.
    /// </summary>
    internal sealed class CircularBuffer : IReadOnlyList<float>
    {
        private readonly float[] _buffer;
        private int _head; // vị trí của phần tử cũ nhất
        private int _count;

        public CircularBuffer(int capacity)
        {
            _buffer = new float[Mathf.Max(1, capacity)];
        }

        public int Count => _count;

        public float this[int index]
        {
            get
            {
                if (index < 0 || index >= _count)
                    throw new ArgumentOutOfRangeException(nameof(index));
                return _buffer[(_head + index) % _buffer.Length];
            }
        }

        public void Add(float value)
        {
            int writeIndex = (_head + _count) % _buffer.Length;
            if (_count < _buffer.Length)
            {
                _buffer[writeIndex] = value;
                _count++;
            }
            else
            {
                // Buffer đã đầy: ghi đè điểm cũ nhất rồi đẩy con trỏ "cũ nhất" lên 1 bước.
                _buffer[_head] = value;
                _head = (_head + 1) % _buffer.Length;
            }
        }

        public IEnumerator<float> GetEnumerator()
        {
            for (int i = 0; i < _count; i++) yield return this[i];
        }

        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
    }

    /// <summary>
    /// Chiến lược tính khoảng giá trị (min/max) mục tiêu cho trục Y, dựa trên giá trị
    /// hiện tại và lịch sử gần nhất. Việc làm mượt (smoothing) được xử lý riêng ở SmoothedAxisRange.
    /// </summary>
    internal interface IAxisRangeStrategy
    {
        void ComputeTargetRange(float currentValue, IReadOnlyList<float> history, out float targetMin, out float targetMax);
    }

    /// <summary>
    /// Dùng cho Temperature / Humidity: trục luôn là [giá_trị_hiện_tại ± nửa cửa sổ],
    /// nên giá trị tuyệt đối luôn nằm giữa biểu đồ. "Di chuyển mượt khi đổi vùng vận hành"
    /// không xử lý ở đây mà do SmoothedAxisRange đảm nhiệm (lerp dần qua từng lần cập nhật).
    /// </summary>
    internal sealed class CenteredWindowAxisStrategy : IAxisRangeStrategy
    {
        private readonly float _windowSize;

        public CenteredWindowAxisStrategy(float windowSize)
        {
            _windowSize = Mathf.Max(0.01f, windowSize);
        }

        public void ComputeTargetRange(float currentValue, IReadOnlyList<float> history, out float targetMin, out float targetMax)
        {
            float half = _windowSize * 0.5f;
            targetMin = currentValue - half;
            targetMax = currentValue + half;
        }
    }

    /// <summary>
    /// Dùng cho CO / NO2: chọn nấc (level) nhỏ nhất trong danh sách cấu hình sẵn
    /// đủ để chứa giá trị lớn nhất trong lịch sử đang hiển thị. Có hysteresis
    /// (ngưỡng tăng khác ngưỡng giảm) để tránh nhảy nấc liên tục khi giá trị dao động quanh biên.
    /// </summary>
    internal sealed class AdaptiveStepAxisStrategy : IAxisRangeStrategy
    {
        private readonly float[] _levels;       // tăng dần, ví dụ CO: 10,20,50,100,...
        private readonly float _growThreshold;  // vượt % của nấc hiện tại -> tăng nấc
        private readonly float _shrinkThreshold; // dưới % của nấc thấp hơn -> hạ nấc
        private int _levelIndex;

        public AdaptiveStepAxisStrategy(float[] levels, float growThreshold = 0.9f, float shrinkThreshold = 0.45f)
        {
            _levels = (levels != null && levels.Length > 0) ? levels : new float[] { 10f };
            _growThreshold = growThreshold;
            _shrinkThreshold = shrinkThreshold;
            _levelIndex = 0;
        }

        public void ComputeTargetRange(float currentValue, IReadOnlyList<float> history, out float targetMin, out float targetMax)
        {
            float maxInWindow = currentValue;
            for (int i = 0; i < history.Count; i++)
            {
                if (history[i] > maxInWindow) maxInWindow = history[i];
            }

            // Tăng nấc ngay khi dữ liệu áp sát giới hạn hiện tại (tránh bị cắt đỉnh đường).
            while (_levelIndex < _levels.Length - 1 && maxInWindow > _levels[_levelIndex] * _growThreshold)
            {
                _levelIndex++;
            }

            // Chỉ hạ nấc khi dữ liệu đã xuống thấp hơn rõ rệt so với nấc thấp hơn,
            // để không "nhảy" qua lại liên tục quanh một ngưỡng.
            while (_levelIndex > 0 && maxInWindow < _levels[_levelIndex - 1] * _shrinkThreshold)
            {
                _levelIndex--;
            }

            targetMin = 0f;
            targetMax = _levels[_levelIndex];
        }
    }

    /// <summary>
    /// Làm mượt việc di chuyển trục: mỗi lần có dữ liệu mới, trục hiển thị chỉ
    /// nhích một phần quãng đường còn lại về phía target, thay vì nhảy thẳng tới target.
    /// Đây là cơ chế chung tạo ra yêu cầu "trục di chuyển mượt, không nhảy mỗi lần cập nhật".
    /// </summary>
    internal sealed class SmoothedAxisRange
    {
        private readonly float _smoothing; // 0..1: tỉ lệ quãng đường còn lại được đi mỗi lần cập nhật
        private float _currentMin;
        private float _currentMax;
        private bool _initialized;

        public SmoothedAxisRange(float smoothing)
        {
            _smoothing = Mathf.Clamp01(smoothing);
        }

        public (float min, float max) Update(float targetMin, float targetMax)
        {
            if (!_initialized)
            {
                // Lần đầu tiên: hiển thị đúng target ngay, không cần "mượt" từ giá trị rác.
                _currentMin = targetMin;
                _currentMax = targetMax;
                _initialized = true;
            }
            else
            {
                _currentMin = Mathf.Lerp(_currentMin, targetMin, _smoothing);
                _currentMax = Mathf.Lerp(_currentMax, targetMax, _smoothing);
            }
            return (_currentMin, _currentMax);
        }
    }

    /// <summary>
    /// Gói toàn bộ logic xử lý cho MỘT cảm biến (history, chiến lược trục, làm mượt,
    /// object pool cho SeriesData). ChartController chỉ tạo 4 instance của class này
    /// thay vì lặp lại code 4 lần.
    /// </summary>
    internal sealed class ChartChannel
    {
        private readonly UGUIChartBridge _bridge;
        private readonly CircularBuffer _history;
        private readonly IAxisRangeStrategy _rangeStrategy;
        private readonly SmoothedAxisRange _smoother;

        // Pool các SeriesData được tái sử dụng - chỉ cấp phát thêm khi lịch sử đang "đầy dần",
        // sau khi đạt capacity tối đa thì không còn allocation nào nữa.
        private readonly List<SeriesData> _pointPool = new List<SeriesData>();
        private int _lastXLabelCount = -1;

        public ChartChannel(UGUIChartBridge bridge, int capacity, IAxisRangeStrategy strategy, float smoothing)
        {
            _bridge = bridge;
            _history = new CircularBuffer(capacity);
            _rangeStrategy = strategy;
            _smoother = new SmoothedAxisRange(smoothing);
        }

        public void Push(float value)
        {
            _history.Add(value);

            if (_bridge == null || _bridge.ChartElement == null) return;

            ChartData chartData = _bridge.ChartElement.Data;
            if (chartData == null || chartData.Series == null || chartData.Series.Count == 0) return;

            _rangeStrategy.ComputeTargetRange(value, _history, out float targetMin, out float targetMax);
            var (displayMin, displayMax) = _smoother.Update(targetMin, targetMax);

            ApplyYAxis(chartData, displayMin, displayMax);
            ApplyXAxisLabels(chartData);
            ApplySeriesData(chartData.Series[0]);

            // Đẩy dữ liệu vào pipeline render của EasyChart (cách này giữ được animation
            // có sẵn của plugin, giống cách bản trước đã xác nhận hoạt động).
            _bridge.ChartElement.SetData(chartData);
        }

        private void ApplyYAxis(ChartData chartData, float min, float max)
        {
            AxisConfig yAxis = FindAxis(chartData.Axes, chartData.YAxisId);
            if (yAxis == null) return;

            yAxis.visible = true;
            yAxis.autoRangeMin = false;
            yAxis.autoRangeMax = false;
            yAxis.autoRangeRounding = AutoRangeRoundingMode.None;
            yAxis.minValue = min;
            yAxis.maxValue = max;
        }

        private void ApplyXAxisLabels(ChartData chartData)
        {
            AxisConfig xAxis = FindAxis(chartData.Axes, chartData.XAxisId);
            if (xAxis == null) return;

            int displayCount = Mathf.Max(_history.Count, 2);
            if (xAxis.labels.Count == displayCount) return; // không có gì thay đổi, khỏi rebuild

            xAxis.labels.Clear();
            for (int i = 0; i < displayCount; i++)
            {
                xAxis.labels.Add(i.ToString());
            }
            _lastXLabelCount = displayCount;
        }

        private void ApplySeriesData(Serie serie)
        {
            int historyCount = _history.Count;
            int displayCount = Mathf.Max(historyCount, 2);

            // Mở rộng pool nếu cần (chỉ xảy ra trong giai đoạn lịch sử đang đầy dần,
            // tối đa "maxHistoryPoints" lần trong suốt đời sống của channel).
            while (_pointPool.Count < displayCount)
            {
                _pointPool.Add(new SeriesData { id = Guid.NewGuid().ToString("N") });
            }

            if (historyCount == 1)
            {
                // EasyChart's LineSeriesRenderer yêu cầu tối thiểu 2 điểm mới chịu vẽ.
                // Nhân đôi điểm duy nhất đang có để hiển thị một đường nằm ngang
                // thay vì không vẽ gì, cho tới khi điểm thứ 2 thật về tới.
                WritePoint(_pointPool[0], 0, _history[0]);
                WritePoint(_pointPool[1], 1, _history[0]);
            }
            else
            {
                for (int i = 0; i < historyCount; i++)
                {
                    WritePoint(_pointPool[i], i, _history[i]);
                }
            }

            // Đồng bộ serie.seriesData về đúng "displayCount" phần tử đầu của pool.
            // Chỉ rebuild list khi số điểm thay đổi - không tạo SeriesData mới.
            if (serie.seriesData.Count != displayCount)
            {
                serie.seriesData.Clear();
                for (int i = 0; i < displayCount; i++)
                {
                    serie.seriesData.Add(_pointPool[i]);
                }
            }
        }

        private static void WritePoint(SeriesData point, int index, float value)
        {
            point.x = index;
            point.value = value;
            point.y = value;
        }

        private static AxisConfig FindAxis(List<AxisConfig> axes, AxisId id)
        {
            if (axes == null) return null;
            for (int i = 0; i < axes.Count; i++)
            {
                if (axes[i] != null && axes[i].id == id) return axes[i];
            }
            return null;
        }
    }

    /// <summary>
    /// Điều phối 4 kênh dữ liệu cảm biến (Temperature, Humidity, CO, NO2) lên 4 chart
    /// EasyChart riêng biệt. Mỗi cảm biến có chiến lược trục Y phù hợp với đặc thù dữ liệu:
    /// - Temperature/Humidity: trục bám theo vùng giá trị hiện tại (centered window).
    /// - CO/NO2: trục chọn nấc thang phù hợp (adaptive step), tránh hiển thị 0~5000
    ///   trong khi giá trị thực tế chỉ quanh 0~10.
    /// </summary>
    public class ChartController : MonoBehaviour
    {
        [Header("EasyChart References")]
        public UGUIChartBridge tempChart;
        public UGUIChartBridge humChart;
        public UGUIChartBridge coChart;
        public UGUIChartBridge no2Chart;

        [Header("History")]
        [Tooltip("Số điểm lịch sử tối đa được giữ cho mỗi cảm biến.")]
        public int maxHistoryPoints = 20;

        [Header("Temperature Axis (°C)")]
        [Tooltip("Tổng độ rộng trục Y, luôn căn giữa theo giá trị hiện tại.")]
        public float temperatureWindow = 10f;
        [Tooltip("Tốc độ trục bám theo vùng vận hành mới. Nhỏ = mượt/chậm, lớn = nhảy nhanh.")]
        [Range(0.01f, 1f)] public float temperatureSmoothing = 0.15f;

        [Header("Humidity Axis (%)")]
        public float humidityWindow = 20f;
        [Range(0.01f, 1f)] public float humiditySmoothing = 0.15f;

        [Header("CO Axis (ppm)")]
        [Tooltip("Các mức trần trục Y có thể chọn, tăng dần. Hệ thống tự chọn mức nhỏ nhất đủ chứa dữ liệu.")]
        public float[] coLevels = { 10f, 20f, 50f, 100f, 200f, 500f, 1000f, 2000f, 5000f };
        [Range(0.01f, 1f)] public float coSmoothing = 0.3f;

        [Header("NO2 Axis (ppm)")]
        public float[] no2Levels = { 2f, 5f, 10f, 20f, 50f, 100f, 200f };
        [Range(0.01f, 1f)] public float no2Smoothing = 0.3f;

        private ChartChannel _tempChannel;
        private ChartChannel _humChannel;
        private ChartChannel _coChannel;
        private ChartChannel _no2Channel;

        private void Awake()
        {
            _tempChannel = new ChartChannel(tempChart, maxHistoryPoints,
                new CenteredWindowAxisStrategy(temperatureWindow), temperatureSmoothing);

            _humChannel = new ChartChannel(humChart, maxHistoryPoints,
                new CenteredWindowAxisStrategy(humidityWindow), humiditySmoothing);

            _coChannel = new ChartChannel(coChart, maxHistoryPoints,
                new AdaptiveStepAxisStrategy(coLevels), coSmoothing);

            _no2Channel = new ChartChannel(no2Chart, maxHistoryPoints,
                new AdaptiveStepAxisStrategy(no2Levels), no2Smoothing);
        }

        public void AddTemperature(float value) => _tempChannel?.Push(value);
        public void AddHumidity(float value) => _humChannel?.Push(value);
        public void AddCO(float value) => _coChannel?.Push(value);
        public void AddNO2(float value) => _no2Channel?.Push(value);
    }
}