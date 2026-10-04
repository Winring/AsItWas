using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;

namespace ATT
{
    /// <summary>
    /// Exports effective quest patch values from ATT's already processed object
    /// graph, including awp values consolidated onto structural ancestors.
    /// </summary>
    internal static class QuestPatchExport
    {
        public static void Export(string directory)
        {
            var values = new SortedDictionary<long, SortedSet<long>>();
            var active = new HashSet<object>(ReferenceEqualityComparer.Instance);
            foreach (var container in Framework.Objects.AllContainers.Values)
            {
                VisitValue(container, values, active, null);
            }

            var json = new Dictionary<string, object>();
            foreach (var pair in values)
            {
                json[pair.Key.ToString()] = pair.Value.Select(value => (object)value).ToList();
            }

            File.WriteAllText(
                Path.Combine(directory, "QuestPatches.att.json"),
                MiniJSON.Json.Serialize(json));
        }

        private static void VisitValue(
            object value,
            SortedDictionary<long, SortedSet<long>> values,
            HashSet<object> active,
            long? inheritedAwp)
        {
            if (value == null || value is string) return;

            bool tracked = value is IDictionary<string, object> || value is IEnumerable;
            if (tracked && !active.Add(value)) return;

            try
            {
                if (value is IDictionary<string, object> data)
                {
                    Visit(data, values, active, inheritedAwp);
                    return;
                }

                if (value is IEnumerable enumerable)
                {
                    foreach (var child in enumerable)
                    {
                        VisitValue(child, values, active, inheritedAwp);
                    }
                }
            }
            finally
            {
                if (tracked) active.Remove(value);
            }
        }

        private static void Visit(
            IDictionary<string, object> data,
            SortedDictionary<long, SortedSet<long>> values,
            HashSet<object> active,
            long? inheritedAwp)
        {
            long? effectiveAwp = inheritedAwp;
            if (data.TryGetValue("awp", out object rawAwp))
            {
                effectiveAwp = Convert.ToInt64(rawAwp);
            }

            if (data.TryGetValue("questID", out object rawQuestID))
            {
                long questID = Convert.ToInt64(rawQuestID);
                if (!values.ContainsKey(questID))
                {
                    values[questID] = new SortedSet<long>();
                }
                if (effectiveAwp.HasValue)
                {
                    values[questID].Add(effectiveAwp.Value);
                }
            }

            // ATT uses several collection implementations here, including
            // ConcurrentDataList. Walk every value rather than assuming that
            // groups are List<object>. The exported hierarchy is carried by
            // g (and the aqd/hqd child objects), so carry the consolidated awp
            // through those branches. __parent is parser bookkeeping, not the
            // final addon hierarchy; it can also point at a stale merge parent.
            foreach (var pair in data)
            {
                if (pair.Key == "__parent") continue;

                bool childIsInHierarchy = pair.Key == "g" || pair.Key == "aqd" || pair.Key == "hqd";
                VisitValue(
                    pair.Value,
                    values,
                    active,
                    childIsInHierarchy ? effectiveAwp : null);
            }
        }

        private sealed class ReferenceEqualityComparer : IEqualityComparer<object>
        {
            public static readonly ReferenceEqualityComparer Instance = new ReferenceEqualityComparer();

            public new bool Equals(object x, object y)
            {
                return ReferenceEquals(x, y);
            }

            public int GetHashCode(object obj)
            {
                return RuntimeHelpers.GetHashCode(obj);
            }
        }

    }
}
