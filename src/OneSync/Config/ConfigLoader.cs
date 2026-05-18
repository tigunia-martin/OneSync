using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using OneSync.Util;

namespace OneSync.Config;

internal static class ConfigLoader
{
    public static AppConfig LoadFromFile(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"Config file not found at: {path}", path);

        var json = File.ReadAllText(path);
        AppConfig? config;
        try
        {
            config = JsonSerializer.Deserialize<AppConfig>(json, JsonOptions);
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException($"config.json is not valid JSON: {ex.Message}", ex);
        }

        if (config is null)
            throw new InvalidDataException("config.json deserialised to null");

        ExpandEnvironmentVariables(config);
        Validate(config);

        return config;
    }

    public static void ExpandEnvironmentVariables(AppConfig config)
    {
        config.LocalStorageRoot = PathUtil.Expand(config.LocalStorageRoot);
        config.Logging.Path = PathUtil.Expand(config.Logging.Path);
        config.Authority = PathUtil.Expand(config.Authority);

        foreach (var drive in config.Drives)
        {
            drive.LocalRootPath = ComputeLocalRootPath(config.LocalStorageRoot, drive);
        }
    }

    private static string ComputeLocalRootPath(string storageRoot, DriveConfig drive)
    {
        var name = drive.Label.Replace(' ', '_');
        if (string.IsNullOrWhiteSpace(name)) name = $"Drive_{drive.Letter}";
        return Path.Combine(storageRoot, name);
    }

    public static void Validate(AppConfig config)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(config.TenantId) ||
            config.TenantId.Equals("YOUR-AZURE-TENANT-ID", StringComparison.OrdinalIgnoreCase))
            errors.Add("config.tenantId is missing or placeholder");

        if (string.IsNullOrWhiteSpace(config.ClientId) ||
            config.ClientId.Equals("YOUR-APP-CLIENT-ID", StringComparison.OrdinalIgnoreCase))
            errors.Add("config.clientId is missing or placeholder");

        if (string.IsNullOrWhiteSpace(config.Authority))
            config.Authority = $"https://login.microsoftonline.com/{config.TenantId}";

        if (config.Drives.Count == 0)
            errors.Add("config.drives is empty - at least one drive required");

        var seenLetters = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var d in config.Drives)
        {
            if (string.IsNullOrWhiteSpace(d.Letter) || d.Letter.Length != 1 ||
                !char.IsLetter(d.Letter[0]))
            {
                errors.Add($"Invalid drive letter '{d.Letter}' (must be A-Z)");
                continue;
            }
            d.Letter = d.Letter.ToUpperInvariant();
            if (!seenLetters.Add(d.Letter))
                errors.Add($"Duplicate drive letter '{d.Letter}'");

            if (d.IsSharePoint)
            {
                if (string.IsNullOrWhiteSpace(d.SiteUrl))
                    errors.Add($"Drive {d.Letter}: siteUrl required for SharePoint drives");
                if (string.IsNullOrWhiteSpace(d.LibraryName))
                    errors.Add($"Drive {d.Letter}: libraryName required for SharePoint drives");
            }
            else if (!d.IsOneDrive)
            {
                errors.Add($"Drive {d.Letter}: type must be 'onedrive' or 'sharepoint', got '{d.Type}'");
            }
        }

        if (errors.Count > 0)
            throw new InvalidDataException("config.json validation failed:\n  - " + string.Join("\n  - ", errors));
    }

    public static AppConfig LoadFromDefaultLocations(out string sourcePath)
    {
        foreach (var candidate in DefaultPaths())
        {
            if (File.Exists(candidate))
            {
                sourcePath = candidate;
                return LoadFromFile(candidate);
            }
        }
        sourcePath = DefaultPaths().First();
        throw new FileNotFoundException(
            $"config.json not found. Looked in:\n  - {string.Join("\n  - ", DefaultPaths())}");
    }

    private static IEnumerable<string> DefaultPaths()
    {
        var baseDir = AppContext.BaseDirectory;
        yield return Path.Combine(baseDir, "config.json");
        yield return Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "config.json");
        yield return PathUtil.Expand(@"%PROGRAMDATA%\OneSync\config.json");
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };
}
