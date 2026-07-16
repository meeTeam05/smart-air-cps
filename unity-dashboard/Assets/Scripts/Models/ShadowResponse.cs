using System;

[Serializable]
public class DesiredData
{
    public string mode;

    public bool relay_1;
}

[Serializable]
public class ShadowResponse
{
    public ReportedData reported;

    public DesiredData desired;

    public string updatedAt;
}