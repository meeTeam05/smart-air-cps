using System;

[Serializable]
public class UserData
{
    public string id;
    public string email;
    public string full_name;
}

[Serializable]
public class LoginResponse
{
    public string accessToken;
    public string refreshToken;

    public UserData user;
}