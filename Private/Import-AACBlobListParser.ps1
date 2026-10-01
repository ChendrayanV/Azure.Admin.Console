function Import-AACBlobListParser {
    <#
    .SYNOPSIS
        Compiles the List Blobs page parser (AzureAdminConsole.BlobListParser
        and its running total, AzureAdminConsole.BlobTally) the first time
        Get-AACStorageAccountContainerSize needs it in a session.
    .DESCRIPTION
        A container can hold millions of blobs, and every one passes through
        the parser. Written in PowerShell it managed about 5,000 blobs a
        second - parsing, not the network, would set the pace. In C# it reads
        a page of 5,000 in about 10 ms, so the containers' pages are added up
        as fast as Azure Storage sends them. ParseBody takes the response's
        body as a task, not as text: PowerShell hands the arguments of each
        .NET method it calls to AMSI, and a page passed as a string would
        cost more than parsing it.

        Compiled once per session with Add-Type (well under a second); a type
        can't be unloaded, so a later import of the module reuses it.

        BlobTally: Blobs and Bytes count the current blobs; snapshots,
        previous versions and soft-deleted blobs are counted on their own, as
        are Data Lake Storage directories. Tiers maps an access tier (Hot,
        Cool, Cold, Archive, or None for page, append and premium blobs) to
        long[] { count, bytes }. LastModified is the newest current blob's
        (UTC). Largest is the -Top largest current blobs; Rows, with
        keepBlob, every blob listed - both as StorageBlob objects, with
        SizeText worked out when it is read.

        BlobListParser.Parse(content, tally, top, account, container) - or
        ParseBody(httpContent.ReadAsStringAsync(), ...) - adds one page (XML)
        to the tally and returns the next page's marker, or '' on the last.
        Each <Blob> element is read in one pass over its tags with ordinal
        string searches - no XML document, no regular expression - copying
        out only the values it uses, so a page is tallied and dropped without
        building a DOM. Names come back XML-escaped (&amp;), or
        percent-encoded when they hold characters XML can't
        (Encoded="true"); both are decoded. A blob counts as deleted
        (<Deleted>true), a snapshot (it has a <Snapshot> time), a previous
        version (a <VersionId> without <IsCurrentVersion>true), a directory
        (<ResourceType>directory, Data Lake Storage Gen2) or else a current
        blob.
    #>
    [CmdletBinding()]
    param()

    if ('AzureAdminConsole.BlobListParser' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Net;

namespace AzureAdminConsole
{
    // One blob: a plain .NET object rather than a PSObject, which would cost
    // more to make than the blob takes to parse.
    public sealed class StorageBlob
    {
        static readonly string[] Units = { "B", "KiB", "MiB", "GiB", "TiB", "PiB" };

        public string StorageAccount { get; set; }
        public string Container { get; set; }
        public string Name { get; set; }
        public long Size { get; set; }
        // As Format-AACByteSize writes it: powers of 1,024.
        public string SizeText
        {
            get
            {
                double value = Size;
                int power = 0;
                while (value >= 1024 && power < 5) { value /= 1024; power++; }
                return power == 0 ? value.ToString("N0", CultureInfo.CurrentCulture) + " B" : value.ToString("N2", CultureInfo.CurrentCulture) + " " + Units[power];
            }
        }
        public string AccessTier { get; set; }
        public string BlobType { get; set; }
        public string Kind { get; set; }
        public DateTime? LastModified { get; set; }
        public string Snapshot { get; set; }
        public string VersionId { get; set; }

        public override string ToString() { return Name; }
    }

    public sealed class BlobTally
    {
        public long Blobs, Bytes, Snapshots, SnapshotBytes, Versions, VersionBytes, Deleted, DeletedBytes, Directories;
        public int Pages;
        public Hashtable Tiers = new Hashtable(StringComparer.OrdinalIgnoreCase);
        public DateTime? LastModified;
        public List<StorageBlob> Rows;
        internal readonly List<StorageBlob> Top = new List<StorageBlob>();
        internal long Smallest = -1;

        public BlobTally(bool keepBlob)
        {
            if (keepBlob) { Rows = new List<StorageBlob>(); }
        }

        public StorageBlob[] Largest { get { return Top.ToArray(); } }
    }

    public static class BlobListParser
    {
        static bool Is(string content, int start, int length, string tag)
        {
            return length == tag.Length && string.CompareOrdinal(content, start, tag, 0, length) == 0;
        }

        // The body as HttpContent.ReadAsStringAsync() returns it: a task, not
        // the text, so PowerShell passes no megabytes of string to AMSI.
        public static string ParseBody(System.Threading.Tasks.Task<string> body, BlobTally tally, int top, string account, string container)
        {
            return Parse(body.GetAwaiter().GetResult(), tally, top, account, container);
        }

        public static string Parse(string content, BlobTally tally, int top, string account, string container)
        {
            tally.Pages++;
            if (string.IsNullOrEmpty(content)) { return string.Empty; }

            int position = 0;
            while (true)
            {
                int blobStart = content.IndexOf("<Blob>", position, StringComparison.Ordinal);
                if (blobStart < 0) { break; }
                int blobEnd = content.IndexOf("</Blob>", blobStart, StringComparison.Ordinal);
                if (blobEnd < 0) { break; }
                position = blobEnd + 7;

                // One pass over the element's tags; only the ones read are copied out.
                string name = null, sizeText = "", tier = "", blobType = "", modifiedText = "", snapshot = "", version = "", current = "", deleted = "", resource = "";
                bool encoded = false;
                int at = blobStart + 6;
                while (at < blobEnd)
                {
                    int open = content.IndexOf('<', at, blobEnd - at);
                    if (open < 0) { break; }
                    int close = content.IndexOf('>', open, blobEnd - open);
                    if (close < 0) { break; }
                    at = close + 1;
                    if (content[open + 1] == '/' || content[close - 1] == '/') { continue; }
                    int tagStart = open + 1, tagEnd = tagStart;
                    while (tagEnd < close && content[tagEnd] != ' ') { tagEnd++; }
                    int length = tagEnd - tagStart;
                    int valueEnd = content.IndexOf('<', at, blobEnd - at);
                    if (valueEnd < 0) { valueEnd = blobEnd; }
                    switch (length)
                    {
                        case 4:
                            if (name == null && Is(content, tagStart, length, "Name"))
                            {
                                name = content.Substring(at, valueEnd - at);
                                encoded = tagEnd < close && content.IndexOf("Encoded=\"true\"", tagEnd, close - tagEnd, StringComparison.Ordinal) >= 0;
                            }
                            break;
                        case 7: if (Is(content, tagStart, length, "Deleted")) { deleted = content.Substring(at, valueEnd - at); } break;
                        case 8: if (Is(content, tagStart, length, "BlobType")) { blobType = content.Substring(at, valueEnd - at); }
                                else if (Is(content, tagStart, length, "Snapshot")) { snapshot = content.Substring(at, valueEnd - at); } break;
                        case 9: if (Is(content, tagStart, length, "VersionId")) { version = content.Substring(at, valueEnd - at); } break;
                        case 10: if (Is(content, tagStart, length, "AccessTier")) { tier = content.Substring(at, valueEnd - at); } break;
                        case 12: if (Is(content, tagStart, length, "ResourceType")) { resource = content.Substring(at, valueEnd - at); } break;
                        case 13: if (Is(content, tagStart, length, "Last-Modified")) { modifiedText = content.Substring(at, valueEnd - at); } break;
                        case 14: if (Is(content, tagStart, length, "Content-Length")) { sizeText = content.Substring(at, valueEnd - at); } break;
                        case 16: if (Is(content, tagStart, length, "IsCurrentVersion")) { current = content.Substring(at, valueEnd - at); } break;
                    }
                }
                if (name == null) { name = string.Empty; }
                if (resource == "directory") { tally.Directories++; continue; }

                long size = 0;
                long.TryParse(sizeText, NumberStyles.Integer, CultureInfo.InvariantCulture, out size);
                if (tier.Length == 0) { tier = "None"; }
                string kind;
                if (deleted == "true") { kind = "Deleted"; }
                else if (snapshot.Length > 0) { kind = "Snapshot"; }
                else if (version.Length > 0 && current != "true") { kind = "Version"; }
                else { kind = "Blob"; }

                DateTime? modified = null;
                DateTimeOffset parsed;
                if (DateTimeOffset.TryParseExact(modifiedText, "r", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out parsed)) { modified = parsed.UtcDateTime; }

                bool isLarge = false;
                switch (kind)
                {
                    case "Deleted": tally.Deleted++; tally.DeletedBytes += size; break;
                    case "Snapshot": tally.Snapshots++; tally.SnapshotBytes += size; break;
                    case "Version": tally.Versions++; tally.VersionBytes += size; break;
                    default:
                        tally.Blobs++;
                        tally.Bytes += size;
                        long[] bucket = tally.Tiers[tier] as long[];
                        if (bucket == null) { bucket = new long[2]; tally.Tiers[tier] = bucket; }
                        bucket[0]++;
                        bucket[1] += size;
                        if (modified.HasValue && (!tally.LastModified.HasValue || modified.Value > tally.LastModified.Value)) { tally.LastModified = modified; }
                        isLarge = top > 0 && (tally.Top.Count < top || size > tally.Smallest);
                        break;
                }

                bool keepRow = tally.Rows != null;
                if (!keepRow && !isLarge) { continue; }

                if (encoded) { name = Uri.UnescapeDataString(name); }
                else if (name.IndexOf('&') >= 0) { name = WebUtility.HtmlDecode(name); }

                var row = new StorageBlob
                {
                    StorageAccount = account, Container = container, Name = name, Size = size, AccessTier = tier,
                    BlobType = blobType, Kind = kind, LastModified = modified, Snapshot = snapshot, VersionId = version
                };
                if (keepRow) { tally.Rows.Add(row); }

                if (isLarge)
                {
                    tally.Top.Add(row);
                    if (tally.Top.Count > top)
                    {
                        int drop = 0;
                        for (int i = 1; i < tally.Top.Count; i++) { if (tally.Top[i].Size < tally.Top[drop].Size) { drop = i; } }
                        tally.Top.RemoveAt(drop);
                    }
                    if (tally.Top.Count >= top)
                    {
                        long min = long.MaxValue;
                        foreach (var item in tally.Top) { if (item.Size < min) { min = item.Size; } }
                        tally.Smallest = min;
                    }
                }
            }

            // <NextMarker /> (empty) on the last page; it sits after the blobs.
            int start = content.LastIndexOf("<NextMarker>", StringComparison.Ordinal);
            if (start < 0) { return string.Empty; }
            int end = content.IndexOf("</NextMarker>", start, StringComparison.Ordinal);
            if (end < 0) { return string.Empty; }
            return WebUtility.HtmlDecode(content.Substring(start + 12, end - start - 12));
        }
    }
}
'@
}
