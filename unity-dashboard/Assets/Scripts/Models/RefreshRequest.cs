using System;

[Serializable]
public class RefreshRequest
{
    public string refreshToken;

    public RefreshRequest(string refreshToken)
    {
        this.refreshToken = refreshToken;
    }
}