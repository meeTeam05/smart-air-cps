using System;

[Serializable]
public class ReportedData
{
    public string mode;

    public bool relay_1;
    public bool relay_2;
    public bool relay_3;

    public float? temperature;
    public float? humidity;

    public float? co_ppm;
    public float? no2_ppm;

    public long ts;
}