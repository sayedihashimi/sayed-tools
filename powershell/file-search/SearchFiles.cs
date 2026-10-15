#!/usr/bin/env dotnet
// SearchFiles.cs - single-file C# app (.NET 10 file-based app, no .csproj needed).
//
// Searches a pre-built list of files of any extension for text and writes the full path
// of every file that contains it. Reads text regardless of extension; does not extract
// text from binary formats. Defaults to UTF-8, with BOM detection for Unicode text.
//
//   dotnet run SearchFiles.cs -- "dotUltimate"
//
// C# port of Search-Files.ps1 with the same behaviour and defaults, but it
// searches files in parallel so it finishes noticeably faster on large lists.

using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;

// --- Defaults ---------------------------------------------------------------
const string DefaultListFileName = "file-list.txt";

string? searchText = null;
string? listPath = null;
bool caseSensitive = false;
bool useRegex = false;
bool showMatches = false;
bool warnMissing = false;
bool verbose = false;

// --- Parse arguments --------------------------------------------------------
var positional = new List<string>();

for (int i = 0; i < args.Length; i++)
{
    string arg = args[i];

    switch (arg)
    {
        case "-h" or "--help" or "-?" or "/?":
            PrintUsage();
            return 0;

        case "-c" or "--case-sensitive":
            caseSensitive = true;
            break;

        case "-r" or "--regex":
            useRegex = true;
            break;

        case "-m" or "--show-matches":
            showMatches = true;
            break;

        case "-w" or "--warn-missing":
            warnMissing = true;
            break;

        case "-v" or "--verbose":
            verbose = true;
            break;

        case "-l" or "--list":
            if (i + 1 >= args.Length)
            {
                Error($"Option '{arg}' requires a path.");
                return 1;
            }
            listPath = args[++i];
            break;

        default:
            if (arg.StartsWith('-') && arg.Length > 1)
            {
                Error($"Unknown option '{arg}'. Use --help to see the available options.");
                return 1;
            }
            positional.Add(arg);
            break;
    }
}

// Positional form: <searchText> [listPath]
if (positional.Count > 0) searchText = positional[0];
if (positional.Count > 1 && listPath is null) listPath = positional[1];
if (positional.Count > 2)
{
    Error("Too many arguments. Expected: <searchText> [listPath].");
    return 1;
}

if (string.IsNullOrWhiteSpace(searchText))
{
    Error("No search text supplied.");
    Console.Error.WriteLine();
    PrintUsage(Console.Error);
    return 1;
}

// --- Resolve and validate the list file -------------------------------------
listPath ??= FindDefaultListFile();

if (!File.Exists(listPath))
{
    Error($"File list not found: '{listPath}'. Provide a valid path via --list.");
    return 1;
}

listPath = Path.GetFullPath(listPath);

// --- Load the paths ---------------------------------------------------------
string[] paths;
try
{
    paths = File.ReadLines(listPath)
        .Select(line => line.Trim().Trim('"'))
        .Where(line => line.Length > 0 && !line.StartsWith('#'))
        .ToArray();
}
catch (Exception ex)
{
    Error($"Could not read the file list '{listPath}': {ex.Message}");
    return 1;
}

if (paths.Length == 0)
{
    Warn($"No file paths found in '{listPath}'.");
    return 0;
}

Verbose($"Searching {paths.Length:N0} file(s) listed in '{listPath}' for '{searchText}'.");

// --- Build the matcher ------------------------------------------------------
Regex? regex = null;
StringComparison comparison = caseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;

if (useRegex)
{
    var options = RegexOptions.Compiled | RegexOptions.CultureInvariant;
    if (!caseSensitive) options |= RegexOptions.IgnoreCase;

    try
    {
        regex = new Regex(searchText, options);
    }
    catch (ArgumentException ex)
    {
        Error($"Invalid regular expression '{searchText}': {ex.Message}");
        return 1;
    }
}

bool IsMatch(string line) => regex?.IsMatch(line) ?? line.Contains(searchText, comparison);

// --- Search in parallel, but keep results in list order ---------------------
var hitsByIndex = new List<Hit>?[paths.Length];
var warnings = new ConcurrentQueue<string>();
int missingCount = 0;
var stopwatch = Stopwatch.StartNew();

Parallel.For(0, paths.Length, i =>
{
    string path = paths[i];

    try
    {
        // detectEncodingFromByteOrderMarks handles UTF-8/UTF-16 files written by different editors.
        using var reader = new StreamReader(path, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);

        List<Hit>? hits = null;
        int lineNumber = 0;

        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            if (!IsMatch(line)) continue;

            hits ??= [];
            hits.Add(new Hit(lineNumber, line.Trim()));

            if (!showMatches) break; // one hit is enough when only paths are wanted
        }

        hitsByIndex[i] = hits;
    }
    catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
    {
        // The list is a snapshot; files get renamed, moved and deleted after it was built.
        Interlocked.Increment(ref missingCount);
        if (warnMissing) warnings.Enqueue($"Missing file: {path}");
    }
    catch (Exception ex)
    {
        // Locked, access-denied, path too long, malformed entry - report rather than hide.
        warnings.Enqueue($"Could not read '{path}': {ex.Message}");
    }
});

stopwatch.Stop();

// --- Report -----------------------------------------------------------------
foreach (string warning in warnings) Warn(warning);

int matchedCount = 0;
bool firstBlock = true;

for (int i = 0; i < paths.Length; i++)
{
    List<Hit>? hits = hitsByIndex[i];
    if (hits is null || hits.Count == 0) continue;

    matchedCount++;

    if (!showMatches)
    {
        Console.Out.WriteLine(paths[i]);
        continue;
    }

    if (!firstBlock) Console.Out.WriteLine();
    firstBlock = false;

    Console.Out.WriteLine(paths[i]);
    foreach (Hit hit in hits)
    {
        Console.Out.WriteLine($"  {hit.LineNumber,6}: {hit.Line}");
    }
}

Verbose($"Done in {stopwatch.Elapsed.TotalSeconds:F2}s. " +
        $"{matchedCount:N0} file(s) matched; {missingCount:N0} listed path(s) no longer exist.");

return 0;

// --- Helpers ----------------------------------------------------------------

// Look for the default list next to the working directory first, then beside this source file.
string FindDefaultListFile()
{
    string local = Path.Combine(Directory.GetCurrentDirectory(), DefaultListFileName);
    if (File.Exists(local)) return local;

    string beside = Path.Combine(SourceDirectory(), DefaultListFileName);
    if (File.Exists(beside)) return beside;

    return local; // report the most intuitive path in the error message
}

// CallerFilePath resolves to this .cs file, which is where the list normally lives.
static string SourceDirectory([CallerFilePath] string sourcePath = "") =>
    Path.GetDirectoryName(sourcePath) ?? Directory.GetCurrentDirectory();

void Verbose(string message)
{
    if (verbose) Console.Error.WriteLine($"info: {message}");
}

static void Warn(string message) => Console.Error.WriteLine($"warning: {message}");

static void Error(string message) => Console.Error.WriteLine($"error: {message}");

static void PrintUsage(TextWriter? writer = null)
{
    writer ??= Console.Out;
    writer.WriteLine("""
        Searches a list of files of any extension for text and prints the path of each file that contains it.

        USAGE
          dotnet run SearchFiles.cs -- <searchText> [listPath] [options]

        ARGUMENTS
          <searchText>            Text to look for. A literal substring unless --regex is used.
          [listPath]              Optional path to the file list (same as --list).

        OPTIONS
          -l, --list <path>       Text file with one full file path per line.
                                  Default: file-list.txt in the current or source directory.
          -c, --case-sensitive    Match case exactly.
          -r, --regex             Treat <searchText> as a regular expression.
          -m, --show-matches      Print matching line numbers and text under each path.
          -w, --warn-missing      Warn about listed paths that no longer exist.
          -v, --verbose           Print a summary to stderr.
          -h, --help              Show this help.

        EXAMPLES
          dotnet run SearchFiles.cs -- "dotUltimate"
          dotnet run SearchFiles.cs -- "license sales" --case-sensitive
          dotnet run SearchFiles.cs -- "^#\s+Roadmap" --regex --show-matches
          dotnet run SearchFiles.cs -- "Rider" --list D:\lists\other-files.txt

        Reads text regardless of extension; does not extract text from binary formats.
        Defaults to UTF-8, with BOM detection for Unicode text.
        Blank lines and lines starting with '#' in the list file are ignored.
        Exit code 0 on success, 1 on a usage or file-list error.
        """);
}

readonly record struct Hit(int LineNumber, string Line);
