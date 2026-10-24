function Import-AACTerraformPlanFlattener {
    <#
    .SYNOPSIS
        Compiles the Terraform plan flattener (AzureAdminConsole.
        TerraformPlanFlattener and its rows, AzureAdminConsole.TerraformLeaf)
        the first time Get-AACTerraformPlan needs it in a session.
    .DESCRIPTION
        A plan of a few thousand resources holds hundreds of thousands of
        values, and every one is walked and compared. Written in PowerShell
        that took over a minute for 3,000 resources - a function call per
        value; in C# it takes well under a second. Compiled once per session
        with Add-Type; a type can't be unloaded, so a later import of the
        module reuses it.

        TerraformPlanFlattener.Flatten(before, after, afterUnknown,
        beforeSensitive, afterSensitive, label, replacePaths) walks one
        change's before and after values side by side - as ConvertFrom-Json
        -AsHashtable reads them - and returns a TerraformLeaf per value that
        changes:

          Raw        the path as plan keys and list indexes, to compare with
                     replace_paths
          Attribute  the path as it reads: tags["cost.centre"],
                     site_config[0].always_on, security_rule[name=ssh].access,
                     policy_rule{json}.then.effect
          Before, After, Change (Added, Removed, Modified, Known after
          apply, Reordered, Reformatted - the same JSON, spaced
          differently), Changed, Sensitive, Unknown, and
          ForcesReplacement when replace_paths names it or a path above it

        ReplacePathLabels(replacePaths) writes replace_paths the same way;
        Fact(first, second, name) reads a top-level text attribute (name,
        location, resource_group_name, id) from the first that has it.

        Maps are walked key by key, with keys only in after_unknown (values
        known after apply) included. A list of blocks is walked element by
        element, paired first when identical, then by their 'name', then in
        order; a list whose elements are the same in another order is one
        Reordered leaf. A string holding JSON on both sides is walked inside
        ({json}), unless only its spacing changed. Values marked in
        before_sensitive or after_sensitive come back as '(sensitive)' and
        values in after_unknown as '(known after apply)'. Empty maps and
        lists, and nulls, on both sides are left out.
    #>
    [CmdletBinding()]
    param()

    if ('AzureAdminConsole.TerraformPlanFlattener' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace AzureAdminConsole
{
    public sealed class TerraformLeaf
    {
        public object[] Raw;
        public string Attribute;
        public string Before;
        public string After;
        public string Change;
        public bool Changed;
        public bool Sensitive;
        public bool Unknown;
        public bool ForcesReplacement;
    }

    public static class TerraformPlanFlattener
    {
        public const string SensitiveText = "(sensitive)";
        public const string UnknownText = "(known after apply)";

        // The leaves that change, each marked when replace_paths names it
        // (or a path above it).
        public static List<TerraformLeaf> Flatten(object before, object after, object afterUnknown, object beforeSensitive, object afterSensitive, string label, object replacePaths)
        {
            var leaves = new List<TerraformLeaf>();
            Walk(new List<object>(), label ?? "", Unwrap(before), Unwrap(after), Unwrap(afterUnknown), Unwrap(beforeSensitive), Unwrap(afterSensitive), leaves);
            var paths = ReplacePaths(replacePaths);
            var changed = new List<TerraformLeaf>(leaves.Count);
            foreach (var leaf in leaves)
            {
                if (!leaf.Changed) { continue; }
                foreach (var path in paths)
                {
                    if (path.Length > leaf.Raw.Length) { continue; }
                    bool match = true;
                    for (int i = 0; match && i < path.Length; i++) { match = string.Equals(path[i], Convert.ToString(leaf.Raw[i], CultureInfo.InvariantCulture), StringComparison.Ordinal); }
                    if (match) { leaf.ForcesReplacement = true; break; }
                }
                changed.Add(leaf);
            }
            return changed;
        }

        static List<string[]> ReplacePaths(object replacePaths)
        {
            var paths = new List<string[]>();
            var list = Unwrap(replacePaths) as IList;
            if (list == null) { return paths; }
            foreach (var item in list)
            {
                var path = Unwrap(item) as IList;
                if (path == null) { continue; }
                var segments = new string[path.Count];
                for (int i = 0; i < path.Count; i++) { segments[i] = Convert.ToString(Unwrap(path[i]), CultureInfo.InvariantCulture); }
                paths.Add(segments);
            }
            return paths;
        }

        // replace_paths as the attributes read: location, network_rules[0].default_action.
        public static string[] ReplacePathLabels(object replacePaths)
        {
            var labels = new List<string>();
            foreach (var path in ReplacePaths(replacePaths))
            {
                var label = "";
                foreach (var segment in path)
                {
                    int index;
                    label = segment.Length > 0 && char.IsDigit(segment[0]) && int.TryParse(segment, NumberStyles.None, CultureInfo.InvariantCulture, out index) ? label + "[" + segment + "]" : JoinLabel(label, segment);
                }
                labels.Add(label);
            }
            return labels.ToArray();
        }

        // A top-level text attribute (name, location, id) from the first
        // value that has it: after then before, or before then after.
        public static string Fact(object first, object second, string name)
        {
            foreach (var side in new[] { Unwrap(first), Unwrap(second) })
            {
                var map = side as IDictionary;
                if (map == null || !map.Contains(name)) { continue; }
                var text = Unwrap(map[name]) as string;
                if (!string.IsNullOrEmpty(text)) { return text; }
            }
            return null;
        }

        // Values set from PowerShell can arrive wrapped in a PSObject.
        static object Unwrap(object value)
        {
            if (value != null && value.GetType().FullName == "System.Management.Automation.PSObject")
            {
                return value.GetType().GetProperty("BaseObject").GetValue(value);
            }
            return value;
        }

        static bool IsTrue(object value) { return value is bool && (bool)value; }

        static bool IsBlocks(object value)
        {
            var list = value as IList;
            if (list == null) { return false; }
            foreach (var item in list) { if (Unwrap(item) is IDictionary) { return true; } }
            return false;
        }

        // A sensitive or unknown marker: true, or a structure with true in it.
        static bool Marked(object marker)
        {
            marker = Unwrap(marker);
            if (marker is bool) { return (bool)marker; }
            var map = marker as IDictionary;
            if (map != null) { foreach (DictionaryEntry entry in map) { if (Marked(entry.Value)) { return true; } } return false; }
            var list = marker as IList;
            if (list != null) { foreach (var item in list) { if (Marked(item)) { return true; } } }
            return false;
        }

        static object Child(object container, object key)
        {
            if (key == null) { return null; }
            var map = container as IDictionary;
            if (map != null) { return map.Contains(key) ? Unwrap(map[key]) : null; }
            var list = container as IList;
            if (list != null && key is int) { int index = (int)key; return index >= 0 && index < list.Count ? Unwrap(list[index]) : null; }
            return null;
        }

        static bool Blank(object value)
        {
            if (value == null) { return true; }
            var map = value as IDictionary;
            if (map != null) { return map.Count == 0; }
            var list = value as IList;
            return list != null && list.Count == 0;
        }

        static string Quote(string text)
        {
            return "\"" + JsonEncodedText.Encode(text, JavaScriptEncoder.UnsafeRelaxedJsonEscaping).ToString() + "\"";
        }

        // One canonical text per value - keys sorted - to compare values.
        public static string Canonical(object value)
        {
            var text = new StringBuilder();
            AppendCanonical(Unwrap(value), text);
            return text.ToString();
        }

        static void AppendCanonical(object value, StringBuilder text)
        {
            value = Unwrap(value);
            if (value == null) { text.Append("null"); return; }
            var s = value as string;
            if (s != null) { text.Append(Quote(s)); return; }
            if (value is bool) { text.Append((bool)value ? "true" : "false"); return; }
            var map = value as IDictionary;
            if (map != null)
            {
                var keys = SortedKeys(map);
                text.Append('{');
                for (int i = 0; i < keys.Count; i++)
                {
                    if (i > 0) { text.Append(','); }
                    text.Append(Quote(keys[i])).Append(':');
                    AppendCanonical(map[keys[i]], text);
                }
                text.Append('}');
                return;
            }
            var list = value as IList;
            if (list != null)
            {
                text.Append('[');
                for (int i = 0; i < list.Count; i++)
                {
                    if (i > 0) { text.Append(','); }
                    AppendCanonical(list[i], text);
                }
                text.Append(']');
                return;
            }
            var formattable = value as IFormattable;
            text.Append(formattable != null ? formattable.ToString(null, CultureInfo.InvariantCulture) : value.ToString());
        }

        static List<string> SortedKeys(IDictionary map)
        {
            var keys = new List<string>(map.Count);
            foreach (var key in map.Keys) { keys.Add(Convert.ToString(key, CultureInfo.InvariantCulture)); }
            keys.Sort(StringComparer.Ordinal);
            return keys;
        }

        // A value as it reads: text as it is, anything else as compact JSON.
        static string Format(object value)
        {
            if (value == null) { return null; }
            var s = value as string;
            return s ?? Canonical(value);
        }

        static string JoinLabel(string label, string key)
        {
            bool plain = key.Length > 0 && (char.IsLetter(key[0]) || key[0] == '_');
            for (int i = 1; plain && i < key.Length; i++) { plain = char.IsLetterOrDigit(key[i]) || key[i] == '_' || key[i] == '-'; }
            if (!plain) { return label + "[" + Quote(key) + "]"; }
            return label.Length > 0 ? label + "." + key : key;
        }

        static void Walk(List<object> raw, string label, object before, object after, object unknown, object beforeSensitive, object afterSensitive, List<TerraformLeaf> leaves)
        {
            bool wholeSecret = IsTrue(beforeSensitive) || IsTrue(afterSensitive);
            bool wholeUnknown = IsTrue(unknown);
            if (!wholeSecret && !wholeUnknown)
            {
                var beforeMap = before as IDictionary;
                var afterMap = after as IDictionary;
                if (beforeMap != null || afterMap != null)
                {
                    var seen = new HashSet<string>(StringComparer.Ordinal);
                    var keys = new List<string>();
                    foreach (var map in new[] { beforeMap, afterMap })
                    {
                        if (map == null) { continue; }
                        foreach (var key in SortedKeys(map)) { if (seen.Add(key)) { keys.Add(key); } }
                    }
                    // Attributes known only after apply are in after_unknown alone.
                    var unknownMap = unknown as IDictionary;
                    if (unknownMap != null)
                    {
                        foreach (var key in SortedKeys(unknownMap)) { if (Marked(unknownMap[key]) && seen.Add(key)) { keys.Add(key); } }
                    }
                    if (keys.Count > 0)
                    {
                        keys.Sort(StringComparer.Ordinal);
                        foreach (var key in keys)
                        {
                            raw.Add(key);
                            Walk(raw, JoinLabel(label, key), Child(before, key), Child(after, key), Child(unknown, key), Child(beforeSensitive, key), Child(afterSensitive, key), leaves);
                            raw.RemoveAt(raw.Count - 1);
                        }
                        return;
                    }
                }
                else if (IsBlocks(before) || IsBlocks(after))
                {
                    WalkBlocks(raw, label, before, after, unknown, beforeSensitive, afterSensitive, leaves);
                    return;
                }
            }

            bool secret = wholeSecret || Marked(beforeSensitive) || Marked(afterSensitive);
            bool isUnknown = wholeUnknown || Marked(unknown);
            if (!isUnknown && Blank(before) && Blank(after)) { return; }

            // A JSON-encoded string (policy rules, ARM templates, azapi
            // bodies): the changes inside it, not two walls of text.
            var beforeText = before as string;
            var afterText = after as string;
            bool reformatted = false;
            if (!secret && !isUnknown && beforeText != null && afterText != null && !string.Equals(beforeText, afterText, StringComparison.Ordinal))
            {
                var beforeJson = ParseJsonContainer(beforeText);
                var afterJson = beforeJson == null ? null : ParseJsonContainer(afterText);
                if (beforeJson != null && afterJson != null)
                {
                    int start = leaves.Count;
                    Walk(raw, label + "{json}", beforeJson, afterJson, null, null, null, leaves);
                    for (int i = start; i < leaves.Count; i++) { if (leaves[i].Changed) { return; } }
                    // Same JSON, different spacing: one leaf, not none.
                    leaves.RemoveRange(start, leaves.Count - start);
                    reformatted = true;
                }
            }

            leaves.Add(new TerraformLeaf
            {
                Raw = raw.ToArray(),
                Attribute = label,
                Before = secret && before != null ? SensitiveText : Format(before),
                After = isUnknown ? UnknownText : (secret && after != null ? SensitiveText : Format(after)),
                Change = isUnknown ? "Known after apply" : reformatted ? "Reformatted" : Blank(before) ? "Added" : Blank(after) ? "Removed" : "Modified",
                Changed = isUnknown || !string.Equals(Canonical(before), Canonical(after), StringComparison.Ordinal),
                Sensitive = secret,
                Unknown = isUnknown
            });
        }

        static string NameOf(object item)
        {
            var map = item as IDictionary;
            if (map == null || !map.Contains("name")) { return null; }
            var name = Unwrap(map["name"]) as string;
            return string.IsNullOrEmpty(name) ? null : name;
        }

        static List<object> Items(object value)
        {
            var items = new List<object>();
            var list = value as IList;
            if (list != null) { foreach (var item in list) { items.Add(Unwrap(item)); } }
            return items;
        }

        // A list of blocks: elements paired identical first, then by name,
        // then in order; what's left was added or removed.
        static void WalkBlocks(List<object> raw, string label, object before, object after, object unknown, object beforeSensitive, object afterSensitive, List<TerraformLeaf> leaves)
        {
            var beforeItems = Items(before);
            var afterItems = Items(after);
            var beforeKeys = beforeItems.ConvertAll(Canonical);
            var afterKeys = afterItems.ConvertAll(Canonical);
            var beforeUsed = new bool[beforeItems.Count];
            var pairOf = new int[afterItems.Count];
            for (int a = 0; a < pairOf.Length; a++) { pairOf[a] = -1; }

            for (int a = 0; a < afterItems.Count; a++)
            {
                if (Marked(Child(unknown, a))) { continue; }
                for (int b = 0; b < beforeItems.Count; b++)
                {
                    if (!beforeUsed[b] && string.Equals(beforeKeys[b], afterKeys[a], StringComparison.Ordinal)) { beforeUsed[b] = true; pairOf[a] = b; break; }
                }
            }
            for (int a = 0; a < afterItems.Count; a++)
            {
                var name = NameOf(afterItems[a]);
                if (pairOf[a] >= 0 || name == null) { continue; }
                for (int b = 0; b < beforeItems.Count; b++)
                {
                    if (!beforeUsed[b] && string.Equals(NameOf(beforeItems[b]), name, StringComparison.Ordinal)) { beforeUsed[b] = true; pairOf[a] = b; break; }
                }
            }
            for (int a = 0; a < afterItems.Count; a++)
            {
                if (pairOf[a] >= 0 || NameOf(afterItems[a]) != null) { continue; }
                for (int b = 0; b < beforeItems.Count; b++)
                {
                    if (!beforeUsed[b] && NameOf(beforeItems[b]) == null) { beforeUsed[b] = true; pairOf[a] = b; break; }
                }
            }

            int start = leaves.Count;
            for (int a = 0; a < afterItems.Count; a++) { WalkElement(raw, label, beforeItems, afterItems, pairOf[a] >= 0 ? pairOf[a] : -1, a, unknown, beforeSensitive, afterSensitive, leaves); }
            for (int b = 0; b < beforeItems.Count; b++) { if (!beforeUsed[b]) { WalkElement(raw, label, beforeItems, afterItems, b, -1, unknown, beforeSensitive, afterSensitive, leaves); } }

            // Same elements, another order.
            for (int i = start; i < leaves.Count; i++) { if (leaves[i].Changed) { return; } }
            if (beforeItems.Count > 0 && afterItems.Count > 0 && !string.Equals(string.Join(",", beforeKeys), string.Join(",", afterKeys), StringComparison.Ordinal))
            {
                leaves.Add(new TerraformLeaf { Raw = raw.ToArray(), Attribute = label, Before = Format(before), After = Format(after), Change = "Reordered", Changed = true });
            }
        }

        static void WalkElement(List<object> raw, string label, List<object> beforeItems, List<object> afterItems, int b, int a, object unknown, object beforeSensitive, object afterSensitive, List<TerraformLeaf> leaves)
        {
            int index = a >= 0 ? a : b;
            var name = NameOf(a >= 0 ? afterItems[a] : beforeItems[b]);
            raw.Add(index);
            Walk(raw, name != null ? label + "[name=" + name + "]" : label + "[" + index.ToString(CultureInfo.InvariantCulture) + "]",
                b >= 0 ? beforeItems[b] : null, a >= 0 ? afterItems[a] : null,
                a >= 0 ? Child(unknown, a) : null, b >= 0 ? Child(beforeSensitive, b) : null, a >= 0 ? Child(afterSensitive, a) : null, leaves);
            raw.RemoveAt(raw.Count - 1);
        }

        static object ParseJsonContainer(string text)
        {
            var trimmed = text.Trim();
            if (trimmed.Length < 2) { return null; }
            bool container = (trimmed[0] == '{' && trimmed[trimmed.Length - 1] == '}') || (trimmed[0] == '[' && trimmed[trimmed.Length - 1] == ']');
            if (!container) { return null; }
            try
            {
                using (var document = JsonDocument.Parse(trimmed))
                {
                    return FromJson(document.RootElement);
                }
            }
            catch (JsonException) { return null; }
        }

        static object FromJson(JsonElement element)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.Object:
                    var map = new Dictionary<string, object>(StringComparer.Ordinal);
                    foreach (var property in element.EnumerateObject()) { map[property.Name] = FromJson(property.Value); }
                    return map;
                case JsonValueKind.Array:
                    var list = new List<object>();
                    foreach (var item in element.EnumerateArray()) { list.Add(FromJson(item)); }
                    return list;
                case JsonValueKind.String: return element.GetString();
                case JsonValueKind.Number:
                    long whole;
                    if (element.TryGetInt64(out whole)) { return whole; }
                    decimal exact;
                    if (element.TryGetDecimal(out exact)) { return exact; }
                    return element.GetDouble();
                case JsonValueKind.True: return true;
                case JsonValueKind.False: return false;
                default: return null;
            }
        }
    }
}
'@
}
