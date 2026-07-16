using System;

[Serializable]
public class RefreshResponse
{
    public string accessToken;
    public string refreshToken;
    public string userId;
}